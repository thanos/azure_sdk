defmodule ReviewVerificationTest do
  @moduledoc false
  # Replays the probe scenarios from prompts/review-0.1.0.md against the fixed code.
  use ExUnit.Case, async: false

  alias AzureSDK.AzureMock

  # F-02: JSON download previously failed with "not an iodata term"
  test "F-02: json blob downloads return raw bytes" do
    bypass = Bypass.open()
    client = AzureMock.client(bypass)
    body = ~s({"a": 1})

    Bypass.expect(bypass, "GET", "/mockaccount/c/data.json", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)

    assert {:ok, %{content: ^body}} = AzureSDK.Storage.Blob.download(client, "c", "data.json")
  end

  # F-02: gzip content must round-trip byte-identical (no silent decompression)
  test "F-02: gzip-encoded blob bytes are not altered" do
    bypass = Bypass.open()
    client = AzureMock.client(bypass)
    gzipped = :zlib.gzip("stored-bytes")

    Bypass.expect(bypass, "GET", "/mockaccount/c/data.gz", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-encoding", "gzip")
      |> Plug.Conn.resp(200, gzipped)
    end)

    assert {:ok, %{content: content}} = AzureSDK.Storage.Blob.download(client, "c", "data.gz")
    assert content == gzipped
  end

  # F-01: sovereign cloud / custom endpoints must NOT double the account
  test "F-01: non-public-cloud host-style endpoints sign with single account" do
    credential = AzureMock.credential()

    for endpoint <- [
          "https://acct.blob.core.usgovcloudapi.net",
          "https://acct.blob.core.chinacloudapi.cn",
          "https://storage.example.com"
        ] do
      client =
        AzureSDK.Storage.Client.new(
          account: "acct",
          credential: credential,
          endpoint: endpoint
        )

      refute AzureSDK.Storage.Client.path_style?(client), "expected host-style for #{endpoint}"

      request =
        AzureSDK.Core.Request.new(
          method: :get,
          path: "/container/blob",
          metadata: AzureSDK.Storage.Client.signing_metadata(client)
        )

      string = AzureSDK.Pipeline.SharedKey.string_to_sign(request, "acct")
      assert String.ends_with?(string, "/acct/container/blob")
      refute String.contains?(string, "/acct/acct/")
    end
  end

  # F-01: queue/table/file default endpoints must not be treated as path-style
  test "F-01: queue, table, file service endpoints are host-style" do
    credential = AzureMock.credential()

    for service <- [:queue, :table, :file] do
      client = AzureSDK.Storage.Client.new(account: "a", credential: credential, service: service)
      refute AzureSDK.Storage.Client.path_style?(client)
    end
  end

  # F-01: Azurite path-style still detected and doubles account
  test "F-01: azurite endpoints still sign path-style" do
    credential = AzureMock.credential()

    client =
      AzureSDK.Storage.Client.new(
        account: "devstoreaccount1",
        credential: credential,
        endpoint: "http://127.0.0.1:10000/devstoreaccount1"
      )

    assert AzureSDK.Storage.Client.path_style?(client)

    request =
      AzureSDK.Core.Request.new(
        method: :get,
        path: "/c/b",
        metadata: AzureSDK.Storage.Client.signing_metadata(client)
      )

    string = AzureSDK.Pipeline.SharedKey.string_to_sign(request, "devstoreaccount1")
    assert String.ends_with?(string, "/devstoreaccount1/devstoreaccount1/c/b")
  end

  # F-03: original probe caught :exit from xmerl; must now return fallbacks
  test "F-03: malformed xml no longer exits the calling process" do
    assert AzureSDK.Core.Xml.Error.parse("<html>oops") == %{}
    assert AzureSDK.Core.Xml.Error.parse("plain text") == %{}
    assert AzureSDK.Core.Xml.ListContainers.parse("") == []
    assert AzureSDK.Core.Xml.ListContainers.parse("not xml") == []
    assert AzureSDK.Core.Xml.ListBlobs.parse("") == []
  end

  # F-03: 200 with empty body through the full pipeline
  test "F-03: container list with empty 200 body returns ok with empty list" do
    bypass = Bypass.open()
    client = AzureMock.client(bypass)

    Bypass.expect(bypass, "GET", "/mockaccount", fn conn ->
      Plug.Conn.resp(conn, 200, "")
    end)

    assert {:ok, []} = AzureSDK.Storage.Container.list(client)
  end

  # F-03: non-XML error body builds %Error{} instead of crashing
  test "F-03: html error body from a proxy produces a structured error" do
    bypass = Bypass.open()

    client =
      AzureMock.client(bypass, retry: %{max_attempts: 1, base_delay_ms: 1, max_delay_ms: 1})

    Bypass.expect(bypass, "GET", "/mockaccount/c/b.txt", fn conn ->
      Plug.Conn.resp(conn, 502, "<html><body>Bad Gateway</body></html>")
    end)

    assert {:error, %AzureSDK.Error{status: 502}} =
             AzureSDK.Storage.Blob.download(client, "c", "b.txt")
  end

  # F-05: retry must actually happen (the old Bypass double-expect was vacuous)
  test "F-05: retry test exercises a real 503-then-200 sequence" do
    bypass = Bypass.open()
    client = AzureMock.client(bypass)

    counter =
      AzureMock.stub_retry_then_success(bypass, "/mockaccount", 503, "retry-ok")

    ref = make_ref()

    :telemetry.attach(
      ref,
      [:azure_sdk, :retry],
      fn event, meas, meta, _ -> send(self(), {event, meas, meta}) end,
      nil
    )

    request =
      AzureSDK.Core.Request.new(
        method: :get,
        path: "/",
        query: [{"comp", "list"}],
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: :list_containers,
        metadata: AzureSDK.Storage.Client.signing_metadata(client)
      )

    assert {:ok, %{body: "retry-ok"}} =
             AzureSDK.Core.Pipeline.run(AzureSDK.Storage.Client.to_core_client(client), request)

    # The mock server must have been hit exactly twice: one 503, one 200.
    assert Agent.get(counter, & &1) == 2
    assert_received {[:azure_sdk, :retry], %{delay_ms: _}, %{attempt: 1}}
    :telemetry.detach(ref)
  end

  # F-07: container opts no longer leak into Req options
  test "F-07: unknown opts on container functions do not crash" do
    bypass = Bypass.open()
    client = AzureMock.client(bypass)
    AzureMock.stub_delete_container(bypass, "c")

    assert {:ok, :deleted} = AzureSDK.Storage.Container.delete(client, "c", metadata: %{a: "b"})
  end

  # F-08: reserved characters in blob names are percent-encoded in the URL
  test "F-08: blob names with ? and # address the correct resource" do
    bypass = Bypass.open()
    client = AzureMock.client(bypass)
    parent = self()

    Bypass.expect(bypass, fn conn ->
      send(parent, {:wire, conn.request_path, conn.query_string})
      Plug.Conn.resp(conn, 200, "data")
    end)

    assert {:ok, %{content: "data"}} = AzureSDK.Storage.Blob.download(client, "c", "file?v=1.txt")
    assert_received {:wire, path, query}

    # The ? must be percent-encoded so it stays in the path, not split into a query.
    assert path == "/mockaccount/c/file%3Fv%3D1.txt"
    assert query == ""

    Bypass.expect(bypass, fn conn ->
      send(parent, {:wire2, conn.request_path, conn.query_string})
      Plug.Conn.resp(conn, 200, "data")
    end)

    assert {:ok, _} = AzureSDK.Storage.Blob.download(client, "c", "file#1.txt")
    assert_received {:wire2, path2, _}
    assert path2 == "/mockaccount/c/file%231.txt"
  end

  # F-12: pagination follows NextMarker
  test "F-12: listing follows NextMarker across pages" do
    bypass = Bypass.open()
    client = AzureMock.client(bypass)

    AzureMock.stub_list_containers_paginated(bypass, [
      %{containers: ["a"], marker: "m2"},
      %{containers: ["b"], marker: nil}
    ])

    assert {:ok, containers} = AzureSDK.Storage.Container.list(client)
    assert Enum.map(containers, & &1.name) == ["a", "b"]
  end

  # F-13: request events are start/stop/attempt, no double-counting on one name
  test "F-13: one logical request emits one stop and one attempt event" do
    bypass = Bypass.open()
    client = AzureMock.client(bypass)
    AzureMock.stub_get_blob(bypass, "c", "b.txt", "x")

    ref = make_ref()

    events = [
      [:azure_sdk, :request, :start],
      [:azure_sdk, :request, :stop],
      [:azure_sdk, :request, :attempt]
    ]

    for {event, i} <- Enum.with_index(events) do
      :telemetry.attach({ref, i}, event, fn e, m, meta, _ -> send(self(), {e, m, meta}) end, nil)
    end

    assert {:ok, _} = AzureSDK.Storage.Blob.download(client, "c", "b.txt")

    assert_received {[:azure_sdk, :request, :start], _, _}
    assert_received {[:azure_sdk, :request, :attempt], _, _}
    assert_received {[:azure_sdk, :request, :stop], %{duration: _}, _}
    refute_received {[:azure_sdk, :request, :stop], _, _}
    refute_received {[:azure_sdk, :request, :attempt], _, _}

    for i <- 0..2, do: :telemetry.detach({ref, i})
  end

  # F-14: include_content: false yields nil, not false
  test "F-14: include_content false returns content nil" do
    bypass = Bypass.open()
    client = AzureMock.client(bypass)
    AzureMock.stub_get_blob(bypass, "c", "b.txt", "data")

    assert {:ok, %{content: nil}} =
             AzureSDK.Storage.Blob.download(client, "c", "b.txt", include_content: false)
  end

  # F-15: set_metadata returns the metadata that was set
  test "F-15: set_metadata echoes the input metadata" do
    bypass = Bypass.open()
    client = AzureMock.client(bypass)
    AzureMock.stub_put_blob_metadata(bypass, "c", "b.txt")

    assert {:ok, %{"tier" => "hot"}} =
             AzureSDK.Storage.Blob.set_metadata(client, "c", "b.txt", %{"tier" => "hot"})
  end

  # F-16: non-exception transport reasons don't raise
  test "F-16: from_exception handles non-exception terms" do
    error = AzureSDK.Error.from_exception(:blob, :timeout)
    assert error.message == ":timeout"
    assert error.cause == :timeout
  end

  # F-17: version comes from app spec, not a duplicated literal
  test "F-17: AzureSDK.version matches mix.exs" do
    assert AzureSDK.version() == to_string(Mix.Project.config()[:version])
  end

  # F-23: stub credentials raise RuntimeError, not ArgumentError
  test "F-23: stub credentials raise RuntimeError" do
    cred =
      AzureSDK.Identity.ClientSecretCredential.new(
        tenant_id: "t",
        client_id: "c",
        client_secret: "s"
      )

    request = AzureSDK.Core.Request.new(method: :get, path: "/")

    assert_raise RuntimeError, fn ->
      AzureSDK.Identity.Credential.sign_request(cred, request)
    end
  end
end
