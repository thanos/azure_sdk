defmodule AzureSDK.Core.Pipeline do
  @moduledoc """
  Request pipeline shared by Azure service clients.

  Flow:

      Authorize → Telemetry attempt → Transport (Req) → Retry / 401 refresh

  Authorization:

  * `TokenCredential` — `TokenCache.fetch/3` then `AzureSDK.Pipeline.Bearer`
  * `Credential` with `authorize_request/2` — Shared Key or SAS
  * no credential — request sent unchanged

  Retry covers HTTP 408/429/5xx and idempotent transport errors. A single
  force-refresh is attempted on HTTP 401 for token credentials.

  ## Options

  Passed through `run/3`:

  * `:scopes` — OAuth scopes for token credentials
  * `:server` / `:buffer_seconds` / `:force_refresh` — TokenCache options
  * other keys — merged into Req options

  ## Returns

  * `{:ok, %AzureSDK.Core.Response{}}` — HTTP 2xx
  * `{:error, %AzureSDK.Error{}}` — auth failure, non-2xx after retries, or transport error

  Does not raise for expected Azure or transport failures (exceptions are wrapped).

  ## Examples

      client = AzureSDK.Storage.Client.to_core_client(storage_client)

      request =
        AzureSDK.Core.Request.new(
          method: :get,
          path: "/",
          query: [{"comp", "list"}],
          headers: %{"x-ms-version" => storage_client.api_version},
          service: :blob,
          operation: :list_containers,
          metadata: AzureSDK.Storage.Client.signing_metadata(storage_client)
        )

      {:ok, response} = AzureSDK.Core.Pipeline.run(client, request)
  """

  alias AzureSDK.Core.{Client, Request, Response, Retry, Telemetry}
  alias AzureSDK.Error
  alias AzureSDK.Identity.{TokenCache, TokenCredential}
  alias AzureSDK.Pipeline.Bearer

  @default_storage_scope "https://storage.azure.com/.default"

  @doc """
  Executes a request through the pipeline.

  ## Parameters

  * `client` — `AzureSDK.Core.Client`
  * `request` — `AzureSDK.Core.Request`
  * `opts` — scopes, TokenCache options, and/or Req options (see module docs)

  ## Returns

  * `{:ok, %AzureSDK.Core.Response{}}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, response} = AzureSDK.Core.Pipeline.run(core_client, request)
      {:error, %AzureSDK.Error{status: 404}} = AzureSDK.Core.Pipeline.run(core_client, missing)
  """
  @spec run(Client.t(), Request.t(), keyword()) :: {:ok, Response.t()} | {:error, Error.t()}
  def run(%Client{} = client, %Request{} = request, opts \\ []) do
    metadata = %{
      service: request.service,
      operation: request.operation,
      method: request.method,
      path: request.path
    }

    Telemetry.span(metadata, fn ->
      execute_with_retry(client, request, opts, metadata, 1, false)
    end)
  end

  defp execute_with_retry(client, request, opts, metadata, attempt, refreshed?) do
    case authorize(request, client, opts) do
      {:ok, authorized} ->
        authorized
        |> AzureSDK.Pipeline.Telemetry.apply(metadata)
        |> then(&dispatch_transport(client, &1, request, opts, metadata, attempt, refreshed?))

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp dispatch_transport(client, authorized, request, opts, metadata, attempt, refreshed?) do
    case transport(client, authorized, opts) do
      {:ok, %Response{status: 401} = response} when not refreshed? ->
        maybe_refresh_and_retry(client, request, opts, metadata, attempt, response)

      {:ok, %Response{} = response} ->
        maybe_retry_response(client, request, opts, metadata, attempt, refreshed?, response)

      {:error, %Error{} = error} ->
        maybe_retry_transport(client, request, opts, metadata, attempt, refreshed?, error)
    end
  end

  defp maybe_retry_response(client, request, opts, metadata, attempt, refreshed?, response) do
    if Retry.retryable?(response) and attempt < client.retry.max_attempts do
      Retry.backoff(client.retry, attempt, metadata, response)
      execute_with_retry(client, request, opts, metadata, attempt + 1, refreshed?)
    else
      handle_response(response)
    end
  end

  defp maybe_retry_transport(client, request, opts, metadata, attempt, refreshed?, error) do
    if Retry.retry_transport?(request, error) and attempt < client.retry.max_attempts do
      Retry.backoff(client.retry, attempt, metadata)
      execute_with_retry(client, request, opts, metadata, attempt + 1, refreshed?)
    else
      {:error, error}
    end
  end

  defp maybe_refresh_and_retry(client, request, opts, metadata, attempt, response) do
    case client.credential do
      %mod{} = cred ->
        if TokenCredential.token_credential?(mod) do
          scopes = scopes_for(request, opts)
          _ = TokenCache.invalidate(cred, scopes, cache_opts(opts))
          execute_with_retry(client, request, opts, metadata, attempt, true)
        else
          handle_response(response)
        end

      _ ->
        handle_response(response)
    end
  end

  defp authorize(request, %Client{credential: %mod{} = cred}, opts) when not is_nil(cred) do
    cond do
      TokenCredential.token_credential?(mod) ->
        scopes = scopes_for(request, opts)

        with {:ok, token} <- TokenCache.fetch(cred, scopes, cache_opts(opts)) do
          {:ok, Bearer.apply(request, token)}
        end

      function_exported?(mod, :authorize_request, 2) ->
        mod.authorize_request(cred, request)

      true ->
        {:error,
         Error.new(
           code: "UnsupportedCredential",
           message:
             "Credential #{inspect(mod)} does not implement authorize_request/2 or get_token/3",
           service: request.service
         )}
    end
  end

  defp authorize(request, _, _), do: {:ok, request}

  defp scopes_for(request, opts) do
    Keyword.get(opts, :scopes) ||
      Map.get(request.metadata, :scopes) ||
      [@default_storage_scope]
  end

  defp cache_opts(opts) do
    Keyword.take(opts, [:server, :buffer_seconds, :force_refresh])
  end

  defp transport(%Client{} = client, %Request{} = request, opts) do
    url = build_url(client, request)
    req_opts = build_req_opts(client, request, url, opts)

    try do
      case Req.request(req_opts) do
        {:ok, %Req.Response{} = resp} ->
          {:ok, Response.from_req(resp, request)}

        {:error, exception} ->
          {:error, Error.from_exception(request.service, exception)}
      end
    rescue
      exception ->
        {:error, Error.from_exception(request.service, exception)}
    end
  end

  defp build_url(%Client{endpoint: endpoint}, %Request{} = request) when is_binary(endpoint) do
    base = String.trim_trailing(endpoint, "/")
    path = request.path |> String.trim_leading("/")
    url_path = Request.url_path(%{request | path: "/" <> path})
    base <> url_path
  end

  defp handle_response(%Response{status: status} = response) when status in 200..299 do
    {:ok, response}
  end

  defp handle_response(%Response{} = response) do
    service =
      case response.request do
        %Request{service: service} -> service
        _ -> :unknown
      end

    {:error, Error.from_response(service, response.status, response.headers, response.body)}
  end

  defp build_req_opts(%Client{req_options: client_opts}, %Request{} = request, url, opts) do
    base = [
      method: request.method,
      url: url,
      headers: Map.to_list(request.headers),
      retry: false,
      decode_body: false,
      compressed: false
    ]

    base =
      cond do
        not is_nil(request.stream) ->
          Keyword.put(base, :body, request.stream)

        not is_nil(request.body) ->
          Keyword.put(base, :body, request.body)

        true ->
          base
      end

    req_opts = Keyword.drop(opts, [:scopes, :server, :buffer_seconds, :force_refresh])

    base
    |> Keyword.merge(client_opts)
    |> Keyword.merge(req_opts)
  end
end
