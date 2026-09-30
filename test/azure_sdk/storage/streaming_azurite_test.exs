defmodule AzureSDK.Storage.StreamingAzuriteTest do
  use AzureSDK.AzuriteCase

  alias AzureSDK.Storage.{Blob, Container, Sas}
  alias AzureSDK.Storage.Blob.Lease

  setup do
    unless azurite_available?() do
      raise "Azurite is not running on port 10000. Start with: docker compose up -d"
    end

    client = azurite_client()
    container = unique_name("stream")
    {:ok, _} = Container.create(client, container)
    on_exit(fn -> _ = Container.delete(client, container) end)
    %{client: client, container: container}
  end

  test "upload_stream and download_stream round-trip", %{client: client, container: container} do
    content = String.duplicate("abcdefghij", 200)

    stream =
      Stream.unfold(content, fn
        <<>> -> nil
        <<chunk::binary-size(50), rest::binary>> -> {chunk, rest}
        rest -> {rest, <<>>}
      end)

    assert {:ok, _} =
             Blob.upload_stream(client, container, "big.bin", stream, block_size: 100)

    assert {:ok, dl} =
             Blob.download_stream(client, container, "big.bin", chunk_size: 80)

    assert Enum.join(dl) == content
  end

  test "lease acquire and delete with lease id", %{client: client, container: container} do
    assert {:ok, _} = Blob.upload(client, container, "lease.txt", "hi")

    assert {:ok, lease_id} =
             Lease.acquire(client, container, "lease.txt", duration: 30)

    assert {:ok, :deleted} =
             Blob.delete(client, container, "lease.txt", lease_id: lease_id)
  end

  test "list_blobs_page and SAS sign", %{client: client, container: container} do
    assert {:ok, _} = Blob.upload(client, container, "a.txt", "a")
    assert {:ok, %{items: [_ | _]}} = Container.list_blobs_page(client, container, max_results: 1)

    assert {:ok, query} =
             Sas.sign_blob(client.credential,
               container: container,
               blob: "a.txt",
               permissions: "r",
               expiry: DateTime.add(DateTime.utc_now(), 3600, :second),
               api_version: client.api_version
             )

    assert query =~ "sig="
  end
end
