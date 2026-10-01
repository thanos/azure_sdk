defmodule AzureSDK.Core.Xml.QueueXmlTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Core.Xml.{ListQueues, QueueMessages}

  test "parses a list queues page" do
    xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <EnumerationResults>
      <Queues>
        <Queue><Name>a</Name></Queue>
        <Queue><Name>b</Name></Queue>
      </Queues>
      <NextMarker>next</NextMarker>
    </EnumerationResults>
    """

    assert %{items: [%{name: "a"}, %{name: "b"}], marker: "next"} =
             ListQueues.parse_page(xml)
  end

  test "returns empty page for invalid list xml" do
    assert %{items: [], marker: nil} = ListQueues.parse_page("not-xml")
  end

  test "encodes and parses queue messages" do
    xml = QueueMessages.encode_put("hello")
    assert String.contains?(xml, Base.encode64("hello"))

    list = """
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

    assert [%{id: "id-1", pop_receipt: "pr", dequeue_count: 2, content: "hello"}] =
             QueueMessages.parse(list)
  end
end
