defmodule AzureSDK.Storage.Blob.Block do
  @moduledoc """
  Block blob staging and commit helpers (`Put Block`, `Put Block List`).

  Used by `AzureSDK.Storage.Blob.upload_stream/5` for bounded-memory uploads.

  ## Examples

      ids = [
        AzureSDK.Storage.Blob.Block.block_id(0),
        AzureSDK.Storage.Blob.Block.block_id(1)
      ]

      {:ok, :staged} =
        AzureSDK.Storage.Blob.Block.put_block(client, "uploads", "big.bin", hd(ids), chunk)

      {:ok, %{etag: _}} =
        AzureSDK.Storage.Blob.Block.put_block_list(client, "uploads", "big.bin", ids,
          content_type: "application/octet-stream",
          metadata: %{"source" => "stream"}
        )
  """

  alias AzureSDK.Core.{Pipeline, Request, Telemetry}
  alias AzureSDK.Storage.{Client, Conditions, Path}

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

  * condition / lease opts from `AzureSDK.Storage.Conditions` (`:if_match`,
    `:if_none_match`, `:if_modified_since`, `:if_unmodified_since`, `:lease_id`)

  ## Returns

  * `{:ok, :staged}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, :staged} =
        AzureSDK.Storage.Blob.Block.put_block(
          client,
          "uploads",
          "file.bin",
          AzureSDK.Storage.Blob.Block.block_id(0),
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
      %{
        "x-ms-version" => client.api_version,
        "Content-Length" => Integer.to_string(byte_size(content))
      }
      |> Map.merge(Conditions.headers(opts))

    request =
      Request.new(
        method: :put,
        path: blob_path(container, name),
        query: [{"comp", "block"}, {"blockid", block_id}],
        headers: headers,
        body: content,
        service: :blob,
        operation: :put_block,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, _} <- Pipeline.run(Client.to_core_client(client), request) do
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

  ## Returns

  * `{:ok, %{etag: etag | nil, last_modified: last_modified | nil}}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, %{etag: etag}} =
        AzureSDK.Storage.Blob.Block.put_block_list(client, "uploads", "file.bin", ids,
          content_type: "application/pdf",
          metadata: %{"owner" => "app"},
          if_match: "\\"0x1\\""
        )
  """
  @spec put_block_list(Client.t(), String.t(), String.t(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, AzureSDK.Error.t()}
  def put_block_list(client, container, name, block_ids, opts \\ []) when is_list(block_ids) do
    Telemetry.emit_operation(:blob, :put_block_list, %{
      container: container,
      name: name,
      block_count: length(block_ids)
    })

    body = block_list_xml(block_ids)

    headers =
      %{
        "x-ms-version" => client.api_version,
        "Content-Type" => "application/xml",
        "Content-Length" => Integer.to_string(byte_size(body))
      }
      |> Map.merge(content_type_header(opts))
      |> Map.merge(Conditions.headers(opts))
      |> Map.merge(AzureSDK.Storage.Metadata.headers(Keyword.get(opts, :metadata, %{})))

    request =
      Request.new(
        method: :put,
        path: blob_path(container, name),
        query: [{"comp", "blocklist"}],
        headers: headers,
        body: body,
        service: :blob,
        operation: :put_block_list,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok,
       %{
         etag: header(response, "etag"),
         last_modified: header(response, "last-modified")
       }}
    end
  end

  @doc """
  Encodes a zero-padded block index as a Base64 block ID.

  All IDs for a blob must use the same decoded width (`width` digits).

  ## Parameters

  * `index` - zero-based block index
  * `width` - digit width before Base64 (default `6`)

  ## Examples

      iex> AzureSDK.Storage.Blob.Block.block_id(0)
      "MDAwMDAw"
      iex> AzureSDK.Storage.Blob.Block.block_id(12, 6)
      "MDAwMDEy"
      iex> AzureSDK.Storage.Blob.Block.block_id(1, 4)
      "MDAwMQ=="
  """
  @spec block_id(non_neg_integer(), pos_integer()) :: String.t()
  def block_id(index, width \\ 6) when is_integer(index) and index >= 0 do
    index
    |> Integer.to_string()
    |> String.pad_leading(width, "0")
    |> Base.encode64()
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
    entries =
      Enum.map_join(block_ids, "", fn id ->
        "<Latest>#{id}</Latest>"
      end)

    "<?xml version=\"1.0\" encoding=\"utf-8\"?><BlockList>#{entries}</BlockList>"
  end

  defp blob_path(container, name) do
    Path.join([container | String.split(name, "/", parts: :infinity)])
  end

  defp content_type_header(opts) do
    case Keyword.get(opts, :content_type) do
      nil -> %{}
      type -> %{"x-ms-blob-content-type" => type}
    end
  end

  defp header(%{headers: headers}, name) do
    Map.get(headers, name) || Map.get(headers, String.downcase(name))
  end
end
