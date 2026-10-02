defmodule AzureSDK.Storage.Blob do
  @moduledoc """
  Azure Blob Storage operations.

  `upload/5` uses a single Put Blob. `upload_stream/5` stages blocks with Put
  Block / Put Block List so only one chunk is held in memory at a time.
  `download_stream/4` fetches the blob with HTTP Range requests, pinned to the
  ETag from an initial `properties/4` HEAD.

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

  ## Properties map (`t:properties/0`)

  Returned by `properties/4` (Blob HEAD; no body download):

      %{
        content_length: 1024,
        content_type: "application/octet-stream",
        etag: "\\"0x8D…\\"",
        last_modified: "Wed, 01 Jan 2025 00:00:00 GMT",
        metadata: %{"owner" => "app"}
      }

  Typical ETag-guarded range read:

      {:ok, props} = AzureSDK.Storage.Blob.properties(client, container, blob)

      {:ok, %{content: bytes}} =
        AzureSDK.Storage.Blob.download(
          client,
          container,
          blob,
          range: {offset, offset + length - 1},
          if_match: props.etag
        )

  ## Errors

  Failures return `{:error, %AzureSDK.Error{}}`. The one exception is
  enumerating the stream from `download_stream/4`: a failed range raises
  `AzureSDK.Storage.Blob.StreamError`.

  ## Condition and lease options

  Most write/read helpers accept `AzureSDK.Storage.Conditions` opts:
  `:if_match`, `:if_none_match`, `:if_modified_since`, `:if_unmodified_since`,
  `:lease_id`.
  """

  alias AzureSDK.Core.{Response, Telemetry}
  alias AzureSDK.Error
  alias AzureSDK.Storage.Blob.Block
  alias AzureSDK.Storage.{Client, Conditions, Metadata, Operation}

  @default_chunk_size 4 * 1024 * 1024
  @default_content_type "application/octet-stream"
  @max_blocks 50_000

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

  @typedoc """
  Blob properties from `properties/4` (HEAD / Get Blob Properties).

  * `:content_length` - size in bytes (integer)
  * `:content_type` - content type when the service returns it
  * `:etag` - ETag exactly as Azure returns it
  * `:last_modified` - RFC 1123 last-modified when present
  * `:metadata` - user metadata without the `x-ms-meta-` prefix
  """
  @type properties :: %{
          content_length: non_neg_integer(),
          content_type: String.t() | nil,
          etag: String.t() | nil,
          last_modified: String.t() | nil,
          metadata: map()
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

    with {:ok, response} <-
           Operation.run(client,
             method: :put,
             path: Operation.blob_path(container, name),
             headers: upload_headers(opts, byte_size(content)),
             body: content,
             operation: :put
           ) do
      {:ok, blob_from_response(container, name, response, content, opts)}
    end
  end

  @doc """
  Uploads a blob from an enumerable using Put Block / Put Block List.

  Only one `:block_size` chunk is buffered at a time. Each call stages blocks
  under a fresh random block-ID prefix, so concurrent uploads to the same blob
  cannot mix blocks; the last commit wins. An empty enumerable falls back to
  `upload/5` with an empty body. Returned `:content` is always `nil`.

  ## Parameters

  * `client`, `container`, `name` - as in `upload/5`
  * `stream` - `Enumerable` of binaries / iodata chunks
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:block_size` - max bytes per staged block (default 4 MiB)
  * `:content_type` - blob content type on commit (default `"application/octet-stream"`)
  * `:metadata` - string-keyed user metadata
  * condition / lease opts from `AzureSDK.Storage.Conditions`. `If-*` conditions
    apply to the final commit; `:lease_id` is sent with every request.

  A blob has at most 50,000 blocks. When the stream would need more, the upload
  stops with `{:error, %AzureSDK.Error{code: "BlockCountExceeded"}}` before the
  extra block is sent; raise `:block_size` for larger uploads.

  On mid-stream failure, staged uncommitted blocks may remain on the service.
  Azure discards them after a week.

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
               content_type: Keyword.get(opts, :content_type, @default_content_type),
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
      opts
      |> Conditions.headers()
      |> Map.merge(range_header(Keyword.get(opts, :range)))

    with {:ok, response} <-
           Operation.run(client,
             method: :get,
             path: Operation.blob_path(container, name),
             headers: headers,
             operation: :get
           ) do
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
  * condition / lease opts from `AzureSDK.Storage.Conditions` (applied to the
    initial HEAD and to each range GET)

  The stream calls `properties/4` once for size and ETag, then sends `If-Match`
  with that ETag on every range (unless you pass `:if_match` yourself). If the
  blob is overwritten while you enumerate, the next range fails with 412
  instead of returning bytes from the new version. The `:range` and
  `:include_content` options of `download/4` are ignored here.

  Mid-stream HTTP failures, including that 412, raise
  `AzureSDK.Storage.Blob.StreamError`. A failed initial HEAD is returned as
  `{:error, %AzureSDK.Error{}}` before a stream is built.

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
    opts = Keyword.drop(opts, [:range, :include_content])

    case properties(client, container, name, opts) do
      {:ok, %{content_length: 0}} ->
        {:ok, []}

      {:ok, %{content_length: size, etag: etag}} ->
        range_opts = if etag, do: Keyword.put_new(opts, :if_match, etag), else: opts
        {:ok, range_stream(client, container, name, range_opts, chunk_size, size)}

      {:error, _} = error ->
        error
    end
  end

  defp range_stream(client, container, name, opts, chunk_size, size) do
    Stream.resource(
      fn -> 0 end,
      fn
        offset when offset >= size ->
          {:halt, offset}

        offset ->
          finish = min(offset + chunk_size - 1, size - 1)

          case download(client, container, name, Keyword.put(opts, :range, {offset, finish})) do
            {:ok, %{content: content}} -> {[content], finish + 1}
            {:error, reason} -> raise AzureSDK.Storage.Blob.StreamError, reason: reason
          end
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Returns blob properties via HEAD (Get Blob Properties). Does not download the body.

  ## Parameters

  * `client`, `container`, `name` - as in `upload/5`
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * condition / lease opts from `AzureSDK.Storage.Conditions`

  ## Returns

  * `{:ok, t:properties/0}` - `content_length` is an integer
  * `{:error, %AzureSDK.Error{}}` - including `InvalidResponse` when length
    headers are missing or malformed

  ## Examples

      {:ok, %{content_length: size, etag: etag}} =
        AzureSDK.Storage.Blob.properties(client, "uploads", "hello.txt")

      {:ok, props} =
        AzureSDK.Storage.Blob.properties(client, "uploads", "hello.txt",
          lease_id: lease_id,
          if_match: etag
        )
  """
  @spec properties(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, properties()} | {:error, AzureSDK.Error.t()}
  def properties(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :properties, %{container: container, name: name})

    with {:ok, response} <- head_blob(client, container, name, opts, :properties),
         {:ok, content_length} <- parse_size(response) do
      {:ok,
       %{
         content_length: content_length,
         content_type: Operation.header(response, "content-type"),
         etag: Operation.header(response, "etag"),
         last_modified: Operation.header(response, "last-modified"),
         metadata: Metadata.from_headers(response.headers)
       }}
    end
  end

  @doc """
  Returns whether the blob exists.

  ## Parameters

  * `client`, `container`, `name` - as in `upload/5`
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * condition / lease opts from `AzureSDK.Storage.Conditions`

  ## Returns

  * `true` / `false` when the service answers or reports not found
  * `{:error, %AzureSDK.Error{}}` for other failures (auth, 403, 5xx, transport)

  Match all three; do not treat the return as a plain boolean. Uses the same
  HEAD request path as `properties/4`; never downloads the body.

  ## Examples

      case AzureSDK.Storage.Blob.exists?(client, "uploads", "hello.txt") do
        true -> :ok
        false -> AzureSDK.Storage.Blob.upload(client, "uploads", "hello.txt", "")
        {:error, error} -> {:error, error}
      end
  """
  @spec exists?(Client.t(), String.t(), String.t(), keyword()) ::
          boolean() | {:error, AzureSDK.Error.t()}
  def exists?(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :exists, %{container: container, name: name})

    case head_blob(client, container, name, opts, :exists) do
      {:ok, _} -> true
      {:error, %{status: 404}} -> false
      {:error, %{code: "BlobNotFound"}} -> false
      {:error, _} = error -> error
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

    with {:ok, _} <-
           Operation.run(client,
             method: :delete,
             path: Operation.blob_path(container, name),
             headers: Conditions.headers(opts),
             operation: :delete
           ) do
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

    with {:ok, response} <- head_blob(client, container, name, opts, :metadata) do
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

    headers = Map.merge(Metadata.headers(metadata), Conditions.headers(opts))

    with {:ok, _} <-
           Operation.run(client,
             method: :put,
             path: Operation.blob_path(container, name),
             query: [{"comp", "metadata"}],
             headers: headers,
             operation: :set_metadata
           ) do
      {:ok, metadata}
    end
  end

  defp stage_blocks(client, container, name, stream, block_size, opts) do
    prefix = Block.upload_prefix()

    stream
    |> chunk_stream(block_size)
    |> Enum.reduce_while({:ok, [], 0, 0}, fn
      _chunk, {:ok, _ids, @max_blocks, _total} ->
        {:halt, {:error, block_count_exceeded(block_size)}}

      chunk, {:ok, ids, index, total} ->
        block_id = Block.block_id(index, 6, prefix)

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

  defp block_count_exceeded(block_size) do
    Error.new(
      code: "BlockCountExceeded",
      message:
        "Upload needs more than #{@max_blocks} blocks of #{block_size} bytes; increase :block_size",
      service: :blob
    )
  end

  @doc false
  # Regroups an enumerable of iodata into binaries of exactly `block_size` bytes
  # (the last one may be shorter). Pieces are buffered as iodata and only
  # flattened once a full block is available, so cost stays linear in the input.
  @spec chunk_stream(Enumerable.t(), pos_integer()) :: Enumerable.t()
  def chunk_stream(stream, block_size) when is_integer(block_size) and block_size > 0 do
    stream
    |> Stream.concat([:__done__])
    |> Stream.transform({[], 0}, fn
      :__done__, {_buffer, 0} ->
        {[], {[], 0}}

      :__done__, {buffer, _size} ->
        {[buffer |> Enum.reverse() |> IO.iodata_to_binary()], {[], 0}}

      piece, {buffer, size} ->
        piece_size = IO.iodata_length(piece)
        buffer = [piece | buffer]
        size = size + piece_size

        if size >= block_size do
          data = buffer |> Enum.reverse() |> IO.iodata_to_binary()
          {blocks, rest} = split_blocks(data, block_size, [])
          {blocks, {[rest], byte_size(rest)}}
        else
          {[], {buffer, size}}
        end
    end)
  end

  defp split_blocks(data, block_size, acc) when byte_size(data) >= block_size do
    <<block::binary-size(block_size), rest::binary>> = data
    split_blocks(rest, block_size, [block | acc])
  end

  defp split_blocks(rest, _block_size, acc), do: {Enum.reverse(acc), rest}

  defp upload_headers(opts, size) do
    %{
      "Content-Type" => Keyword.get(opts, :content_type, @default_content_type),
      "Content-Length" => Integer.to_string(size),
      "x-ms-blob-type" => Keyword.get(opts, :blob_type, "BlockBlob")
    }
    |> Map.merge(Metadata.headers(Keyword.get(opts, :metadata, %{})))
    |> Map.merge(Conditions.headers(opts))
  end

  defp range_header(nil), do: %{}

  defp range_header({start, finish}) when is_integer(start) and is_integer(finish) do
    %{"Range" => "bytes=#{start}-#{finish}"}
  end

  defp head_blob(client, container, name, opts, operation) do
    Operation.run(client,
      method: :head,
      path: Operation.blob_path(container, name),
      headers: Conditions.headers(opts),
      operation: operation
    )
  end

  defp parse_size(response) do
    value =
      Operation.header(response, "x-ms-blob-content-length") ||
        Operation.header(response, "content-length")

    case value && Integer.parse(value) do
      {size, ""} when size >= 0 ->
        {:ok, size}

      _ ->
        {:error,
         Error.new(
           code: "InvalidResponse",
           message: "Blob properties response has no valid Content-Length",
           status: response.status,
           service: :blob
         )}
    end
  end

  defp blob_from_response(container, name, %Response{} = response, content, opts) do
    %{
      container: container,
      name: name,
      properties: %{
        content_type: Operation.header(response, "content-type"),
        content_length: content_length(response, content),
        etag: Operation.header(response, "etag"),
        last_modified: Operation.header(response, "last-modified")
      },
      metadata: Metadata.from_headers(response.headers),
      content: content_value(content, opts)
    }
  end

  defp content_value(content, opts) do
    if Keyword.get(opts, :include_content, true), do: content
  end

  defp content_length(_response, content) when is_binary(content), do: byte_size(content)
  defp content_length(response, _), do: Operation.header(response, "content-length")
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
