defmodule ExAzure.AzureMock do
  @moduledoc false

  @test_account "mockaccount"
  @test_key "cGFzc3dvcmQtcGFzc3dvcmQtcGFzc3dvcmQtcGFzc3dvcmQ="

  def account, do: @test_account
  def key, do: @test_key

  def credential do
    ExAzure.Identity.SharedKeyCredential.new(@test_account, @test_key)
  end

  def client(bypass, opts \\ []) do
    ExAzure.Storage.Client.new(
      account: Keyword.get(opts, :account, @test_account),
      credential: Keyword.get(opts, :credential, credential()),
      endpoint: endpoint(bypass, Keyword.get(opts, :account, @test_account)),
      api_version: Keyword.get(opts, :api_version, "2021-08-06"),
      retry: Keyword.get(opts, :retry, ExAzure.Core.Retry.default_policy())
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
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      if body != content do
        raise "expected body #{inspect(content)}, got #{inspect(body)}"
      end

      conn
      |> Plug.Conn.put_resp_header("etag", "\"0x2\"")
      |> Plug.Conn.put_resp_header("content-type", "text/plain")
      |> Plug.Conn.resp(status, "")
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
