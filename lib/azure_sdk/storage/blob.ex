defmodule AzureSDK.Storage.Blob do
  @moduledoc """
  Azure Blob Storage operations.

  `upload/5` uses a single Put Blob. `upload_stream/5` stages blocks with Put
  Block / Put Block List so only one chunk is held in memory at a time.
  `download_stream/4` fetches the blob with HTTP Range requests.

  ## Blob map (`t:blob/0`)

      %{
        container: "uploads",
        name: "file.txt",
        properties: %{
          content_type: "text/plain",
          content_length: 5,
          etag: "\\"0x8D…\\"",
          last_modified: "Wed, 01 Jan 2025 00:00:00 GMT"
        },
        metadata: %{"owner" => "app"},
        content: "hello"
      }

  ## Errors

  Failures return `{:error, %AzureSDK.Error{}}`. Mid-stream range failures in
  `download_stream/4` raise `AzureSDK.Storage.Blob.StreamError`. Functions do
  not raise for ordinary Azure HTTP failures on non-stream APIs.

  ## Condition and lease options

  Most write/read helpers accept `AzureSDK.Storage.Conditions` opts:
  `:if_match`, `:if_none_match`, `:if_modified_since`, `:if_unmodified_since`,
  `:lease_id`.
  """

  alias AzureSDK.Core.{Pipeline, Request, Response, Telemetry}
  alias AzureSDK.Storage.Blob.Block
  alias AzureSDK.Storage.{Client, Conditions, Metadata, Path}

  @default_chunk_size 4 * 1024 * 1024

  @typedoc """
  Blob result map.

  * `:container` / `:name` - identity
  * `:properties` - `content_type`, `content_length`, `etag`, `last_modified`
  * `:metadata` - user metadata (keys without `x-ms-meta-` prefix)
  * `:content` - binary body, or `nil` when `:include_content` is `false`
  """
  @type blob :: %{
          container: String.t(),
          name: String.t(),
          properties: map(),
          metadata: map(),
          content: binary() | nil
        }

  @doc """
  Uploads a blob from binary or iodata content (single Put Blob).

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `container` - container name
  * `name` - blob name
  * `content` - binary or iodata
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:content_type` - defaults to `"application/octet-stream"`
  * `:blob_type` - defaults to `"BlockBlob"`
  * `:metadata` - string-keyed user metadata
  * `:include_content` - when `false`, returned `:content` is `nil` (default `true`)
  * condition / lease opts from `AzureSDK.Storage.Conditions`

  ## Examples

      {:ok, blob} =
        AzureSDK.Storage.Blob.upload(client, "uploads", "hello.txt", "hello")

      {:ok, blob} =
        AzureSDK.Storage.Blob.upload(client, "uploads", "hello.txt", ["hel", "lo"],
          content_type: "text/plain",
          blob_type: "BlockBlob",
          metadata: %{"owner" => "app"},
          include_content: false,
          if_none_match: "*"
        )
  """
  @spec upload(Client.t(), String.t(), String.t(), iodata(), keyword()) ::
          {:ok, blob()} | {:error, AzureSDK.Error.t()}
  def upload(client, container, name, content, opts \\ []) do
    Telemetry.emit_operation(:blob, :put, %{container: container, name: name})

    content = IO.iodata_to_binary(content)
    headers = upload_headers(client, opts, byte_size(content))

    request =
      Request.new(
        method: :put,
        path: blob_path(container, name),
        headers: headers,
        body: content,
        service: :blob,
        operation: :put,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, blob_from_response(container, name, response, content, opts)}
    end
  end

  @doc """
  Uploads a blob from an enumerable using Put Block / Put Block List.

  Only one `:block_size` chunk is buffered at a time. An empty enumerable falls
  back to `upload/5` with an empty body. Returned `:content` is always `nil`.

  ## Parameters

  * `client`, `container`, `name` - as in `upload/5`
  * `stream` - `Enumerable` of binaries / iodata chunks
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:block_size` - max bytes per staged block (default 4 MiB)
  * `:content_type` - blob content type on commit
  * `:metadata` - string-keyed user metadata
  * condition / lease opts from `AzureSDK.Storage.Conditions`

  On mid-stream failure, staged uncommitted blocks may remain on the service.

  ## Examples

      stream = File.stream!("large.bin", [], 64 * 1024)

      {:ok, blob} =
        AzureSDK.Storage.Blob.upload_stream(client, "uploads", "large.bin", stream,
          block_size: 4 * 1024 * 1024,
          content_type: "application/octet-stream",
          metadata: %{"source" => "disk"}
        )
  """
  @spec upload_stream(Client.t(), String.t(), String.t(), Enumerable.t(), keyword()) ::
          {:ok, blob()} | {:error, AzureSDK.Error.t()}
  def upload_stream(client, container, name, stream, opts \\ []) do
    block_size = Keyword.get(opts, :block_size, @default_chunk_size)

    Telemetry.emit_operation(:blob, :put, %{
      container: container,
      name: name,
      streaming: true
    })

    case stage_blocks(client, container, name, stream, block_size, opts) do
      {:ok, [], 0} ->
        upload(client, container, name, "", opts)

      {:ok, block_ids, total_size} ->
        with {:ok, props} <- Block.put_block_list(client, container, name, block_ids, opts) do
          {:ok,
           %{
             container: container,
             name: name,
             properties: %{
               content_type: Keyword.get(opts, :content_type),
               content_length: total_size,
               etag: props.etag,
               last_modified: props.last_modified
             },
             metadata: Keyword.get(opts, :metadata, %{}),
             content: nil
           }}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Downloads a blob and returns its content.

  ## Parameters

  * `client`, `container`, `name` - as in `upload/5`
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:include_content` - when `false`, `:content` is `nil` (default `true`)
  * `:range` - `{start, finish}` inclusive byte offsets for a single Range GET
  * condition / lease opts from `AzureSDK.Storage.Conditions`

  ## Examples

      {:ok, %{content: body}} =
        AzureSDK.Storage.Blob.download(client, "uploads", "hello.txt")

      {:ok, %{content: slice}} =
        AzureSDK.Storage.Blob.download(client, "uploads", "hello.txt",
          range: {0, 3},
          if_match: etag
        )

      {:ok, %{content: nil}} =
        AzureSDK.Storage.Blob.download(client, "uploads", "hello.txt",
          include_content: false
        )
  """
  @spec download(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, blob()} | {:error, AzureSDK.Error.t()}
  def download(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :get, %{container: container, name: name})

    headers =
      client
      |> base_headers()
      |> Map.merge(Conditions.headers(opts))
      |> Map.merge(range_header(Keyword.get(opts, :range)))

    request =
      Request.new(
        method: :get,
        path: blob_path(container, name),
        headers: headers,
        service: :blob,
        operation: :get,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, blob_from_response(container, name, response, response.body, opts)}
    end
  end

  @doc """
  Downloads a blob as an enumerable of binaries via HTTP Range requests.

  ## Parameters

  * `client`, `container`, `name` - as in `upload/5`
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:chunk_size` - bytes per range request (default 4 MiB)
  * condition / lease opts from `AzureSDK.Storage.Conditions` (applied to each range GET)

  Mid-stream HTTP failures raise `AzureSDK.Storage.Blob.StreamError`.

  ## Examples

      {:ok, chunks} =
        AzureSDK.Storage.Blob.download_stream(client, "uploads", "large.bin",
          chunk_size: 1024 * 1024,
          lease_id: lease_id
        )

      IO.iodata_to_binary(Enum.to_list(chunks))
  """
  @spec download_stream(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, AzureSDK.Error.t()}
  def download_stream(client, container, name, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)

    case blob_size(client, container, name, opts) do
      {:ok, 0} ->
        {:ok, []}

      {:ok, size} ->
        {:ok, range_stream(client, container, name, opts, chunk_size, size)}

      {:error, _} = error ->
        error
    end
  end

  defp range_stream(client, container, name, opts, chunk_size, size) do
    Stream.resource(
      fn -> 0 end,
      fn offset -> next_range_chunk(client, container, name, opts, chunk_size, size, offset) end,
      fn _ -> :ok end
    )
  end

  defp next_range_chunk(_client, _container, _name, _opts, _chunk_size, size, offset)
       when offset >= size do
    {:halt, offset}
  end

  defp next_range_chunk(client, container, name, opts, chunk_size, size, offset) do
    finish = min(offset + chunk_size - 1, size - 1)

    case download(client, container, name, Keyword.put(opts, :range, {offset, finish})) do
      {:ok, %{content: content}} when is_binary(content) ->
        {[content], finish + 1}

      {:error, reason} ->
        raise AzureSDK.Storage.Blob.StreamError, reason: reason
    end
  end

  @doc """
  Deletes a blob.

  ## Parameters

  * `client`, `container`, `name` - as in `upload/5`
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * condition / lease opts from `AzureSDK.Storage.Conditions`

  ## Examples

      {:ok, :deleted} = AzureSDK.Storage.Blob.delete(client, "uploads", "hello.txt")

      {:ok, :deleted} =
        AzureSDK.Storage.Blob.delete(client, "uploads", "hello.txt",
          lease_id: lease_id,
          if_match: etag
        )
  """
  @spec delete(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, :deleted} | {:error, AzureSDK.Error.t()}
  def delete(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :delete, %{container: container, name: name})

    headers =
      client
      |> base_headers()
      |> Map.merge(Conditions.headers(opts))

    request =
      Request.new(
        method: :delete,
        path: blob_path(container, name),
        headers: headers,
        service: :blob,
        operation: :delete,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, _} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, :deleted}
    end
  end

  @doc """
  Returns blob user metadata (keys without the `x-ms-meta-` prefix).

  ## Parameters

  * `client`, `container`, `name` - as in `upload/5`
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * condition / lease opts from `AzureSDK.Storage.Conditions`

  ## Examples

      {:ok, %{"owner" => "app"}} =
        AzureSDK.Storage.Blob.metadata(client, "uploads", "hello.txt")

      {:ok, meta} =
        AzureSDK.Storage.Blob.metadata(client, "uploads", "hello.txt", lease_id: lease_id)
  """
  @spec metadata(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, AzureSDK.Error.t()}
  def metadata(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :metadata, %{container: container, name: name})

    headers =
      client
      |> base_headers()
      |> Map.merge(Conditions.headers(opts))

    request =
      Request.new(
        method: :head,
        path: blob_path(container, name),
        headers: headers,
        service: :blob,
        operation: :metadata,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, Metadata.from_headers(response.headers)}
    end
  end

  @doc """
  Sets blob metadata. Replaces all existing metadata keys.

  ## Parameters

  * `client`, `container`, `name` - as in `upload/5`
  * `metadata` - string-keyed map of user metadata
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * condition / lease opts from `AzureSDK.Storage.Conditions`

  ## Examples

      {:ok, %{"tier" => "hot"}} =
        AzureSDK.Storage.Blob.set_metadata(client, "uploads", "hello.txt", %{"tier" => "hot"})

      {:ok, meta} =
        AzureSDK.Storage.Blob.set_metadata(client, "uploads", "hello.txt", meta,
          if_match: etag,
          lease_id: lease_id
        )
  """
  @spec set_metadata(Client.t(), String.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, AzureSDK.Error.t()}
  def set_metadata(client, container, name, metadata, opts \\ []) do
    Telemetry.emit_operation(:blob, :set_metadata, %{container: container, name: name})

    headers =
      client
      |> base_headers()
      |> Map.merge(Metadata.headers(metadata))
      |> Map.merge(Conditions.headers(opts))

    request =
      Request.new(
        method: :put,
        path: blob_path(container, name),
        query: [{"comp", "metadata"}],
        headers: headers,
        service: :blob,
        operation: :set_metadata,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, _} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, metadata}
    end
  end

  defp stage_blocks(client, container, name, stream, block_size, opts) do
    stream
    |> chunk_iodata(block_size)
    |> Enum.reduce_while({:ok, [], 0, 0}, fn chunk, {:ok, ids, index, total} ->
      block_id = Block.block_id(index)

      case Block.put_block(client, container, name, block_id, chunk, opts) do
        {:ok, :staged} ->
          {:cont, {:ok, [block_id | ids], index + 1, total + byte_size(chunk)}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, ids, _index, total} -> {:ok, Enum.reverse(ids), total}
      {:error, _} = error -> error
    end
  end

  defp chunk_iodata(stream, block_size) do
    stream
    |> Stream.concat([:__done__])
    |> Stream.transform(<<>>, fn
      :__done__, <<>> ->
        {:halt, <<>>}

      :__done__, acc ->
        {[acc], <<>>}

      piece, acc ->
        data = IO.iodata_to_binary([acc, piece])
        flush_full_chunks(data, block_size)
    end)
  end

  defp flush_full_chunks(data, block_size) do
    do_flush(data, block_size, [])
  end

  defp do_flush(data, block_size, acc) when byte_size(data) >= block_size do
    <<chunk::binary-size(block_size), rest::binary>> = data
    do_flush(rest, block_size, [chunk | acc])
  end

  defp do_flush(data, _block_size, acc) do
    {Enum.reverse(acc), data}
  end

  defp blob_path(container, name) do
    Path.join([container | String.split(name, "/", parts: :infinity)])
  end

  defp upload_headers(client, opts, size) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    %{
      "x-ms-version" => client.api_version,
      "Content-Type" => content_type,
      "Content-Length" => Integer.to_string(size),
      "x-ms-blob-type" => Keyword.get(opts, :blob_type, "BlockBlob")
    }
    |> Map.merge(Metadata.headers(Keyword.get(opts, :metadata, %{})))
    |> Map.merge(Conditions.headers(opts))
  end

  defp base_headers(client) do
    %{"x-ms-version" => client.api_version}
  end

  defp range_header(nil), do: %{}

  defp range_header({start, finish}) when is_integer(start) and is_integer(finish) do
    %{"Range" => "bytes=#{start}-#{finish}"}
  end

  defp blob_size(client, container, name, opts) do
    headers =
      client
      |> base_headers()
      |> Map.merge(Conditions.headers(opts))

    request =
      Request.new(
        method: :head,
        path: blob_path(container, name),
        headers: headers,
        service: :blob,
        operation: :blob_size,
        metadata: Client.signing_metadata(client)
      )

    case Pipeline.run(Client.to_core_client(client), request) do
      {:ok, response} ->
        case parse_size_header(response) do
          {:ok, _} = ok -> ok
          :error -> probe_size_via_range(client, container, name, opts)
        end

      {:error, _} = error ->
        error
    end
  end

  defp parse_size_header(response) do
    cond do
      value = response_header(response, "x-ms-blob-content-length") ->
        {:ok, String.to_integer(to_string(value))}

      value = response_header(response, "content-length") ->
        {:ok, String.to_integer(to_string(value))}

      true ->
        :error
    end
  end

  defp probe_size_via_range(client, container, name, opts) do
    headers =
      client
      |> base_headers()
      |> Map.merge(Conditions.headers(opts))
      |> Map.merge(%{"Range" => "bytes=0-0"})

    request =
      Request.new(
        method: :get,
        path: blob_path(container, name),
        headers: headers,
        service: :blob,
        operation: :blob_size_probe,
        metadata: Client.signing_metadata(client)
      )

    case Pipeline.run(Client.to_core_client(client), request) do
      {:ok, response} -> {:ok, size_from_probe_response(response)}
      {:error, %{status: 416}} -> {:ok, 0}
      {:error, _} = error -> error
    end
  end

  defp size_from_probe_response(response) do
    case response_header(response, "content-range") do
      "bytes " <> rest ->
        case Regex.run(~r/\/(\d+)\z/, rest) do
          [_, total] -> String.to_integer(total)
          _ -> byte_size(response.body || "")
        end

      _ ->
        byte_size(response.body || "")
    end
  end

  defp blob_from_response(container, name, %Response{} = response, content, opts) do
    %{
      container: container,
      name: name,
      properties: %{
        content_type: response_header(response, "content-type"),
        content_length: content_length(response, content),
        etag: response_header(response, "etag"),
        last_modified: response_header(response, "last-modified")
      },
      metadata: Metadata.from_headers(response.headers),
      content: content_value(content, opts)
    }
  end

  defp content_value(content, opts) do
    if Keyword.get(opts, :include_content, true), do: content
  end

  defp response_header(%Response{headers: headers}, name) do
    Map.get(headers, name) || Map.get(headers, String.downcase(name))
  end

  defp content_length(_response, content) when is_binary(content), do: byte_size(content)
  defp content_length(response, _), do: response_header(response, "content-length")
end

defmodule AzureSDK.Storage.Blob.StreamError do
  @moduledoc """
  Raised when a mid-stream Range download fails inside `Blob.download_stream/4`.

  ## Fields

  * `:reason` - typically `%AzureSDK.Error{}` from a failed Range GET

  ## Examples

      try do
        {:ok, stream} = AzureSDK.Storage.Blob.download_stream(client, "c", "b.bin")
        Enum.to_list(stream)
      rescue
        e in AzureSDK.Storage.Blob.StreamError ->
          e.reason
      end
  """
  defexception [:reason]

  @impl true
  def message(%{reason: reason}), do: "blob stream failed: #{inspect(reason)}"
end
