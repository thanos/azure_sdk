defmodule AzureSDK.Storage.QueueAzuriteTest do
  use AzureSDK.AzuriteCase

  alias AzureSDK.Storage.Queue
  alias AzureSDK.Storage.Queue.Message

  @queue_endpoint "http://127.0.0.1:10001/devstoreaccount1"

  setup do
    unless azurite_available?(10_001) do
      raise "Azurite Queue is not running on port 10001. Start with: docker compose up -d"
    end

    client = azurite_client(endpoint: @queue_endpoint, service: :queue)
    queue = unique_name("q")
    {:ok, _} = Queue.create(client, queue)
    on_exit(fn -> _ = Queue.delete(client, queue) end)
    %{client: client, queue: queue}
  end

  test "message lifecycle round-trip", %{client: client, queue: queue} do
    assert {:ok, %{id: id, content: nil}} = Message.put(client, queue, "hello-azurite")
    assert is_binary(id)

    assert {:ok, [peeked]} = Message.peek(client, queue)
    assert peeked.content == "hello-azurite"

    assert {:ok, [msg]} = Message.get(client, queue, visibility_timeout: 30)
    assert msg.content == "hello-azurite"
    assert is_binary(msg.pop_receipt)

    assert {:ok, updated} =
             Message.update(client, queue, msg.id,
               pop_receipt: msg.pop_receipt,
               visibility_timeout: 0,
               content: "updated"
             )

    assert {:ok, [%{content: "updated"}]} = Message.peek(client, queue)

    assert {:ok, :deleted} =
             Message.delete(client, queue, msg.id, pop_receipt: updated.pop_receipt)

    assert {:ok, []} = Message.peek(client, queue)
  end

  test "a visibility-only update keeps the message body", %{client: client, queue: queue} do
    assert {:ok, _} = Message.put(client, queue, "important payload")
    assert {:ok, [msg]} = Message.get(client, queue, visibility_timeout: 30)

    assert {:ok, %{content: nil}} =
             Message.update(client, queue, msg.id,
               pop_receipt: msg.pop_receipt,
               visibility_timeout: 0
             )

    assert {:ok, [%{content: "important payload"}]} = Message.peek(client, queue)
  end

  test "deleting an already deleted message succeeds", %{client: client, queue: queue} do
    assert {:ok, _} = Message.put(client, queue, "once")
    assert {:ok, [msg]} = Message.get(client, queue, visibility_timeout: 30)

    assert {:ok, :deleted} = Message.delete(client, queue, msg.id, pop_receipt: msg.pop_receipt)
    assert {:ok, :deleted} = Message.delete(client, queue, msg.id, pop_receipt: msg.pop_receipt)
  end

  test "plain-text messages round-trip with message_encoding: :none", %{
    client: client,
    queue: queue
  } do
    texts = ["true", "TEST", "abcd1234", ~s(<job id="1"> & 'q')]
    for text <- texts, do: {:ok, _} = Message.put(client, queue, text, message_encoding: :none)

    assert {:ok, messages} =
             Message.peek(client, queue, number_of_messages: 4, message_encoding: :none)

    assert Enum.map(messages, & &1.content) == texts

    assert {:error, %{code: "InvalidMessageEncoding"}} =
             Message.peek(client, queue, number_of_messages: 4)
  end

  test "binary and empty messages round-trip with :base64", %{client: client, queue: queue} do
    assert {:ok, _} = Message.put(client, queue, <<0, 255, 1>>)
    assert {:ok, _} = Message.put(client, queue, "")

    assert {:ok, [%{content: <<0, 255, 1>>}, %{content: ""}]} =
             Message.peek(client, queue, number_of_messages: 2)
  end

  test "get returns distinct messages that can each be deleted", %{
    client: client,
    queue: queue
  } do
    for i <- 1..3, do: {:ok, _} = Message.put(client, queue, "m#{i}")

    assert {:ok, messages} =
             Message.get(client, queue, number_of_messages: 3, visibility_timeout: 30)

    assert messages |> Enum.map(& &1.content) |> Enum.sort() == ["m1", "m2", "m3"]
    assert messages |> Enum.map(& &1.id) |> Enum.uniq() |> length() == 3

    for msg <- messages do
      assert {:ok, :deleted} = Message.delete(client, queue, msg.id, pop_receipt: msg.pop_receipt)
    end

    assert {:ok, %{approximate_message_count: 0}} = Queue.properties(client, queue)
  end

  test "list, metadata and properties", %{client: client, queue: queue} do
    assert Queue.exists?(client, queue) == true

    assert {:ok, %{"owner" => "test"}} =
             Queue.set_metadata(client, queue, %{"owner" => "test"})

    assert {:ok, %{"owner" => "test"}} = Queue.metadata(client, queue)

    assert {:ok, [%{name: ^queue, metadata: nil}]} = Queue.list(client, prefix: queue)

    assert {:ok, [%{name: ^queue, metadata: %{"owner" => "test"}}]} =
             Queue.list(client, prefix: queue, include_metadata: true)

    for i <- 1..2, do: {:ok, _} = Message.put(client, queue, "m#{i}")

    assert {:ok, %{approximate_message_count: 2, metadata: %{"owner" => "test"}}} =
             Queue.properties(client, queue)
  end
end
