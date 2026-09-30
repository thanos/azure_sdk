defmodule AzureSDK.Storage.BlobTest do
  use AzureSDK.AzureMockCase, async: true

  alias AzureSDK.Storage.Blob

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

  test "uploads from a stream via blocks", %{bypass: bypass, client: client} do
    AzureMock.stub_put_blob_blocks(bypass, "uploads", "stream.txt")

    stream = Stream.repeatedly(fn -> "a" end) |> Stream.take(3)

    assert {:ok, %{name: "stream.txt", content: nil, properties: %{content_length: 3}}} =
             Blob.upload_stream(client, "uploads", "stream.txt", stream, block_size: 1)
  end

  test "empty upload_stream falls back to put blob", %{bypass: bypass, client: client} do
    AzureMock.stub_put_blob(bypass, "uploads", "empty.txt", "")

    assert {:ok, %{name: "empty.txt"}} =
             Blob.upload_stream(client, "uploads", "empty.txt", [])
  end

  test "deletes with lease id", %{bypass: bypass, client: client} do
    Bypass.expect(bypass, "DELETE", AzureMock.path(["uploads", "hello.txt"]), fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-ms-lease-id") == ["lease-1"]
      Plug.Conn.resp(conn, 202, "")
    end)

    assert {:ok, :deleted} =
             Blob.delete(client, "uploads", "hello.txt", lease_id: "lease-1")
  end

  test "downloads a blob as a ranged stream", %{bypass: bypass, client: client} do
    content = "payload"
    AzureMock.stub_head_blob_size(bypass, "uploads", "hello.txt", byte_size(content))
    AzureMock.stub_get_blob_ranges(bypass, "uploads", "hello.txt", content)

    assert {:ok, stream} =
             Blob.download_stream(client, "uploads", "hello.txt", chunk_size: 3)

    assert Enum.join(stream) == content
  end

  test "downloads a single range", %{bypass: bypass, client: client} do
    AzureMock.stub_get_blob_ranges(bypass, "uploads", "hello.txt", "payload")

    assert {:ok, %{content: "ayl"}} =
             Blob.download(client, "uploads", "hello.txt", range: {1, 3})
  end

  test "downloads a blob", %{bypass: bypass, client: client} do
    AzureMock.stub_get_blob(bypass, "uploads", "hello.txt", "payload")

    assert {:ok, %{content: "payload"}} = Blob.download(client, "uploads", "hello.txt")
  end

  test "downloads json blobs as raw bytes", %{bypass: bypass, client: client} do
    body = ~s({"a": 1})

    Bypass.expect(bypass, "GET", AzureMock.path(["uploads", "data.json"]), fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)

    assert {:ok, %{content: ^body}} = Blob.download(client, "uploads", "data.json")
  end

  test "include_content false returns nil content", %{bypass: bypass, client: client} do
    AzureMock.stub_get_blob(bypass, "uploads", "hello.txt", "payload")

    assert {:ok, %{content: nil}} =
             Blob.download(client, "uploads", "hello.txt", include_content: false)
  end

  test "downloads a blob as a stream", %{bypass: bypass, client: client} do
    content = "payload"
    AzureMock.stub_head_blob_size(bypass, "uploads", "hello.txt", byte_size(content))
    AzureMock.stub_get_blob_ranges(bypass, "uploads", "hello.txt", content)

    assert {:ok, stream} = Blob.download_stream(client, "uploads", "hello.txt", chunk_size: 4)
    assert Enum.join(stream) == content
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

    assert {:ok, %{"tier" => "hot"}} =
             Blob.set_metadata(client, "uploads", "hello.txt", %{"tier" => "hot"})
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
