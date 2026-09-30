defmodule AzureSDK.Storage.Blob.Block do
  @moduledoc """
  Block blob staging and commit helpers (`Put Block`, `Put Block List`).

  Used by `AzureSDK.Storage.Blob.upload_stream/5` for bounded-memory uploads.

  Uncommitted blocks are keyed by blob and block ID, so two uploads to the same
  blob must not share IDs. Generate a fresh `upload_prefix/0` per upload and
  pass it to `block_id/3`.

  ## Examples

      prefix = AzureSDK.Storage.Blob.Block.upload_prefix()
      ids = [
        AzureSDK.Storage.Blob.Block.block_id(0, 6, prefix),
        AzureSDK.Storage.Blob.Block.block_id(1, 6, prefix)
      ]

      {:ok, :staged} =
        AzureSDK.Storage.Blob.Block.put_block(client, "uploads", "big.bin", hd(ids), chunk)

      {:ok, %{etag: _}} =
        AzureSDK.Storage.Blob.Block.put_block_list(client, "uploads", "big.bin", ids,
          content_type: "application/octet-stream",
          metadata: %{"source" => "stream"}
        )
  """

  alias AzureSDK.Core.Telemetry
  alias AzureSDK.Storage.{Client, Conditions, Metadata, Operation}

  @doc """
  Stages a single uncommitted block.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `container` - container name
  * `name` - blob name (may include `/` path segments)
  * `block_id` - Base64-encoded block identifier (same decoded length for all blocks)
  * `content` - binary block body
  * `opts` - optional keyword list

  ## Options

  * `:lease_id` - required when the blob has an active lease

  Put Block does not support `If-*` conditions; pass them to `put_block_list/5`,
  which commits the blob. Other options are ignored here.

  ## Examples

      {:ok, :staged} =
        AzureSDK.Storage.Blob.Block.put_block(
          client,
          "uploads",
          "file.bin",
          AzureSDK.Storage.Blob.Block.block_id(0, 6, prefix),
          <<1, 2, 3>>,
          lease_id: lease_id
        )
  """
  @spec put_block(Client.t(), String.t(), String.t(), String.t(), binary(), keyword()) ::
          {:ok, :staged} | {:error, AzureSDK.Error.t()}
  def put_block(client, container, name, block_id, content, opts \\ [])
      when is_binary(block_id) and is_binary(content) do
    Telemetry.emit_operation(:blob, :put_block, %{container: container, name: name})

    headers =
      opts
      |> Keyword.take([:lease_id])
      |> Conditions.headers()
      |> Map.put("Content-Length", Integer.to_string(byte_size(content)))

    with {:ok, _} <-
           Operation.run(client,
             method: :put,
             path: Operation.blob_path(container, name),
             query: [{"comp", "block"}, {"blockid", block_id}],
             headers: headers,
             body: content,
             operation: :put_block
           ) do
      {:ok, :staged}
    end
  end

  @doc """
  Commits staged blocks in order.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `container` - container name
  * `name` - blob name
  * `block_ids` - list of Base64 block IDs in commit order
  * `opts` - optional keyword list

  ## Options

  * `:content_type` - sets `x-ms-blob-content-type` on commit
  * `:metadata` - string-keyed user metadata (replaces existing metadata)
  * condition / lease opts from `AzureSDK.Storage.Conditions`

  Returns the committed blob's `etag` and `last_modified` (either may be `nil`).

  ## Examples

      {:ok, %{etag: etag}} =
        AzureSDK.Storage.Blob.Block.put_block_list(client, "uploads", "file.bin", ids,
          content_type: "application/pdf",
          metadata: %{"owner" => "app"},
          if_match: "\\"0x1\\""
        )
  """
  @spec put_block_list(Client.t(), String.t(), String.t(), [String.t()], keyword()) ::
          {:ok, %{etag: String.t() | nil, last_modified: String.t() | nil}}
          | {:error, AzureSDK.Error.t()}
  def put_block_list(client, container, name, block_ids, opts \\ []) when is_list(block_ids) do
    Telemetry.emit_operation(:blob, :put_block_list, %{
      container: container,
      name: name,
      block_count: length(block_ids)
    })

    body = block_list_xml(block_ids)

    headers =
      %{
        "Content-Type" => "application/xml",
        "Content-Length" => Integer.to_string(byte_size(body))
      }
      |> Operation.put_present("x-ms-blob-content-type", Keyword.get(opts, :content_type))
      |> Map.merge(Conditions.headers(opts))
      |> Map.merge(Metadata.headers(Keyword.get(opts, :metadata, %{})))

    with {:ok, response} <-
           Operation.run(client,
             method: :put,
             path: Operation.blob_path(container, name),
             query: [{"comp", "blocklist"}],
             headers: headers,
             body: body,
             operation: :put_block_list
           ) do
      {:ok,
       %{
         etag: Operation.header(response, "etag"),
         last_modified: Operation.header(response, "last-modified")
       }}
    end
  end

  @doc """
  Returns a random prefix for the block IDs of one upload.

  Every call returns a different 16-character hex string, so concurrent
  uploads to the same blob never share block IDs.

  ## Examples

      iex> prefix = AzureSDK.Storage.Blob.Block.upload_prefix()
      iex> byte_size(prefix)
      16
      iex> prefix == AzureSDK.Storage.Blob.Block.upload_prefix()
      false
  """
  @spec upload_prefix() :: String.t()
  def upload_prefix do
    8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end

  @doc """
  Encodes `prefix` plus a zero-padded block index as a Base64 block ID.

  All IDs for a blob must have the same decoded length, so use one `prefix`
  and one `width` for every block of an upload.

  ## Parameters

  * `index` - zero-based block index
  * `width` - digit width of the padded index (default `6`)
  * `prefix` - per-upload prefix from `upload_prefix/0` (default `""`)

  ## Examples

      iex> AzureSDK.Storage.Blob.Block.block_id(0)
      "MDAwMDAw"
      iex> AzureSDK.Storage.Blob.Block.block_id(12, 6)
      "MDAwMDEy"
      iex> AzureSDK.Storage.Blob.Block.block_id(1, 4)
      "MDAwMQ=="
      iex> AzureSDK.Storage.Blob.Block.block_id(1, 6, "ab") |> Base.decode64!()
      "ab000001"
  """
  @spec block_id(non_neg_integer(), pos_integer(), String.t()) :: String.t()
  def block_id(index, width \\ 6, prefix \\ "")
      when is_integer(index) and index >= 0 and is_binary(prefix) do
    padded = index |> Integer.to_string() |> String.pad_leading(width, "0")
    Base.encode64(prefix <> padded)
  end

  @doc """
  Builds Put Block List XML for Latest blocks.

  ## Parameters

  * `block_ids` - Base64 block IDs in commit order

  ## Examples

      iex> xml = AzureSDK.Storage.Blob.Block.block_list_xml(["YWFh", "YmJi"])
      iex> String.contains?(xml, "<Latest>YWFh</Latest>")
      true
      iex> String.contains?(xml, "<BlockList>")
      true
  """
  @spec block_list_xml([String.t()]) :: binary()
  def block_list_xml(block_ids) when is_list(block_ids) do
    entries = Enum.map_join(block_ids, "", &"<Latest>#{&1}</Latest>")
    "<?xml version=\"1.0\" encoding=\"utf-8\"?><BlockList>#{entries}</BlockList>"
  end
end
