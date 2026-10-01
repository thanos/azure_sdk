defmodule AzureSDK.Core.Xml.QueueMessages do
  @moduledoc false

  import SweetXml

  alias AzureSDK.Core.Xml.Safe

  @typedoc """
  How message text is stored on the queue.

  * `:base64` - Base64 of the raw bytes (Azure Functions, v11 SDKs)
  * `:none` - the text itself, XML-escaped on the wire (v12 Python/.NET defaults)
  """
  @type encoding :: :base64 | :none

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
  # `content` is `nil` when the response has no MessageText (Put Message), and
  # `""` for an empty message. With `:base64`, text that is not valid Base64 is
  # an error rather than being returned undecoded.
  @spec parse(binary(), encoding()) ::
          {:ok, [message()]} | {:error, :invalid_xml | {:invalid_base64, String.t()}}
  def parse(xml, encoding \\ :base64) when encoding in [:base64, :none] do
    with {:ok, items} <- Safe.run(fn -> parse_xml(xml) end) do
      decode_all(items, encoding, [])
    end
  end

  @doc false
  # Dialyzer's success typing is a binary pattern literal; keep the public contract.
  @dialyzer {:nowarn_function, encode_put: 1, encode_put: 2}
  @spec encode_put(binary(), encoding()) :: binary()
  def encode_put(content, encoding \\ :base64) when is_binary(content) do
    text =
      case encoding do
        :base64 -> Base.encode64(content)
        :none -> escape(content)
      end

    ~s(<?xml version="1.0" encoding="utf-8"?>) <>
      "<QueueMessage><MessageText>" <> text <> "</MessageText></QueueMessage>"
  end

  defp parse_xml(xml) do
    xpath(
      xml,
      ~x"//QueueMessagesList/QueueMessage"l,
      id: ~x"./MessageId/text()"s,
      pop_receipt: ~x"./PopReceipt/text()"s,
      insertion_time: ~x"./InsertionTime/text()"s,
      expiration_time: ~x"./ExpirationTime/text()"s,
      time_next_visible: ~x"./TimeNextVisible/text()"s,
      dequeue_count: ~x"./DequeueCount/text()"s,
      has_text: ~x"count(./MessageText)"i,
      message_text: ~x"string(./MessageText)"s
    )
  end

  defp decode_all([], _encoding, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_all([item | rest], encoding, acc) do
    with {:ok, content} <- decode(item, encoding) do
      decode_all(rest, encoding, [to_message(item, content) | acc])
    end
  end

  defp decode(%{has_text: 0}, _encoding), do: {:ok, nil}
  defp decode(%{message_text: text}, :none), do: {:ok, text}

  defp decode(%{message_text: text, id: id}, :base64) do
    case Base.decode64(text) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, {:invalid_base64, id}}
    end
  end

  defp to_message(item, content) do
    %{
      id: item.id,
      pop_receipt: Safe.blank_to_nil(item.pop_receipt),
      insertion_time: Safe.blank_to_nil(item.insertion_time),
      expiration_time: Safe.blank_to_nil(item.expiration_time),
      time_next_visible: Safe.blank_to_nil(item.time_next_visible),
      dequeue_count: parse_integer(item.dequeue_count),
      content: content
    }
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp parse_integer(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end
end
