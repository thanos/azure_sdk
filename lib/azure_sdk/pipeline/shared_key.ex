defmodule AzureSDK.Pipeline.SharedKey do
  @moduledoc false

  alias AzureSDK.Core.Request

  @doc """
  Signs a storage request using Shared Key authorization.
  """
  @spec apply(Request.t(), AzureSDK.Identity.SharedKeyCredential.t()) :: Request.t()
  def apply(%Request{} = request, %AzureSDK.Identity.SharedKeyCredential{} = credential) do
    request =
      request
      |> ensure_ms_headers()
      |> remove_empty_headers()

    signature = sign(request, credential)

    request
    |> Request.put_header(
      "Authorization",
      "SharedKey #{credential.account}:#{signature}"
    )
    |> tap(fn _ ->
      AzureSDK.Core.Telemetry.emit_sign(%{
        scheme: :shared_key,
        account: credential.account,
        service: request.service,
        operation: request.operation
      })
    end)
  end

  @doc """
  Builds the Shared Key string-to-sign. Exposed for testing.
  """
  @spec string_to_sign(Request.t(), String.t()) :: String.t()
  def string_to_sign(%Request{} = request, account) do
    headers = request.headers
    path_style? = Map.get(request.metadata, :path_style, false)

    [
      request.method |> Atom.to_string() |> String.upcase(),
      Map.get(headers, "Content-Encoding", ""),
      Map.get(headers, "Content-Language", ""),
      content_length_for_sign(headers),
      Map.get(headers, "Content-MD5", ""),
      Map.get(headers, "Content-Type", ""),
      Map.get(headers, "Date", ""),
      Map.get(headers, "If-Modified-Since", ""),
      Map.get(headers, "If-Match", ""),
      Map.get(headers, "If-None-Match", ""),
      Map.get(headers, "If-Unmodified-Since", ""),
      Map.get(headers, "Range", ""),
      canonicalized_headers(headers),
      canonicalized_resource(account, request.path, request.query, path_style?)
    ]
    |> Enum.join("\n")
  end

  defp sign(request, credential) do
    string = string_to_sign(request, credential.account)

    :crypto.mac(:hmac, :sha256, Base.decode64!(credential.key), string)
    |> Base.encode64()
  end

  defp ensure_ms_headers(request) do
    date = Map.get(request.headers, "x-ms-date", http_date())

    request
    |> Request.put_header("x-ms-date", date)
    |> Request.put_header("x-ms-version", default_api_version(request))
  end

  defp remove_empty_headers(%Request{headers: headers} = request) do
    cleaned =
      headers
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()

    %{request | headers: cleaned}
  end

  defp canonicalized_headers(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(k), v} end)
    |> Enum.filter(fn {k, _} -> String.starts_with?(k, "x-ms-") end)
    |> Enum.sort()
    |> Enum.map_join("\n", fn {k, v} -> "#{k}:#{v}" end)
  end

  defp canonicalized_resource(account, path, query, path_style?) do
    account = account |> String.replace("-secondary", "")
    normalized_path = if String.starts_with?(path, "/"), do: path, else: "/" <> path

    resource_path =
      if path_style? do
        "/#{account}/#{account}#{normalized_path}"
      else
        "/#{account}#{normalized_path}"
      end

    sorted_query =
      query
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join("\n", fn {k, v} -> "#{k}:#{v}" end)

    case sorted_query do
      "" -> resource_path
      qs -> resource_path <> "\n" <> qs
    end
  end

  defp default_api_version(request) do
    Map.get(
      request.headers,
      "x-ms-version",
      Map.get(request.metadata, :api_version, "2024-11-04")
    )
  end

  defp http_date do
    Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S GMT")
  end

  # Azure treats zero-length Content-Length as empty in the string-to-sign.
  defp content_length_for_sign(headers) do
    case Map.get(headers, "Content-Length", "") do
      "0" -> ""
      value -> value
    end
  end
end
