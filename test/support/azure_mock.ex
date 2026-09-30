defmodule AzureSDK.AzureMock do
  @moduledoc false

  @test_account "mockaccount"
  @test_key "cGFzc3dvcmQtcGFzc3dvcmQtcGFzc3dvcmQtcGFzc3dvcmQ="

  def account, do: @test_account
  def key, do: @test_key

  def credential do
    AzureSDK.Identity.SharedKeyCredential.new(@test_account, @test_key)
  end

  def client(bypass, opts \\ []) do
    AzureSDK.Storage.Client.new(
      account: Keyword.get(opts, :account, @test_account),
      credential: Keyword.get(opts, :credential, credential()),
      endpoint: endpoint(bypass, Keyword.get(opts, :account, @test_account)),
      api_version: Keyword.get(opts, :api_version, "2021-08-06"),
      retry: Keyword.get(opts, :retry, AzureSDK.Core.Retry.default_policy())
    )
  end

  def endpoint(bypass, account \\ @test_account) do
    "http://127.0.0.1:#{bypass.port}/#{account}"
  end

  def path(segments, account \\ @test_account) when is_list(segments) do
    "/" <> Enum.join([account | segments], "/")
  end

  def stub_put_container(bypass, container, status \\ 201) do
    Bypass.expect(bypass, "PUT", path([container]), fn conn ->
      conn
      |> Plug.Conn.put_resp_header("etag", "\"0x1\"")
      |> Plug.Conn.put_resp_header("last-modified", "Wed, 01 Jan 2025 00:00:00 GMT")
      |> Plug.Conn.resp(status, "")
    end)
  end

  def stub_delete_container(bypass, container, status \\ 202) do
    Bypass.expect(bypass, "DELETE", path([container]), fn conn ->
      Plug.Conn.resp(conn, status, "")
    end)
  end

  def stub_list_containers(bypass, containers \\ ["uploads"]) do
    entries =
      Enum.map_join(containers, "", fn name ->
        """
        <Container>
          <Name>#{name}</Name>
          <Properties>
            <Last-Modified>Wed, 01 Jan 2025 00:00:00 GMT</Last-Modified>
            <Etag>"0x1"</Etag>
          </Properties>
        </Container>
        """
      end)

    body = """
    <?xml version="1.0" encoding="utf-8"?>
    <EnumerationResults>
      <Containers>#{entries}</Containers>
    </EnumerationResults>
    """

    Bypass.expect(bypass, "GET", path([]), fn conn ->
      Plug.Conn.resp(conn, 200, body)
    end)
  end

  def stub_list_blobs(bypass, container, blobs \\ ["file.txt"]) do
    entries =
      Enum.map_join(blobs, "", fn name ->
        """
        <Blob>
          <Name>#{name}</Name>
          <Properties>
            <Content-Length>5</Content-Length>
            <Content-Type>text/plain</Content-Type>
          </Properties>
        </Blob>
        """
      end)

    body = """
    <?xml version="1.0" encoding="utf-8"?>
    <EnumerationResults>
      <Blobs>#{entries}</Blobs>
    </EnumerationResults>
    """

    Bypass.expect(bypass, "GET", path([container]), fn conn ->
      Plug.Conn.resp(conn, 200, body)
    end)
  end

  def stub_put_blob(bypass, container, blob, content \\ "hello", status \\ 201) do
    Bypass.expect(bypass, "PUT", path([container, blob]), fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      respond_put_blob(conn, content, status)
    end)
  end

  defp respond_put_blob(%{query_params: %{"comp" => "block"}} = conn, _content, _status) do
    Plug.Conn.resp(conn, 201, "")
  end

  defp respond_put_blob(%{query_params: %{"comp" => "blocklist"}} = conn, _content, _status) do
    conn
    |> Plug.Conn.put_resp_header("etag", "\"0x2\"")
    |> Plug.Conn.resp(201, "")
  end

  defp respond_put_blob(conn, content, status) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    if body != content do
      raise "expected body #{inspect(content)}, got #{inspect(body)}"
    end

    conn
    |> Plug.Conn.put_resp_header("etag", "\"0x2\"")
    |> Plug.Conn.put_resp_header("content-type", "text/plain")
    |> Plug.Conn.resp(status, "")
  end

  @doc """
  Stubs Put Block / Put Block List and records what the client sent.

  Returns an Agent holding `%{blocks: %{id => body}, block_headers: [headers],
  commits: [%{ids: [id], headers: headers}]}`. Use `committed_content/1` to
  reassemble the committed blob.
  """
  def stub_put_blob_blocks(bypass, container, blob) do
    {:ok, recorder} = Agent.start_link(fn -> %{blocks: %{}, block_headers: [], commits: []} end)

    Bypass.expect(bypass, "PUT", path([container, blob]), fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: 64 * 1024 * 1024)
      headers = Map.new(conn.req_headers)

      case conn.query_params do
        %{"comp" => "block", "blockid" => id} ->
          Agent.update(recorder, &record_block(&1, id, body, headers))
          Plug.Conn.resp(conn, 201, "")

        %{"comp" => "blocklist"} ->
          Agent.update(recorder, &record_commit(&1, body, headers))

          conn
          |> Plug.Conn.put_resp_header("etag", "\"0xblock\"")
          |> Plug.Conn.put_resp_header("last-modified", "Wed, 01 Jan 2025 00:00:00 GMT")
          |> Plug.Conn.resp(201, "")

        _ ->
          Plug.Conn.resp(conn, 400, "unexpected")
      end
    end)

    recorder
  end

  defp record_block(state, id, body, headers) do
    %{
      state
      | blocks: Map.put(state.blocks, id, body),
        block_headers: [headers | state.block_headers]
    }
  end

  defp record_commit(state, body, headers) do
    ids =
      ~r{<Latest>([^<]+)</Latest>} |> Regex.scan(body, capture: :all_but_first) |> List.flatten()

    %{state | commits: state.commits ++ [%{ids: ids, headers: headers}]}
  end

  @doc """
  Reassembles the last committed blob from a `stub_put_blob_blocks/3` recorder.
  """
  def committed_content(recorder) do
    %{blocks: blocks, commits: commits} = Agent.get(recorder, & &1)
    %{ids: ids} = List.last(commits)
    Enum.map_join(ids, &Map.fetch!(blocks, &1))
  end

  def stub_head_blob_size(bypass, container, blob, size) do
    Bypass.expect(bypass, "HEAD", path([container, blob]), fn conn ->
      conn
      |> Plug.Conn.put_resp_header("x-ms-blob-content-length", Integer.to_string(size))
      |> Plug.Conn.put_resp_header("content-length", Integer.to_string(size))
      |> Plug.Conn.put_resp_header("etag", "\"0x2\"")
      |> Plug.Conn.resp(200, "")
    end)
  end

  def stub_get_blob_ranges(bypass, container, blob, content) do
    Bypass.expect(bypass, "GET", path([container, blob]), fn conn ->
      range =
        conn
        |> Plug.Conn.get_req_header("range")
        |> List.first()

      {status, body, content_range} =
        case range do
          "bytes=" <> rest ->
            [start_s, finish_s] = String.split(rest, "-", parts: 2)
            start = String.to_integer(start_s)
            finish = String.to_integer(finish_s)
            total = byte_size(content)
            slice = binary_part(content, start, finish - start + 1)

            {206, slice, "bytes #{start}-#{finish}/#{total}"}

          _ ->
            {200, content, nil}
        end

      conn =
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/plain")
        |> Plug.Conn.put_resp_header("etag", "\"0x2\"")

      conn =
        if content_range do
          Plug.Conn.put_resp_header(conn, "content-range", content_range)
        else
          conn
        end

      Plug.Conn.resp(conn, status, body)
    end)
  end

  def stub_get_blob(bypass, container, blob, content \\ "hello") do
    Bypass.expect(bypass, "GET", path([container, blob]), fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/plain")
      |> Plug.Conn.put_resp_header("etag", "\"0x2\"")
      |> Plug.Conn.resp(200, content)
    end)
  end

  def stub_delete_blob(bypass, container, blob, status \\ 202) do
    Bypass.expect(bypass, "DELETE", path([container, blob]), fn conn ->
      Plug.Conn.resp(conn, status, "")
    end)
  end

  def stub_head_blob(bypass, container, blob, metadata \\ %{}) do
    Bypass.expect(bypass, "HEAD", path([container, blob]), fn conn ->
      conn =
        Enum.reduce(metadata, conn, fn {k, v}, conn ->
          Plug.Conn.put_resp_header(conn, "x-ms-meta-#{k}", v)
        end)

      Plug.Conn.resp(conn, 200, "")
    end)
  end

  def stub_put_blob_metadata(bypass, container, blob) do
    Bypass.expect(bypass, "PUT", path([container, blob]), fn conn ->
      Plug.Conn.resp(conn, 200, "")
    end)
  end

  def stub_head_container(bypass, container, metadata \\ %{}) do
    Bypass.expect(bypass, "HEAD", path([container]), fn conn ->
      conn =
        Enum.reduce(metadata, conn, fn {k, v}, conn ->
          Plug.Conn.put_resp_header(conn, "x-ms-meta-#{k}", v)
        end)

      Plug.Conn.resp(conn, 200, "")
    end)
  end

  def stub_error(bypass, method, route, status, code, message) do
    body = """
    <?xml version="1.0" encoding="utf-8"?>
    <Error>
      <Code>#{code}</Code>
      <Message>#{message}</Message>
    </Error>
    """

    Bypass.expect(bypass, method, route, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("x-ms-request-id", "mock-request-id")
      |> Plug.Conn.resp(status, body)
    end)
  end

  def stub_retry_then_success(bypass, route, fail_status \\ 503, body \\ "ok") do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Bypass.expect(bypass, "GET", route, fn conn ->
      attempt = Agent.get_and_update(counter, &{&1, &1 + 1})

      if attempt == 0 do
        Plug.Conn.resp(conn, fail_status, "")
      else
        Plug.Conn.resp(conn, 200, body)
      end
    end)

    counter
  end

  def stub_list_containers_paginated(bypass, pages) when is_list(pages) do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Bypass.expect(bypass, "GET", path([]), fn conn ->
      index = Agent.get_and_update(counter, &{&1, &1 + 1})

      %{containers: containers, marker: marker} =
        Enum.at(pages, index, %{containers: [], marker: nil})

      entries =
        Enum.map_join(containers, "", fn name ->
          """
          <Container>
            <Name>#{name}</Name>
            <Properties>
              <Last-Modified>Wed, 01 Jan 2025 00:00:00 GMT</Last-Modified>
              <Etag>"0x1"</Etag>
            </Properties>
          </Container>
          """
        end)

      marker_xml =
        case marker do
          nil -> ""
          "" -> ""
          value -> "<NextMarker>#{value}</NextMarker>"
        end

      body = """
      <?xml version="1.0" encoding="utf-8"?>
      <EnumerationResults>
        #{marker_xml}
        <Containers>#{entries}</Containers>
      </EnumerationResults>
      """

      Plug.Conn.resp(conn, 200, body)
    end)
  end
end
