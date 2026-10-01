defmodule AzureSDK.Storage.Queue.MessageTest do
  use AzureSDK.AzureMockCase, async: true

  alias AzureSDK.Storage.Queue.Message

  test "put returns the new message without content", %{bypass: bypass, client: client} do
    AzureMock.stub_put_message(bypass, "jobs")

    assert {:ok, %{id: "msg-1", pop_receipt: "pr-1", content: nil}} =
             Message.put(client, "jobs", "hello")
  end

  test "put returns InvalidResponse when the service returns no message",
       %{bypass: bypass, client: client} do
    Bypass.expect(bypass, "POST", AzureMock.path(["jobs", "messages"]), fn conn ->
      Plug.Conn.resp(conn, 201, "<QueueMessagesList></QueueMessagesList>")
    end)

    assert {:error, %{code: "InvalidResponse"}} = Message.put(client, "jobs", "hello")
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

  test "update with content sends the new body", %{bypass: bypass, client: client} do
    Bypass.expect(bypass, "PUT", AzureMock.path(["jobs", "messages", "msg-1"]), fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "<MessageText>#{Base.encode64("next")}</MessageText>"

      conn
      |> Plug.Conn.put_resp_header("x-ms-popreceipt", "pr-2")
      |> Plug.Conn.resp(204, "")
    end)

    assert {:ok, %{id: "msg-1", pop_receipt: "pr-2", content: "next"}} =
             Message.update(client, "jobs", "msg-1",
               pop_receipt: "pr-1",
               visibility_timeout: 60,
               content: "next"
             )
  end

  test "update without content sends no body and keeps the message",
       %{bypass: bypass, client: client} do
    Bypass.expect(bypass, "PUT", AzureMock.path(["jobs", "messages", "msg-1"]), fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body == ""
      assert Plug.Conn.get_req_header(conn, "content-length") == ["0"]

      conn
      |> Plug.Conn.put_resp_header("x-ms-popreceipt", "pr-2")
      |> Plug.Conn.resp(204, "")
    end)

    assert {:ok, %{pop_receipt: "pr-2", content: nil}} =
             Message.update(client, "jobs", "msg-1", pop_receipt: "pr-1", visibility_timeout: 30)
  end

  test "delete treats MessageNotFound as already deleted", %{bypass: bypass, client: client} do
    AzureMock.stub_error(
      bypass,
      "DELETE",
      AzureMock.path(["jobs", "messages", "msg-1"]),
      404,
      "MessageNotFound",
      "gone"
    )

    assert {:ok, :deleted} = Message.delete(client, "jobs", "msg-1", pop_receipt: "pr-1")
  end

  test "delete still reports a stale pop receipt", %{bypass: bypass, client: client} do
    AzureMock.stub_error(
      bypass,
      "DELETE",
      AzureMock.path(["jobs", "messages", "msg-1"]),
      400,
      "PopReceiptMismatch",
      "stale"
    )

    assert {:error, %{status: 400, code: "PopReceiptMismatch"}} =
             Message.delete(client, "jobs", "msg-1", pop_receipt: "old")
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

  describe "message encoding" do
    test "get rejects plain text under :base64 and returns it under :none",
         %{bypass: bypass, client: client} do
      body =
        ~s(<QueueMessagesList><QueueMessage><MessageId>m</MessageId><MessageText>hello world</MessageText></QueueMessage></QueueMessagesList>)

      Bypass.expect(bypass, "GET", AzureMock.path(["jobs", "messages"]), fn conn ->
        Plug.Conn.resp(conn, 200, body)
      end)

      assert {:error, %{code: "InvalidMessageEncoding", message: message}} =
               Message.peek(client, "jobs")

      assert message =~ "message_encoding: :none"

      assert {:ok, [%{content: "hello world"}]} =
               Message.peek(client, "jobs", message_encoding: :none)
    end

    test "put with :none sends escaped text", %{bypass: bypass, client: client} do
      Bypass.expect(bypass, "POST", AzureMock.path(["jobs", "messages"]), fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "<MessageText>a &amp; b</MessageText>"

        Plug.Conn.resp(
          conn,
          201,
          "<QueueMessagesList><QueueMessage><MessageId>m</MessageId></QueueMessage></QueueMessagesList>"
        )
      end)

      assert {:ok, %{id: "m"}} = Message.put(client, "jobs", "a & b", message_encoding: :none)
    end

    test ":none rejects content XML cannot carry", %{client: client} do
      assert {:error, %{code: "InvalidArgument"}} =
               Message.put(client, "jobs", <<255, 254>>, message_encoding: :none)

      assert {:error, %{code: "InvalidArgument"}} =
               Message.put(client, "jobs", "bell\a", message_encoding: :none)
    end

    test "an unknown encoding is rejected", %{client: client} do
      assert {:error, %{code: "InvalidArgument"}} =
               Message.get(client, "jobs", message_encoding: :utf8)
    end
  end

  describe "limits" do
    test "out-of-range options return InvalidArgument without a request", %{client: client} do
      for {fun, opts} <- [
            {&Message.get(client, "jobs", &1), [number_of_messages: 0]},
            {&Message.get(client, "jobs", &1), [number_of_messages: 33]},
            {&Message.get(client, "jobs", &1), [visibility_timeout: 0]},
            {&Message.peek(client, "jobs", &1), [number_of_messages: 40]},
            {&Message.put(client, "jobs", "x", &1), [visibility_timeout: 604_801]},
            {&Message.put(client, "jobs", "x", &1), [message_ttl: 0]},
            {&Message.put(client, "jobs", "x", &1), [visibility_timeout: "10"]},
            {&Message.update(client, "jobs", "m", &1), [pop_receipt: "p", visibility_timeout: -1]}
          ] do
        assert {:error, %{code: "InvalidArgument"}} = fun.(opts),
               "expected #{inspect(opts)} to be rejected"
      end
    end

    test "a body over 64 KiB after encoding is rejected", %{client: client} do
      at_limit = :binary.copy("a", 48 * 1024)
      over_limit = :binary.copy("a", 48 * 1024 + 1)

      assert {:error, %{code: "InvalidArgument", message: message}} =
               Message.put(client, "jobs", over_limit)

      assert message =~ "65540 bytes"

      assert {:error, %{code: "InvalidArgument"}} =
               Message.put(client, "jobs", :binary.copy("a", 64 * 1024 + 1),
                 message_encoding: :none
               )

      assert byte_size(Base.encode64(at_limit)) == 64 * 1024
    end
  end

  describe "retries" do
    @retry %{max_attempts: 3, base_delay_ms: 1, max_delay_ms: 1, jitter: false}

    # The first request fails with a transport error; later ones answer `status`.
    defp flaky_client(test_pid, status) do
      {:ok, calls} = Agent.start_link(fn -> 0 end)

      plug = fn conn ->
        send(test_pid, {:queue_request, conn.method})

        case Agent.get_and_update(calls, &{&1, &1 + 1}) do
          0 -> Req.Test.transport_error(conn, :closed)
          _ -> Plug.Conn.resp(conn, status, "")
        end
      end

      AzureSDK.Storage.Client.new(
        account: AzureMock.account(),
        credential: AzureMock.credential(),
        endpoint: "http://localhost/#{AzureMock.account()}",
        retry: @retry,
        req_options: [plug: plug]
      )
    end

    test "update is not retried" do
      client = flaky_client(self(), 204)

      assert {:error, %AzureSDK.Error{}} =
               Message.update(client, "jobs", "m", pop_receipt: "p", visibility_timeout: 0)

      assert_received {:queue_request, "PUT"}
      refute_received {:queue_request, _}
    end

    test "delete is retried" do
      client = flaky_client(self(), 204)

      assert {:ok, :deleted} = Message.delete(client, "jobs", "m", pop_receipt: "p")
      assert_received {:queue_request, "DELETE"}
      assert_received {:queue_request, "DELETE"}
    end
  end
end
