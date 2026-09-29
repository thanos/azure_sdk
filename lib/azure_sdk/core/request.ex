defmodule AzureSDK.Core.Request do
  @moduledoc """
  Service-agnostic HTTP request consumed by `AzureSDK.Core.Pipeline`.

  ## Fields

  * `:method` - HTTP method atom (`:get`, `:put`, `:head`, …); default `:get`
  * `:path` - URL path beginning with `/`; default `"/"`
  * `:query` - list of `{name, value}` string pairs
  * `:headers` - map of header name to value
  * `:body` - request body as iodata, or `nil`
  * `:stream` - enumerable body stream, or `nil` (takes precedence over `:body` in the pipeline when set)
  * `:service` - logical service for telemetry/errors (`:blob`, `:identity`, …)
  * `:operation` - logical operation name for telemetry
  * `:metadata` - opaque map for signing and pipeline options (`:api_version`, `:path_style`, `:idempotent`, `:scopes`, …)

  ## Examples

      iex> req = AzureSDK.Core.Request.new(method: :get, path: "/uploads", service: :blob)
      iex> req.method
      :get
      iex> req.path
      "/uploads"
  """

  @typedoc "HTTP request struct. See the module documentation for field meanings."
  @type t :: %__MODULE__{
          method: atom(),
          path: String.t(),
          query: [{String.t(), String.t()}],
          headers: %{String.t() => String.t()},
          body: iodata() | nil,
          stream: Enumerable.t() | nil,
          service: atom(),
          operation: atom(),
          metadata: map()
        }

  defstruct method: :get,
            path: "/",
            query: [],
            headers: %{},
            body: nil,
            stream: nil,
            service: :unknown,
            operation: :request,
            metadata: %{}

  @doc """
  Creates a new request struct.

  ## Parameters

  * `fields` - keyword list of struct fields. A list of headers is accepted and
    converted to a map.

  ## Returns

  `%AzureSDK.Core.Request{}`. Raises `KeyError` for unknown keys.

  ## Examples

      iex> req = AzureSDK.Core.Request.new(method: :put, path: "/c/b", headers: [{"Content-Type", "text/plain"}])
      iex> req.headers["Content-Type"]
      "text/plain"
  """
  @spec new(keyword()) :: t()
  def new(fields) when is_list(fields) do
    struct!(__MODULE__, normalize_fields(fields))
  end

  @doc """
  Sets or replaces a single header.

  ## Examples

      iex> req = AzureSDK.Core.Request.new([]) |> AzureSDK.Core.Request.put_header("x-ms-version", "2024-11-04")
      iex> req.headers["x-ms-version"]
      "2024-11-04"
  """
  @spec put_header(t(), String.t(), String.t()) :: t()
  def put_header(%__MODULE__{} = request, key, value)
      when is_binary(key) and is_binary(value) do
    %{request | headers: Map.put(request.headers, key, value)}
  end

  @doc """
  Merges a header map into the request (right-hand values win).

  ## Examples

      iex> req = AzureSDK.Core.Request.new(headers: %{"a" => "1"})
      iex> AzureSDK.Core.Request.merge_headers(req, %{"a" => "2", "b" => "3"}).headers
      %{"a" => "2", "b" => "3"}
  """
  @spec merge_headers(t(), map()) :: t()
  def merge_headers(%__MODULE__{} = request, headers) when is_map(headers) do
    %{request | headers: Map.merge(request.headers, headers)}
  end

  @doc """
  Appends query parameters to the end of the existing query list.

  ## Examples

      iex> req = AzureSDK.Core.Request.new(query: [{"comp", "list"}])
      iex> AzureSDK.Core.Request.append_query(req, [{"marker", "abc"}]).query
      [{"comp", "list"}, {"marker", "abc"}]
  """
  @spec append_query(t(), [{String.t(), String.t()}]) :: t()
  def append_query(%__MODULE__{} = request, params) when is_list(params) do
    %{request | query: request.query ++ params}
  end

  @doc """
  Returns the path with an encoded query string when query params are present.

  ## Examples

      iex> AzureSDK.Core.Request.url_path(AzureSDK.Core.Request.new(path: "/c"))
      "/c"
      iex> req = AzureSDK.Core.Request.new(path: "/c", query: [{"restype", "container"}])
      iex> AzureSDK.Core.Request.url_path(req)
      "/c?restype=container"
  """
  @spec url_path(t()) :: String.t()
  def url_path(%__MODULE__{path: path, query: []}), do: path

  def url_path(%__MODULE__{path: path, query: query}) do
    encoded =
      query
      |> Enum.map_join("&", fn {k, v} ->
        "#{URI.encode_www_form(k)}=#{URI.encode_www_form(v)}"
      end)

    path <> "?" <> encoded
  end

  defp normalize_fields(fields) do
    Enum.map(fields, fn
      {:headers, headers} when is_list(headers) ->
        {:headers, Map.new(headers)}

      pair ->
        pair
    end)
  end
end
