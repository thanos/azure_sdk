defmodule AzureSDK.Storage.Operation do
  @moduledoc false
  # Shared plumbing for Storage service modules: request building, paths,
  # response headers, option validation, and paged listing.

  alias AzureSDK.Core.{Pipeline, Request, Response}
  alias AzureSDK.Error
  alias AzureSDK.Storage.{Client, Path}

  @doc """
  Builds a Storage request and runs it through the pipeline.

  `fields` are `AzureSDK.Core.Request` fields. `x-ms-version` is added to the
  headers, the client's signing metadata is merged under `:metadata`, and
  `:service` defaults to `:blob`.
  """
  @spec run(Client.t(), keyword()) :: {:ok, Response.t()} | {:error, Error.t()}
  def run(%Client{} = client, fields) when is_list(fields) do
    headers =
      Map.merge(%{"x-ms-version" => client.api_version}, Keyword.get(fields, :headers, %{}))

    metadata = Map.merge(Client.signing_metadata(client), Keyword.get(fields, :metadata, %{}))

    request =
      fields
      |> Keyword.put(:headers, headers)
      |> Keyword.put(:metadata, metadata)
      |> Keyword.put_new(:service, :blob)
      |> Request.new()

    Pipeline.run(Client.to_core_client(client), request)
  end

  @doc """
  URL path for a blob. `/` in the blob name separates encoded path segments.
  """
  @spec blob_path(String.t(), String.t()) :: String.t()
  def blob_path(container, name) do
    Path.join([container | String.split(name, "/")])
  end

  @doc """
  URL path for a queue resource.
  """
  @spec queue_path(String.t()) :: String.t()
  def queue_path(queue) when is_binary(queue) do
    Path.join([queue])
  end

  @doc """
  URL path for the messages resource of a queue.
  """
  @spec queue_messages_path(String.t()) :: String.t()
  def queue_messages_path(queue) when is_binary(queue) do
    Path.join([queue, "messages"])
  end

  @doc """
  URL path for a single queue message.
  """
  @spec queue_message_path(String.t(), String.t()) :: String.t()
  def queue_message_path(queue, message_id)
      when is_binary(queue) and is_binary(message_id) do
    Path.join([queue, "messages", message_id])
  end

  @doc """
  Reads a response header by name (response headers are lowercased).
  """
  @spec header(Response.t(), String.t()) :: String.t() | nil
  def header(%Response{headers: headers}, name) do
    Map.get(headers, String.downcase(name))
  end

  @doc """
  Puts `to_string(value)` under `key` unless `value` is `nil`.
  """
  @spec put_present(map(), String.t(), term()) :: map()
  def put_present(map, _key, nil), do: map
  def put_present(map, key, value), do: Map.put(map, key, to_string(value))

  @doc """
  Appends optional query pairs, skipping `nil` and `""` values.
  """
  @spec maybe_query([{String.t(), String.t()}], String.t(), term()) ::
          [{String.t(), String.t()}]
  def maybe_query(query, _key, nil), do: query
  def maybe_query(query, _key, ""), do: query
  def maybe_query(query, key, value), do: query ++ [{key, to_string(value)}]

  @doc """
  Query pairs for the `:marker`, `:max_results` and `:prefix` list options.
  """
  @spec list_query(keyword()) :: [{String.t(), String.t()}]
  def list_query(opts) do
    []
    |> maybe_query("marker", Keyword.get(opts, :marker))
    |> maybe_query("maxresults", Keyword.get(opts, :max_results))
    |> maybe_query("prefix", Keyword.get(opts, :prefix))
  end

  @doc """
  `nil` for `nil` or `""`, otherwise the value.
  """
  @spec blank_to_nil(String.t() | nil) :: String.t() | nil
  def blank_to_nil(value) when value in [nil, ""], do: nil
  def blank_to_nil(value), do: value

  @doc """
  Fetches required options, returning `InvalidArgument` when any is missing.
  """
  @spec require_opts(keyword(), [atom()], atom()) :: {:ok, map()} | {:error, Error.t()}
  def require_opts(opts, keys, service) do
    case Enum.reject(keys, &Keyword.has_key?(opts, &1)) do
      [] ->
        {:ok, Map.new(keys, &{&1, Keyword.fetch!(opts, &1)})}

      missing ->
        {:error,
         Error.new(
           code: "InvalidArgument",
           message: "Missing required option(s): #{Enum.map_join(missing, ", ", &inspect/1)}",
           service: service
         )}
    end
  end

  @doc """
  Collects every page returned by `fetch_page` (called with `nil`, then each marker).
  """
  @spec collect_pages((String.t() | nil -> {:ok, map()} | {:error, Error.t()})) ::
          {:ok, list()} | {:error, Error.t()}
  def collect_pages(fetch_page), do: collect_pages(fetch_page, nil, [])

  defp collect_pages(fetch_page, marker, pages) do
    case fetch_page.(marker) do
      {:ok, %{items: items, marker: nil}} ->
        {:ok, [items | pages] |> Enum.reverse() |> Enum.concat()}

      {:ok, %{items: items, marker: next}} ->
        collect_pages(fetch_page, next, [items | pages])

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Lazily streams items across pages. A failed page raises `error_module` with
  the `AzureSDK.Error` as `:reason`.
  """
  @spec page_stream((String.t() | nil -> {:ok, map()} | {:error, Error.t()}), module()) ::
          Enumerable.t()
  def page_stream(fetch_page, error_module) do
    Stream.resource(
      fn -> {:next, nil} end,
      fn
        :done ->
          {:halt, :done}

        {:next, marker} ->
          case fetch_page.(marker) do
            {:ok, %{items: items, marker: nil}} -> {items, :done}
            {:ok, %{items: items, marker: next}} -> {items, {:next, next}}
            {:error, reason} -> raise error_module, reason: reason
          end
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  RFC 1123 HTTP-date for a `DateTime` (converted to UTC).
  """
  @spec http_date(DateTime.t()) :: String.t()
  def http_date(%DateTime{} = dt) do
    dt |> to_utc() |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
  end

  @doc """
  ISO 8601 UTC timestamp with second precision (`2030-01-01T00:00:00Z`).
  """
  @spec iso8601_utc(DateTime.t()) :: String.t()
  def iso8601_utc(%DateTime{} = dt) do
    dt |> to_utc() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp to_utc(dt), do: dt |> DateTime.to_unix(:microsecond) |> DateTime.from_unix!(:microsecond)
end
