defmodule AzureSDK.Storage.BlobStreamingTest do
  use AzureSDK.AzureMockCase, async: true

  alias AzureSDK.Error
  alias AzureSDK.Storage.{Blob, Client}
  alias AzureSDK.Storage.Blob.StreamError

  @no_retry %{max_attempts: 1, base_delay_ms: 1, max_delay_ms: 1, jitter: false}

  # Client whose requests go to an in-process plug instead of the network.
  defp plug_client(plug) do
    Client.new(
      account: AzureMock.account(),
      credential: AzureMock.credential(),
      endpoint: "http://localhost/#{AzureMock.account()}",
      api_version: "2021-08-06",
      retry: @no_retry,
      req_options: [plug: plug]
    )
  end

  describe "upload_stream/5" do
    test "commits the blocks in order and the committed bytes equal the input",
         %{bypass: bypass, client: client} do
      recorder = AzureMock.stub_put_blob_blocks(bypass, "uploads", "big.bin")
      input = Enum.map(1..10, &String.duplicate(<<&1>>, 7))

      assert {:ok, %{properties: %{content_length: 70, etag: "\"0xblock\""}}} =
               Blob.upload_stream(client, "uploads", "big.bin", input, block_size: 16)

      assert AzureMock.committed_content(recorder) == IO.iodata_to_binary(input)
      %{blocks: blocks, commits: [%{ids: ids}]} = Agent.get(recorder, & &1)
      assert length(ids) == 5
      assert Enum.map(ids, &byte_size(Map.fetch!(blocks, &1))) == [16, 16, 16, 16, 6]
    end

    test "two uploads to the same blob use disjoint block ids of equal length",
         %{bypass: bypass, client: client} do
      recorder = AzureMock.stub_put_blob_blocks(bypass, "uploads", "shared.bin")

      assert {:ok, _} =
               Blob.upload_stream(client, "uploads", "shared.bin", ["aaaa"], block_size: 2)

      assert {:ok, _} =
               Blob.upload_stream(client, "uploads", "shared.bin", ["bbbb"], block_size: 2)

      %{commits: [%{ids: first}, %{ids: second}]} = Agent.get(recorder, & &1)
      assert MapSet.disjoint?(MapSet.new(first), MapSet.new(second))

      assert first
             |> Enum.concat(second)
             |> Enum.map(&byte_size(Base.decode64!(&1)))
             |> Enum.uniq()
             |> length() == 1

      assert AzureMock.committed_content(recorder) == "bbbb"
    end

    test "sends If-* conditions and metadata only on the commit, lease id on every request",
         %{bypass: bypass, client: client} do
      recorder = AzureMock.stub_put_blob_blocks(bypass, "uploads", "cond.bin")

      assert {:ok, _} =
               Blob.upload_stream(client, "uploads", "cond.bin", ["abcd"],
                 block_size: 2,
                 if_match: "\"0x1\"",
                 lease_id: "lease-1",
                 metadata: %{"owner" => "app"},
                 content_type: "text/plain"
               )

      %{block_headers: block_headers, commits: [%{headers: commit}]} = Agent.get(recorder, & &1)

      for headers <- block_headers do
        refute Map.has_key?(headers, "if-match")
        assert headers["x-ms-lease-id"] == "lease-1"
      end

      assert commit["if-match"] == "\"0x1\""
      assert commit["x-ms-lease-id"] == "lease-1"
      assert commit["x-ms-meta-owner"] == "app"
      assert commit["x-ms-blob-content-type"] == "text/plain"
    end

    test "reports the default content type when none is given", %{bypass: bypass, client: client} do
      AzureMock.stub_put_blob_blocks(bypass, "uploads", "typed.bin")

      assert {:ok, %{properties: %{content_type: "application/octet-stream"}}} =
               Blob.upload_stream(client, "uploads", "typed.bin", ["abc"], block_size: 2)
    end

    @tag timeout: 120_000
    test "stops before staging block 50,001" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      client =
        plug_client(fn conn ->
          Agent.update(counter, &(&1 + 1))
          Plug.Conn.resp(conn, 201, "")
        end)

      stream = Stream.repeatedly(fn -> "x" end) |> Stream.take(50_001)

      assert {:error, %Error{code: "BlockCountExceeded"}} =
               Blob.upload_stream(client, "uploads", "huge.bin", stream, block_size: 1)

      assert Agent.get(counter, & &1) == 50_000
    end
  end

  describe "chunk_stream/2" do
    test "regroups pieces of any size into exact blocks" do
      for {pieces, block_size, expected} <- [
            {List.duplicate("a", 5), 2, ["aa", "aa", "a"]},
            {["abc", "def"], 4, ["abcd", "ef"]},
            {["abcd"], 4, ["abcd"]},
            {["abcdefghijkl"], 4, ["abcd", "efgh", "ijkl"]},
            {[["ab", ?c], "d"], 2, ["ab", "cd"]},
            {[], 4, []}
          ] do
        assert pieces |> Blob.chunk_stream(block_size) |> Enum.to_list() == expected
      end
    end
  end

  describe "download_stream/4" do
    test "pins every range to the ETag from the initial HEAD", %{bypass: bypass, client: client} do
      AzureMock.stub_head_blob_size(bypass, "uploads", "pinned.txt", 7)
      test_pid = self()

      Bypass.expect(bypass, "GET", AzureMock.path(["uploads", "pinned.txt"]), fn conn ->
        send(test_pid, {:if_match, Plug.Conn.get_req_header(conn, "if-match")})
        "bytes=" <> range = conn |> Plug.Conn.get_req_header("range") |> hd()
        [first, last] = range |> String.split("-") |> Enum.map(&String.to_integer/1)
        Plug.Conn.resp(conn, 206, binary_part("payload", first, last - first + 1))
      end)

      assert {:ok, stream} = Blob.download_stream(client, "uploads", "pinned.txt", chunk_size: 3)
      assert Enum.join(stream) == "payload"

      for _ <- 1..3, do: assert_received({:if_match, ["\"0x2\""]})
    end

    test "raises StreamError when the blob changes mid-stream", %{bypass: bypass, client: client} do
      AzureMock.stub_head_blob_size(bypass, "uploads", "moving.txt", 6)
      {:ok, calls} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, "GET", AzureMock.path(["uploads", "moving.txt"]), fn conn ->
        case Agent.get_and_update(calls, &{&1, &1 + 1}) do
          0 -> Plug.Conn.resp(conn, 206, "abc")
          _ -> Plug.Conn.resp(conn, 412, "")
        end
      end)

      assert {:ok, stream} = Blob.download_stream(client, "uploads", "moving.txt", chunk_size: 3)

      assert %StreamError{reason: %Error{status: 412}} =
               assert_raise(StreamError, fn -> Enum.to_list(stream) end)
    end

    test "a caller's :if_match wins over the pinned ETag", %{bypass: bypass, client: client} do
      AzureMock.stub_head_blob_size(bypass, "uploads", "own.txt", 3)

      Bypass.expect(bypass, "GET", AzureMock.path(["uploads", "own.txt"]), fn conn ->
        assert Plug.Conn.get_req_header(conn, "if-match") == ["\"mine\""]
        Plug.Conn.resp(conn, 206, "abc")
      end)

      assert {:ok, stream} =
               Blob.download_stream(client, "uploads", "own.txt", if_match: "\"mine\"")

      assert Enum.join(stream) == "abc"
    end

    test "ignores a caller's :range and :include_content", %{bypass: bypass, client: client} do
      AzureMock.stub_head_blob_size(bypass, "uploads", "all.txt", 7)
      AzureMock.stub_get_blob_ranges(bypass, "uploads", "all.txt", "payload")

      assert {:ok, stream} =
               Blob.download_stream(client, "uploads", "all.txt",
                 range: {0, 1},
                 include_content: false,
                 chunk_size: 4
               )

      assert Enum.join(stream) == "payload"
    end

    test "a zero-length blob is an empty stream", %{bypass: bypass, client: client} do
      AzureMock.stub_head_blob_size(bypass, "uploads", "empty.txt", 0)
      assert {:ok, []} = Blob.download_stream(client, "uploads", "empty.txt")
    end

    test "raises StreamError when a range request fails", %{bypass: bypass, client: client} do
      AzureMock.stub_head_blob_size(bypass, "uploads", "broken.txt", 6)

      Bypass.expect(bypass, "GET", AzureMock.path(["uploads", "broken.txt"]), fn conn ->
        Plug.Conn.resp(conn, 500, "")
      end)

      client = %{client | retry: @no_retry}
      assert {:ok, stream} = Blob.download_stream(client, "uploads", "broken.txt", chunk_size: 3)

      assert %StreamError{reason: %Error{status: 500}} =
               assert_raise(StreamError, fn -> Enum.to_list(stream) end)
    end

    test "returns InvalidResponse when the blob size header is malformed" do
      client =
        plug_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("x-ms-blob-content-length", "not-a-number")
          |> Plug.Conn.resp(200, "")
        end)

      assert {:error, %Error{code: "InvalidResponse"}} =
               Blob.download_stream(client, "uploads", "odd.txt")
    end
  end
end
