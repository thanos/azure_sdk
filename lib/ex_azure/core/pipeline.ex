defmodule ExAzure.Core.Pipeline do
  @moduledoc """
  Reusable request pipeline for all Azure services.

  Flow:

      Credential → Signing → Retry → Telemetry → Transport (Req)
  """

  alias ExAzure.Core.{Client, Request, Response, Retry, Telemetry}
  alias ExAzure.Error
  alias ExAzure.Pipeline.SAS
  alias ExAzure.Pipeline.SharedKey

  @doc """
  Executes a request through the pipeline and returns `{:ok, response}` or `{:error, error}`.
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
      execute_with_retry(client, request, opts, metadata, 1)
    end)
  end

  defp execute_with_retry(client, request, opts, metadata, attempt) do
    signed =
      request
      |> sign(client)
      |> ExAzure.Pipeline.Telemetry.apply(metadata)

    case transport(client, signed, opts) do
      {:ok, %Response{} = response} ->
        if Retry.retryable?(response) and attempt < client.retry.max_attempts do
          Retry.backoff(client.retry, attempt, metadata)
          execute_with_retry(client, request, opts, metadata, attempt + 1)
        else
          handle_response(response)
        end

      {:error, %Error{} = error} ->
        if attempt < client.retry.max_attempts do
          Retry.backoff(client.retry, attempt, metadata)
          execute_with_retry(client, request, opts, metadata, attempt + 1)
        else
          {:error, error}
        end
    end
  end

  defp sign(request, %Client{credential: credential}) when not is_nil(credential) do
    case credential do
      %ExAzure.Identity.SharedKeyCredential{} ->
        SharedKey.apply(request, credential)

      %ExAzure.Identity.SASCredential{} ->
        SAS.apply(request, credential)

      _ ->
        ExAzure.Identity.Credential.sign_request(credential, request)
    end
  end

  defp sign(request, _), do: request

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
    headers =
      request.headers
      |> Map.to_list()
      |> Enum.map(fn {k, v} -> {k, v} end)

    base = [
      method: request.method,
      url: url,
      headers: headers,
      retry: false
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

    base
    |> Keyword.merge(client_opts)
    |> Keyword.merge(opts)
  end
end
