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
    assert {:ok, [_]} = Message.put(client, queue, "hello-azurite")

    assert {:ok, [peeked]} = Message.peek(client, queue)
    assert peeked.content == "hello-azurite"

    assert {:ok, [msg]} = Message.get(client, queue, visibility_timeout: 30)
    assert msg.content == "hello-azurite"
    assert is_binary(msg.pop_receipt)

    assert {:ok, updated} =
             Message.update(client, queue, msg.id,
               pop_receipt: msg.pop_receipt,
               visibility_timeout: 60,
               content: "updated"
             )

    assert {:ok, :deleted} =
             Message.delete(client, queue, msg.id, pop_receipt: updated.pop_receipt)

    assert {:ok, :cleared} = Queue.clear_messages(client, queue)
  end

  test "list and metadata", %{client: client, queue: queue} do
    assert Queue.exists?(client, queue) == true

    assert {:ok, %{"owner" => "test"}} =
             Queue.set_metadata(client, queue, %{"owner" => "test"})

    assert {:ok, %{"owner" => "test"}} = Queue.metadata(client, queue)

    assert {:ok, queues} = Queue.list(client, prefix: String.slice(queue, 0, 4))
    assert Enum.any?(queues, &(&1.name == queue))
  end
end
