defmodule AzureSDK.Core.Response do
  @moduledoc """
  Normalized HTTP response returned by `AzureSDK.Core.Pipeline`.

  ## Fields

  * `:status` - HTTP status code
  * `:headers` - lowercased header map with single string values
  * `:body` - response body as a binary, or `nil`
  * `:request` - originating `AzureSDK.Core.Request` when available

  ## Examples

      iex> resp = %AzureSDK.Core.Response{status: 200, headers: %{}, body: "ok"}
      iex> AzureSDK.Core.Response.success?(resp)
      true
  """

  @typedoc "HTTP response struct. See the module documentation for field meanings."
  @type t :: %__MODULE__{
          status: non_neg_integer(),
          headers: map(),
          body: binary() | nil,
          request: AzureSDK.Core.Request.t() | nil
        }

  defstruct [:status, :headers, :body, :request]

  @doc """
  Builds a response from a `Req.Response`.

  ## Parameters

  * `resp` - Req response
  * `request` - optional originating request (default `nil`)

  ## Returns

  `%AzureSDK.Core.Response{}` with normalized headers and binary body.

  ## Examples

      iex> req_resp = %Req.Response{status: 201, headers: %{"ETag" => "\\"1\\""}, body: ""}
      iex> resp = AzureSDK.Core.Response.from_req(req_resp)
      iex> {resp.status, resp.headers["etag"]}
      {201, "\\"1\\""}
  """
  @spec from_req(Req.Response.t(), AzureSDK.Core.Request.t() | nil) :: t()
  def from_req(%Req.Response{status: status, headers: headers, body: body}, request \\ nil) do
    %__MODULE__{
      status: status,
      headers: normalize_headers(headers),
      body: normalize_body(body),
      request: request
    }
  end

  @doc """
  Returns `true` when the status is in the 2xx range.

  ## Examples

      iex> AzureSDK.Core.Response.success?(%AzureSDK.Core.Response{status: 204})
      true
      iex> AzureSDK.Core.Response.success?(%AzureSDK.Core.Response{status: 404})
      false
  """
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{status: status}) when status in 200..299, do: true
  def success?(_), do: false

  defp normalize_headers(headers) when is_map(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(k), header_value(v)} end)
    |> Map.new()
  end

  defp normalize_headers(headers) when is_list(headers) do
    headers
    |> Enum.group_by(fn {k, _} -> String.downcase(k) end, fn {_, v} -> header_value(v) end)
    |> Map.new(fn {k, values} -> {k, List.last(values)} end)
  end

  defp header_value(values) when is_list(values), do: List.last(values)
  defp header_value(value), do: value

  defp normalize_body(body) when is_binary(body), do: body
  defp normalize_body(body) when is_nil(body), do: nil
  defp normalize_body(body), do: IO.iodata_to_binary(body)
end
