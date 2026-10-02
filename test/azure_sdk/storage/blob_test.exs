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

  describe "properties/4" do
    test "returns integer length, headers, and metadata", %{bypass: bypass, client: client} do
      AzureMock.stub_head_blob_size(bypass, "uploads", "hello.txt", 5,
        content_type: "text/plain",
        metadata: %{"owner" => "app"}
      )

      assert {:ok,
              %{
                content_length: 5,
                content_type: "text/plain",
                etag: "\"0x2\"",
                last_modified: "Wed, 01 Jan 2025 00:00:00 GMT",
                metadata: %{"owner" => "app"}
              }} = Blob.properties(client, "uploads", "hello.txt")
    end

    test "supports a zero-byte blob", %{bypass: bypass, client: client} do
      AzureMock.stub_head_blob_size(bypass, "uploads", "empty.txt", 0)

      assert {:ok, %{content_length: 0, etag: "\"0x2\""}} =
               Blob.properties(client, "uploads", "empty.txt")
    end

    test "forwards condition headers and uses HEAD", %{bypass: bypass, client: client} do
      Bypass.expect(bypass, "HEAD", AzureMock.path(["uploads", "hello.txt"]), fn conn ->
        assert Plug.Conn.get_req_header(conn, "if-match") == ["\"etag\""]
        assert Plug.Conn.get_req_header(conn, "x-ms-lease-id") == ["lease-1"]

        conn
        |> Plug.Conn.put_resp_header("x-ms-blob-content-length", "3")
        |> Plug.Conn.put_resp_header("etag", "\"etag\"")
        |> Plug.Conn.resp(200, "")
      end)

      assert {:ok, %{content_length: 3}} =
               Blob.properties(client, "uploads", "hello.txt",
                 if_match: "\"etag\"",
                 lease_id: "lease-1"
               )
    end

    test "returns 404 as an error", %{bypass: bypass, client: client, account: account} do
      AzureMock.stub_error(
        bypass,
        "HEAD",
        AzureMock.path(["uploads", "missing.txt"], account),
        404,
        "BlobNotFound",
        "gone"
      )

      assert {:error, %{status: 404}} =
               Blob.properties(client, "uploads", "missing.txt")
    end

    test "returns 403 as an error", %{bypass: bypass, client: client, account: account} do
      AzureMock.stub_error(
        bypass,
        "HEAD",
        AzureMock.path(["uploads", "secret.txt"], account),
        403,
        "AuthorizationFailure",
        "denied"
      )

      assert {:error, %{status: 403}} = Blob.properties(client, "uploads", "secret.txt")
    end

    test "returns InvalidResponse when content length is missing" do
      client =
        AzureSDK.Storage.Client.new(
          account: AzureMock.account(),
          credential: AzureMock.credential(),
          endpoint: "http://localhost/#{AzureMock.account()}",
          req_options: [
            plug: fn conn ->
              conn
              |> Plug.Conn.put_resp_header("etag", "\"0x1\"")
              |> Plug.Conn.resp(200, "")
            end
          ]
        )

      assert {:error, %{code: "InvalidResponse"}} =
               Blob.properties(client, "uploads", "odd.txt")
    end
  end

  describe "exists?/4" do
    test "returns true when the blob exists", %{bypass: bypass, client: client} do
      AzureMock.stub_head_blob_size(bypass, "uploads", "hello.txt", 5)
      assert true == Blob.exists?(client, "uploads", "hello.txt")
    end

    test "returns false on 404", %{bypass: bypass, client: client, account: account} do
      AzureMock.stub_error(
        bypass,
        "HEAD",
        AzureMock.path(["uploads", "missing.txt"], account),
        404,
        "BlobNotFound",
        "gone"
      )

      assert false == Blob.exists?(client, "uploads", "missing.txt")
    end

    test "returns an error on 403", %{bypass: bypass, client: client, account: account} do
      AzureMock.stub_error(
        bypass,
        "HEAD",
        AzureMock.path(["uploads", "secret.txt"], account),
        403,
        "AuthorizationFailure",
        "denied"
      )

      assert {:error, %{status: 403}} = Blob.exists?(client, "uploads", "secret.txt")
    end

    test "returns an error after retry exhaustion on 500", %{bypass: bypass, account: account} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      client =
        AzureMock.client(bypass,
          retry: %{max_attempts: 2, base_delay_ms: 1, max_delay_ms: 1, jitter: false}
        )

      Bypass.expect(bypass, "HEAD", AzureMock.path(["uploads", "flaky.txt"], account), fn conn ->
        Agent.update(counter, &(&1 + 1))
        Plug.Conn.resp(conn, 500, "")
      end)

      assert {:error, %{status: 500}} = Blob.exists?(client, "uploads", "flaky.txt")
      assert Agent.get(counter, & &1) == 2
    end

    test "returns a transport failure as an error" do
      client =
        AzureSDK.Storage.Client.new(
          account: AzureMock.account(),
          credential: AzureMock.credential(),
          endpoint: "http://localhost/#{AzureMock.account()}",
          retry: %{max_attempts: 1, base_delay_ms: 1, max_delay_ms: 1, jitter: false},
          req_options: [plug: fn conn -> Req.Test.transport_error(conn, :closed) end]
        )

      assert {:error, %AzureSDK.Error{}} = Blob.exists?(client, "uploads", "gone.txt")
    end

    test "accepts condition options", %{bypass: bypass, client: client} do
      Bypass.expect(bypass, "HEAD", AzureMock.path(["uploads", "hello.txt"]), fn conn ->
        assert Plug.Conn.get_req_header(conn, "if-none-match") == ["*"]

        conn
        |> Plug.Conn.put_resp_header("x-ms-blob-content-length", "1")
        |> Plug.Conn.resp(200, "")
      end)

      assert true == Blob.exists?(client, "uploads", "hello.txt", if_none_match: "*")
    end
  end
end
