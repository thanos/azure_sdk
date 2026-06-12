defmodule ExAzure.Integration.BlobStorageTest do
  use ExAzure.AzuriteCase

  alias ExAzure.Storage.{Blob, Container}

  setup do
    unless azurite_available?() do
      raise "Azurite is not running on port 10000. Start with: docker compose up -d"
    end

    :ok
  end

  test "container and blob lifecycle" do
    client = azurite_client()
    container_name = unique_name("container")
    blob_name = "hello.txt"

    assert {:ok, %{name: ^container_name}} = Container.create(client, container_name)

    assert {:ok, %{content: "hello world"}} =
             Blob.upload(client, container_name, blob_name, "hello world")

    assert {:ok, %{content: "hello world"}} = Blob.download(client, container_name, blob_name)
    assert {:ok, blobs} = Container.list_blobs(client, container_name)
    assert Enum.any?(blobs, &(&1.name == blob_name))
    assert {:ok, :deleted} = Blob.delete(client, container_name, blob_name)
    assert {:ok, :deleted} = Container.delete(client, container_name)
  end

  test "lists containers" do
    client = azurite_client()
    assert {:ok, _containers} = Container.list(client)
  end

  test "round-trips blob names with reserved characters" do
    client = azurite_client()
    container_name = unique_name("special")
    assert {:ok, _} = Container.create(client, container_name)

    for name <- ["a b.txt", "file?v=1.txt", "dir/sub#1.txt"] do
      assert {:ok, _} = Blob.upload(client, container_name, name, "data-#{name}")
      assert {:ok, %{content: content}} = Blob.download(client, container_name, name)
      assert content == "data-#{name}"
      assert {:ok, :deleted} = Blob.delete(client, container_name, name)
    end

    assert {:ok, :deleted} = Container.delete(client, container_name)
  end
end
