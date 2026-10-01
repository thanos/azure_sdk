defmodule AzureSDK.Storage.Queue.MessageTest do
  use AzureSDK.AzureMockCase, async: true

  alias AzureSDK.Storage.Queue.Message

  test "puts a message", %{bypass: bypass, client: client} do
    AzureMock.stub_put_message(bypass, "jobs", "hello")

    assert {:ok, [%{id: "msg-1", content: "hello", pop_receipt: "pr-1"}]} =
             Message.put(client, "jobs", "hello")
  end

  test "gets and peeks messages", %{bypass: bypass, client: client} do
    AzureMock.stub_get_messages(bypass, "jobs", "payload")

    assert {:ok, [%{content: "payload", dequeue_count: 1}]} =
             Message.get(client, "jobs", number_of_messages: 1, visibility_timeout: 30)

    assert {:ok, [%{content: "payload"}]} = Message.peek(client, "jobs")
  end

  test "deletes a message", %{bypass: bypass, client: client} do
    Bypass.expect(bypass, "DELETE", AzureMock.path(["jobs", "messages", "msg-1"]), fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["popreceipt"] == "pr-1"
      Plug.Conn.resp(conn, 204, "")
    end)

    assert {:ok, :deleted} =
             Message.delete(client, "jobs", "msg-1", pop_receipt: "pr-1")
  end

  test "updates a message", %{bypass: bypass, client: client} do
    AzureMock.stub_update_message(bypass, "jobs", "msg-1")

    assert {:ok, %{id: "msg-1", pop_receipt: "pr-2", content: "next"}} =
             Message.update(client, "jobs", "msg-1",
               pop_receipt: "pr-1",
               visibility_timeout: 60,
               content: "next"
             )
  end

  test "returns InvalidArgument when pop_receipt is missing", %{client: client} do
    assert {:error, %{code: "InvalidArgument"}} =
             Message.delete(client, "jobs", "msg-1")
  end

  test "put message does not retry on 500", %{bypass: bypass, account: account} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    client =
      AzureMock.client(bypass,
        retry: %{max_attempts: 3, base_delay_ms: 1, max_delay_ms: 1, jitter: false}
      )

    Bypass.expect(bypass, "POST", AzureMock.path(["jobs", "messages"], account), fn conn ->
      Agent.update(counter, &(&1 + 1))
      Plug.Conn.resp(conn, 500, "")
    end)

    assert {:error, %{status: 500}} = Message.put(client, "jobs", "x")
    assert Agent.get(counter, & &1) == 1
  end

  test "get messages does not retry on 500", %{bypass: bypass, account: account} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    client =
      AzureMock.client(bypass,
        retry: %{max_attempts: 3, base_delay_ms: 1, max_delay_ms: 1, jitter: false}
      )

    Bypass.expect(bypass, "GET", AzureMock.path(["jobs", "messages"], account), fn conn ->
      Agent.update(counter, &(&1 + 1))
      Plug.Conn.resp(conn, 500, "")
    end)

    assert {:error, %{status: 500}} = Message.get(client, "jobs")
    assert Agent.get(counter, & &1) == 1
  end

  test "peek may retry on 500", %{bypass: bypass, account: account} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    client =
      AzureMock.client(bypass,
        retry: %{max_attempts: 2, base_delay_ms: 1, max_delay_ms: 1, jitter: false}
      )

    Bypass.expect(bypass, "GET", AzureMock.path(["jobs", "messages"], account), fn conn ->
      Agent.update(counter, &(&1 + 1))
      Plug.Conn.resp(conn, 500, "")
    end)

    assert {:error, %{status: 500}} = Message.peek(client, "jobs")
    assert Agent.get(counter, & &1) == 2
  end
end
