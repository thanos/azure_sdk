defmodule AzureSDK.Identity.Http do
  @moduledoc false

  alias AzureSDK.Error
  alias AzureSDK.Identity.AccessToken

  @doc """
  Builds the Entra v2 token endpoint URL for a tenant.
  """
  @spec token_url(String.t(), String.t()) :: String.t()
  def token_url(authority_host, tenant_id) do
    String.trim_trailing(authority_host, "/") <> "/#{tenant_id}/oauth2/v2.0/token"
  end

  @doc """
  POSTs form-encoded body to a token endpoint and parses an AccessToken.
  """
  @spec post_form(String.t(), map(), keyword()) ::
          {:ok, AccessToken.t()} | {:error, Error.t()}
  def post_form(url, form, opts \\ []) do
    headers = [
      {"content-type", "application/x-www-form-urlencoded"} | Keyword.get(opts, :headers, [])
    ]

    request([method: :post, url: url, headers: headers, form: form], opts)
  end

  @doc """
  GETs a token from IMDS-style endpoints.
  """
  @spec get_json(String.t(), keyword()) :: {:ok, AccessToken.t()} | {:error, Error.t()}
  def get_json(url, opts \\ []) do
    request([method: :get, url: url, headers: Keyword.get(opts, :headers, [])], opts)
  end

  defp request(base, opts) do
    req_opts =
      base
      |> Keyword.merge(decode_body: true, retry: false)
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
      code: error_code(parsed["error"]),
      message:
        parsed["error_description"] || parsed["error_message"] || parsed["message"] ||
          "Token acquisition failed with HTTP #{status}",
      service: :identity,
      details: parsed
    )
  end

  defp error_code(code) when is_binary(code) and code != "", do: code
  defp error_code(_), do: "TokenAcquisitionFailed"
end
