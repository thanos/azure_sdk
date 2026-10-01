defmodule AzureSDK.Core.Xml.QueueXmlTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Core.Xml.{ListQueues, QueueMessages}

  defp messages_xml(texts) do
    entries =
      Enum.map_join(texts, "", fn
        :absent ->
          "<QueueMessage><MessageId>id</MessageId></QueueMessage>"

        text ->
          "<QueueMessage><MessageId>id</MessageId><MessageText>#{text}</MessageText></QueueMessage>"
      end)

    ~s(<?xml version="1.0" encoding="utf-8"?><QueueMessagesList>#{entries}</QueueMessagesList>)
  end

  describe "ListQueues.parse_page/2" do
    test "parses names and the continuation marker" do
      xml = AzureSDK.AzureMock.list_queues_xml(["a", "b"], "next")
      assert %{items: [%{name: "a"}, %{name: "b"}], marker: "next"} = ListQueues.parse_page(xml)
    end

    test "metadata is nil unless requested" do
      xml = AzureSDK.AzureMock.list_queues_xml([{"a", %{"env" => "dev"}}], nil, true)

      assert %{items: [%{name: "a", metadata: nil}]} = ListQueues.parse_page(xml)

      assert %{items: [%{name: "a", metadata: %{"env" => "dev"}}]} =
               ListQueues.parse_page(xml, true)
    end

    test "a requested queue without metadata has an empty map" do
      xml = AzureSDK.AzureMock.list_queues_xml(["a"], nil, true)
      assert %{items: [%{metadata: metadata}]} = ListQueues.parse_page(xml, true)
      assert metadata == %{}
    end

    test "returns an empty page for invalid xml" do
      assert %{items: [], marker: nil} = ListQueues.parse_page("not-xml")
    end
  end

  describe "QueueMessages with :base64" do
    test "round-trips binary content" do
      content = <<0, 255, 10, "hello">>
      body = QueueMessages.encode_put(content)
      [_, text] = Regex.run(~r{<MessageText>(.*)</MessageText>}, body)

      assert {:ok, [%{content: ^content}]} = QueueMessages.parse(messages_xml([text]))
    end

    test "rejects text that is not Base64 instead of returning it raw" do
      assert {:error, {:invalid_base64, "id"}} =
               QueueMessages.parse(messages_xml(["hello world"]))
    end

    test "parses the other message fields" do
      xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <QueueMessagesList>
        <QueueMessage>
          <MessageId>id-1</MessageId>
          <PopReceipt>pr</PopReceipt>
          <DequeueCount>2</DequeueCount>
          <MessageText>#{Base.encode64("hello")}</MessageText>
        </QueueMessage>
      </QueueMessagesList>
      """

      assert {:ok, [%{id: "id-1", pop_receipt: "pr", dequeue_count: 2, content: "hello"}]} =
               QueueMessages.parse(xml)
    end
  end

  describe "QueueMessages with :none" do
    test "plain text that looks like Base64 is returned unchanged" do
      for text <- ["true", "TEST", "abcd1234"] do
        assert {:ok, [%{content: ^text}]} = QueueMessages.parse(messages_xml([text]), :none)
      end
    end

    test "XML-special characters are escaped on put and restored on parse" do
      content = ~s(<job id="1"> & 'quoted')
      body = QueueMessages.encode_put(content, :none)
      refute body =~ "<job"
      [_, text] = Regex.run(~r{<MessageText>(.*)</MessageText>}, body)

      assert {:ok, [%{content: ^content}]} = QueueMessages.parse(messages_xml([text]), :none)
    end
  end

  test "an empty message is \"\" and a missing MessageText is nil" do
    for encoding <- [:base64, :none] do
      assert {:ok, [%{content: ""}, %{content: nil}]} =
               QueueMessages.parse(messages_xml(["", :absent]), encoding)
    end
  end

  test "invalid xml is an error" do
    assert {:error, :invalid_xml} = QueueMessages.parse("<QueueMessagesList>")
  end
end
