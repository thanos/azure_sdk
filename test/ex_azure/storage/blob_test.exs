defmodule ExAzure.Storage.BlobTest do
  use ExAzure.AzureMockCase, async: true

  alias ExAzure.Storage.Blob

  test "uploads a blob", %{bypass: bypass, client: client} do
    AzureMock.stub_put_blob(bypass, "uploads", "hello.txt", "hello")

    assert {:ok, %{name: "hello.txt", content: "hello"}} =
             Blob.upload(client, "uploads", "hello.txt", "hello")
  end

  test "uploads iodata", %{bypass: bypass, client: client} do
    AzureMock.stub_put_blob(bypass, "uploads", "data.bin", "abc")

    assert {:ok, %{content: "abc"}} =
             Blob.upload(client, "uploads", "data.bin", ["a", "bc"])
  end

  test "uploads from a stream", %{bypass: bypass, client: client} do
    AzureMock.stub_put_blob(bypass, "uploads", "stream.txt", "aaa")

    stream = Stream.repeatedly(fn -> "a" end) |> Stream.take(3)

    assert {:ok, %{content: "aaa"}} =
             Blob.upload_stream(client, "uploads", "stream.txt", stream)
  end

  test "downloads a blob", %{bypass: bypass, client: client} do
    AzureMock.stub_get_blob(bypass, "uploads", "hello.txt", "payload")

    assert {:ok, %{content: "payload"}} = Blob.download(client, "uploads", "hello.txt")
  end

  test "downloads a blob as a stream", %{bypass: bypass, client: client} do
    AzureMock.stub_get_blob(bypass, "uploads", "hello.txt", "payload")

    assert {:ok, stream} = Blob.download_stream(client, "uploads", "hello.txt")
    assert Enum.join(stream) == "payload"
  end

  test "deletes a blob", %{bypass: bypass, client: client} do
    AzureMock.stub_delete_blob(bypass, "uploads", "hello.txt")

    assert {:ok, :deleted} = Blob.delete(client, "uploads", "hello.txt")
  end

  test "returns blob metadata", %{bypass: bypass, client: client} do
    AzureMock.stub_head_blob(bypass, "uploads", "hello.txt", %{"tier" => "hot"})

    assert {:ok, %{"tier" => "hot"}} = Blob.metadata(client, "uploads", "hello.txt")
  end

  test "sets blob metadata", %{bypass: bypass, client: client} do
    AzureMock.stub_put_blob_metadata(bypass, "uploads", "hello.txt")

    assert {:ok, %{}} = Blob.set_metadata(client, "uploads", "hello.txt", %{"tier" => "hot"})
  end

  test "returns azure error on failure", %{bypass: bypass, client: client, account: account} do
    AzureMock.stub_error(
      bypass,
      "GET",
      AzureMock.path(["uploads", "missing.txt"], account),
      404,
      "BlobNotFound",
      "The specified blob does not exist."
    )

    assert {:error, %{code: "BlobNotFound", status: 404}} =
             Blob.download(client, "uploads", "missing.txt")
  end
end
