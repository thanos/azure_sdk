defmodule AzureSDK.Core.Xml.QueueMessages do
  @moduledoc false

  import SweetXml

  alias AzureSDK.Core.Xml.Safe

  @type message :: %{
          id: String.t(),
          pop_receipt: String.t() | nil,
          insertion_time: String.t() | nil,
          expiration_time: String.t() | nil,
          time_next_visible: String.t() | nil,
          dequeue_count: non_neg_integer() | nil,
          content: binary() | nil
        }

  @doc false
  @spec parse(binary()) :: [message()]
  def parse(xml) do
    case Safe.run(fn -> parse_xml(xml) end) do
      {:ok, messages} -> messages
      {:error, :invalid_xml} -> []
    end
  end

  @doc false
  @spec encode_put(binary()) :: binary()
  # Dialyzer success typing is a binary pattern literal; keep the public contract.
  @dialyzer {:nowarn_function, encode_put: 1}
  def encode_put(content) when is_binary(content) do
    text = Base.encode64(content)

    """
    <?xml version="1.0" encoding="utf-8"?>
    <QueueMessage><MessageText>#{text}</MessageText></QueueMessage>
    """
  end

  defp parse_xml(xml) do
    xml
    |> xpath(
      ~x"//QueueMessagesList/QueueMessage"l,
      id: ~x"./MessageId/text()"s,
      pop_receipt: ~x"./PopReceipt/text()"s,
      insertion_time: ~x"./InsertionTime/text()"s,
      expiration_time: ~x"./ExpirationTime/text()"s,
      time_next_visible: ~x"./TimeNextVisible/text()"s,
      dequeue_count: ~x"./DequeueCount/text()"s,
      message_text: ~x"./MessageText/text()"s
    )
    |> Enum.map(&to_message/1)
  end

  defp to_message(item) do
    %{
      id: item[:id],
      pop_receipt: blank_to_nil(item[:pop_receipt]),
      insertion_time: blank_to_nil(item[:insertion_time]),
      expiration_time: blank_to_nil(item[:expiration_time]),
      time_next_visible: blank_to_nil(item[:time_next_visible]),
      dequeue_count: parse_integer(item[:dequeue_count]),
      content: decode_content(item[:message_text])
    }
  end

  defp decode_content(nil), do: nil
  defp decode_content(""), do: nil

  defp decode_content(text) do
    case Base.decode64(text) do
      {:ok, binary} -> binary
      :error -> text
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil

  defp parse_integer(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end
end
