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

  test "properties and exists? against a real blob", %{client: client, container: container} do
    assert {:ok, _} =
             Blob.upload(client, container, "props.txt", "hello",
               content_type: "text/plain",
               metadata: %{"owner" => "azurite"}
             )

    assert {:ok,
            %{
              content_length: 5,
              content_type: content_type,
              etag: etag,
              metadata: %{"owner" => "azurite"}
            }} = Blob.properties(client, container, "props.txt")

    assert is_binary(etag) and etag != ""
    assert content_type in ["text/plain", "application/octet-stream"] or is_binary(content_type)
    assert true == Blob.exists?(client, container, "props.txt")
    assert false == Blob.exists?(client, container, "missing-props.txt")

    assert {:ok, %{content: "ell"}} =
             Blob.download(client, container, "props.txt", range: {1, 3}, if_match: etag)

    assert {:ok, stream} = Blob.download_stream(client, container, "props.txt", chunk_size: 2)
    assert Enum.join(stream) == "hello"
  end

  test "lease acquire and delete with lease id", %{client: client, container: container} do
    assert {:ok, _} = Blob.upload(client, container, "lease.txt", "hi")

    assert {:ok, lease_id} =
             Lease.acquire(client, container, "lease.txt", duration: 30)

    assert {:ok, :deleted} =
             Blob.delete(client, container, "lease.txt", lease_id: lease_id)
  end

  test "list_blobs_stream follows markers across pages", %{client: client, container: container} do
    for name <- ["a.txt", "b.txt", "c.txt"],
        do: {:ok, _} = Blob.upload(client, container, name, name)

    assert {:ok, %{items: [_], marker: marker}} =
             Container.list_blobs_page(client, container, max_results: 1)

    assert is_binary(marker)

    names =
      client
      |> Container.list_blobs_stream(container, max_results: 1)
      |> Enum.map(& &1.name)

    assert names == ["a.txt", "b.txt", "c.txt"]
  end

  test "a generated blob SAS authorizes a download", %{client: client, container: container} do
    assert {:ok, _} = Blob.upload(client, container, "a.txt", "sas-content")

    sas_client = fn permissions ->
      {:ok, sas} =
        Sas.sign_blob(client.credential,
          container: container,
          blob: "a.txt",
          permissions: permissions,
          expiry: DateTime.add(DateTime.utc_now(), 3600, :second),
          api_version: client.api_version,
          as_credential: true
        )

      %{client | credential: sas}
    end

    assert {:ok, %{content: "sas-content"}} = Blob.download(sas_client.("r"), container, "a.txt")
    assert {:error, %{status: 403}} = Blob.download(sas_client.("w"), container, "a.txt")
  end

  test "a generated container SAS authorizes listing", %{client: client, container: container} do
    assert {:ok, _} = Blob.upload(client, container, "a.txt", "a")

    {:ok, sas} =
      Sas.sign_container(client.credential,
        container: container,
        permissions: "rl",
        expiry: DateTime.add(DateTime.utc_now(), 3600, :second),
        api_version: client.api_version,
        as_credential: true
      )

    assert {:ok, [%{name: "a.txt"}]} =
             Container.list_blobs(%{client | credential: sas}, container)
  end

  test "lease lifecycle and lease-protected writes", %{client: client, container: container} do
    assert {:ok, _} = Blob.upload(client, container, "leased.txt", "v1")
    assert {:ok, lease_id} = Lease.acquire(client, container, "leased.txt", duration: 15)

    assert {:error, %{status: 412}} = Blob.upload(client, container, "leased.txt", "no lease id")
    assert {:ok, _} = Blob.upload(client, container, "leased.txt", "v2", lease_id: lease_id)

    assert {:ok, ^lease_id} = Lease.renew(client, container, "leased.txt", lease_id: lease_id)

    new_id = "7c9e6679-7425-40de-944b-e07fc1f90ae7"

    assert {:ok, ^new_id} =
             Lease.change(client, container, "leased.txt",
               lease_id: lease_id,
               proposed_lease_id: new_id
             )

    assert {:ok, :released} = Lease.release(client, container, "leased.txt", lease_id: new_id)
    assert {:ok, _} = Lease.acquire(client, container, "leased.txt", duration: 15)
    assert {:ok, :broken} = Lease.break(client, container, "leased.txt", break_period: 0)
    assert {:ok, _} = Blob.upload(client, container, "leased.txt", "after break")
  end

  test "if_none_match * refuses to overwrite an existing blob", %{
    client: client,
    container: container
  } do
    assert {:ok, _} = Blob.upload(client, container, "once.txt", "first", if_none_match: "*")

    assert {:error, %{status: status}} =
             Blob.upload(client, container, "once.txt", "second", if_none_match: "*")

    assert status in [409, 412]
    assert {:ok, %{content: "first"}} = Blob.download(client, container, "once.txt")
  end

  test "download_stream fails instead of mixing versions when the blob changes",
       %{client: client, container: container} do
    assert {:ok, _} = Blob.upload(client, container, "moving.bin", String.duplicate("a", 100))
    assert {:ok, stream} = Blob.download_stream(client, container, "moving.bin", chunk_size: 40)

    [first | _] = Enum.take(stream, 1)
    assert first == String.duplicate("a", 40)

    assert {:ok, _} = Blob.upload(client, container, "moving.bin", String.duplicate("b", 100))

    assert_raise Blob.StreamError, fn -> Enum.to_list(stream) end
  end
end
