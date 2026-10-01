defmodule AzureSDK.Storage.QueueTest do
  use AzureSDK.AzureMockCase, async: true

  alias AzureSDK.Storage.Queue

  test "creates a queue", %{bypass: bypass, client: client} do
    AzureMock.stub_put_queue(bypass, "jobs")

    assert {:ok, %{name: "jobs"}} = Queue.create(client, "jobs")
  end

  test "creates a queue with metadata", %{bypass: bypass, client: client} do
    Bypass.expect(bypass, "PUT", AzureMock.path(["jobs"]), fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-ms-meta-env") == ["dev"]

      conn
      |> Plug.Conn.put_resp_header("etag", "\"0x1\"")
      |> Plug.Conn.resp(201, "")
    end)

    assert {:ok, %{metadata: %{"env" => "dev"}}} =
             Queue.create(client, "jobs", metadata: %{"env" => "dev"})
  end

  test "deletes a queue", %{bypass: bypass, client: client} do
    AzureMock.stub_delete_queue(bypass, "jobs")
    assert {:ok, :deleted} = Queue.delete(client, "jobs")
  end

  test "exists? and metadata", %{bypass: bypass, client: client} do
    AzureMock.stub_queue_metadata(bypass, "jobs", %{"env" => "dev"})

    assert Queue.exists?(client, "jobs") == true
    assert {:ok, %{"env" => "dev"}} = Queue.metadata(client, "jobs")
  end

  test "exists? returns false for missing queue", %{bypass: bypass, client: client} do
    Bypass.expect(bypass, "GET", AzureMock.path(["missing"]), fn conn ->
      Plug.Conn.resp(conn, 404, "")
    end)

    assert Queue.exists?(client, "missing") == false
  end

  test "sets metadata", %{bypass: bypass, client: client} do
    AzureMock.stub_put_queue_metadata(bypass, "jobs")

    assert {:ok, %{"env" => "prod"}} =
             Queue.set_metadata(client, "jobs", %{"env" => "prod"})
  end

  test "lists queues", %{bypass: bypass, client: client} do
    AzureMock.stub_list_queues(bypass, ["a", "b"])

    assert {:ok, queues} = Queue.list(client)
    assert Enum.map(queues, & &1.name) == ["a", "b"]

    assert {:ok, %{items: [%{name: "a"}, %{name: "b"}], marker: nil}} =
             Queue.list_page(client)

    assert Enum.map(Queue.list_stream(client), & &1.name) == ["a", "b"]
  end

  test "clears messages", %{bypass: bypass, client: client} do
    AzureMock.stub_clear_messages(bypass, "jobs")
    assert {:ok, :cleared} = Queue.clear_messages(client, "jobs")
  end

  test "returns azure error on failure", %{bypass: bypass, client: client, account: account} do
    AzureMock.stub_error(
      bypass,
      "PUT",
      AzureMock.path(["bad"], account),
      400,
      "InvalidResourceName",
      "bad name"
    )

    assert {:error, %{code: "InvalidResourceName", service: :queue}} =
             Queue.create(client, "bad")
  end

  describe "listing" do
    @no_retry %{max_attempts: 1, base_delay_ms: 1, max_delay_ms: 1, jitter: false}

    test "metadata is nil unless include_metadata is set", %{bypass: bypass, client: client} do
      AzureMock.stub_list_queues(bypass, [{"a", %{"env" => "dev"}}])

      assert {:ok, [%{name: "a", metadata: nil}]} = Queue.list(client)

      assert {:ok, [%{name: "a", metadata: %{"env" => "dev"}}]} =
               Queue.list(client, include_metadata: true)
    end

    test "list follows markers across three pages", %{bypass: bypass, client: client} do
      pages = %{nil => {["a"], "p2"}, "p2" => {["b"], "p3"}, "p3" => {["c"], nil}}

      Bypass.expect(bypass, "GET", AzureMock.path([]), fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        {names, next} = Map.fetch!(pages, conn.query_params["marker"])
        Plug.Conn.resp(conn, 200, AzureMock.list_queues_xml(names, next))
      end)

      assert {:ok, queues} = Queue.list(client, max_results: 1)
      assert Enum.map(queues, & &1.name) == ["a", "b", "c"]
      assert client |> Queue.list_stream(max_results: 1) |> Enum.map(& &1.name) == ["a", "b", "c"]
    end

    test "list_stream raises StreamError when a later page fails", %{bypass: bypass} do
      client = AzureMock.client(bypass, retry: @no_retry)

      Bypass.expect(bypass, "GET", AzureMock.path([]), fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        case conn.query_params["marker"] do
          nil -> Plug.Conn.resp(conn, 200, AzureMock.list_queues_xml(["a"], "p2"))
          _ -> Plug.Conn.resp(conn, 500, "")
        end
      end)

      assert %Queue.StreamError{reason: %AzureSDK.Error{status: 500}} =
               assert_raise(Queue.StreamError, fn ->
                 client |> Queue.list_stream() |> Enum.to_list()
               end)
    end
  end

  test "properties returns an integer message count and metadata",
       %{bypass: bypass, client: client} do
    Bypass.expect(bypass, "GET", AzureMock.path(["jobs"]), fn conn ->
      conn
      |> Plug.Conn.put_resp_header("x-ms-approximate-messages-count", "3")
      |> Plug.Conn.put_resp_header("x-ms-meta-env", "dev")
      |> Plug.Conn.resp(200, "")
    end)

    assert {:ok, %{approximate_message_count: 3, metadata: %{"env" => "dev"}}} =
             Queue.properties(client, "jobs")
  end
end
