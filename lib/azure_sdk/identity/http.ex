defmodule AzureSDK.Identity.Http do
  @moduledoc false

  alias AzureSDK.Error
  alias AzureSDK.Identity.AccessToken

  @doc """
  POSTs form-encoded body to a token endpoint and parses an AccessToken.
  """
  @spec post_form(String.t(), map(), keyword()) ::
          {:ok, AccessToken.t()} | {:error, Error.t()}
  def post_form(url, form, opts \\ []) do
    headers =
      [{"content-type", "application/x-www-form-urlencoded"}]
      |> Kernel.++(Keyword.get(opts, :headers, []))

    req_opts =
      [
        method: :post,
        url: url,
        headers: headers,
        form: form,
        decode_body: true,
        retry: false
      ]
      |> Keyword.merge(Keyword.get(opts, :req_options, []))

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        body
        |> normalize_body()
        |> AccessToken.from_response()

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, token_error(status, body)}

      {:error, exception} ->
        {:error, Error.from_exception(:identity, exception)}
    end
  rescue
    exception ->
      {:error, Error.from_exception(:identity, exception)}
  end

  @doc """
  GETs a token from IMDS-style endpoints.
  """
  @spec get_json(String.t(), keyword()) :: {:ok, AccessToken.t()} | {:error, Error.t()}
  def get_json(url, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])

    req_opts =
      [
        method: :get,
        url: url,
        headers: headers,
        decode_body: true,
        retry: false
      ]
      |> Keyword.merge(Keyword.get(opts, :req_options, []))

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        body
        |> normalize_body()
        |> AccessToken.from_response()

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, token_error(status, body)}

      {:error, exception} ->
        {:error, Error.from_exception(:identity, exception)}
    end
  rescue
    exception ->
      {:error, Error.from_exception(:identity, exception)}
  end

  defp normalize_body(body) when is_map(body), do: stringify_keys(body)

  defp normalize_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} when is_map(map) -> stringify_keys(map)
      _ -> %{}
    end
  end

  defp normalize_body(_), do: %{}

  defp stringify_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {to_string(k), v}
    end)
  end

  defp token_error(status, body) do
    parsed = normalize_body(body)

    Error.new(
      status: status,
      code: parsed["error"] || parsed["error_codes"] || "TokenAcquisitionFailed",
      message:
        parsed["error_description"] || parsed["error_message"] || parsed["message"] ||
          "Token acquisition failed with HTTP #{status}",
      service: :identity,
      details: parsed
    )
  end
end
