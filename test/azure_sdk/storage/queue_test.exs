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
end
