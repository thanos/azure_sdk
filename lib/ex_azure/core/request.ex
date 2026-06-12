defmodule ExAzure.Core.Request do
  @moduledoc """
  Service-agnostic HTTP request representation consumed by the ExAzure pipeline.
  """

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
  """
  @spec new(keyword()) :: t()
  def new(fields) do
    struct!(__MODULE__, normalize_fields(fields))
  end

  @doc """
  Sets or replaces a header value.
  """
  @spec put_header(t(), String.t(), String.t()) :: t()
  def put_header(%__MODULE__{} = request, key, value) do
    %{request | headers: Map.put(request.headers, key, value)}
  end

  @doc """
  Merges headers into the request.
  """
  @spec merge_headers(t(), map()) :: t()
  def merge_headers(%__MODULE__{} = request, headers) do
    %{request | headers: Map.merge(request.headers, headers)}
  end

  @doc """
  Appends query parameters.
  """
  @spec append_query(t(), [{String.t(), String.t()}]) :: t()
  def append_query(%__MODULE__{} = request, params) do
    %{request | query: request.query ++ params}
  end

  @doc """
  Returns the full URL path including query string.
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
