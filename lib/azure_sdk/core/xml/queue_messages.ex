defmodule AzureSDK.Core.Xml.QueueMessages do
  @moduledoc """
  Parses and encodes Azure Queue Message XML.

  Used by `AzureSDK.Storage.Queue.Message`. Prefer the Storage APIs unless you
  are inspecting raw service responses.

  ## Encoding (`t:encoding/0`)

  * `:base64` - MessageText is Base64 of the raw bytes
  * `:none` - MessageText is the UTF-8 text (XML-escaped on encode)

  ## Message map (`t:message/0`)

      %{
        id: "msg-1",
        pop_receipt: "pr-1",
        insertion_time: "Wed, 01 Jan 2025 00:00:00 GMT",
        expiration_time: "Wed, 08 Jan 2025 00:00:00 GMT",
        time_next_visible: "Wed, 01 Jan 2025 00:00:30 GMT",
        dequeue_count: 1,
        content: "hello"
      }

  `:content` is `nil` when the response has no `MessageText` element, and `""`
  for an empty element. With `:base64`, text that is not valid Base64 returns
  `{:error, {:invalid_base64, id}}` rather than being returned undecoded.
  """

  import SweetXml

  alias AzureSDK.Core.Xml.Safe

  @typedoc """
  How message text is stored on the queue.

  * `:base64` - Base64 of the raw bytes (Azure Functions, v11 SDKs)
  * `:none` - the text itself, XML-escaped on the wire (v12 Python/.NET defaults)
  """
  @type encoding :: :base64 | :none

  @typedoc """
  Parsed queue message fields from a Get/Peek/Put response.
  """
  @type message :: %{
          id: String.t(),
          pop_receipt: String.t() | nil,
          insertion_time: String.t() | nil,
          expiration_time: String.t() | nil,
          time_next_visible: String.t() | nil,
          dequeue_count: non_neg_integer() | nil,
          content: binary() | nil
        }

  @doc """
  Parses a `QueueMessagesList` XML body.

  ## Parameters

  * `xml` - response body
  * `encoding` - `:base64` (default) or `:none`

  ## Returns

  * `{:ok, [t:message/0]}`
  * `{:error, :invalid_xml}`
  * `{:error, {:invalid_base64, message_id}}` when `:base64` decoding fails

  ## Examples

      iex> xml = ~s(<QueueMessagesList><QueueMessage><MessageId>m</MessageId><MessageText>aGVsbG8=</MessageText><DequeueCount>1</DequeueCount></QueueMessage></QueueMessagesList>)
      iex> {:ok, [%{id: "m", content: "hello", dequeue_count: 1}]} =
      ...>   AzureSDK.Core.Xml.QueueMessages.parse(xml)
      iex> true
      true

      iex> xml = ~s(<QueueMessagesList><QueueMessage><MessageId>m</MessageId><MessageText>hello world</MessageText></QueueMessage></QueueMessagesList>)
      iex> {:ok, [%{content: "hello world"}]} =
      ...>   AzureSDK.Core.Xml.QueueMessages.parse(xml, :none)
      iex> AzureSDK.Core.Xml.QueueMessages.parse(xml, :base64)
      {:error, {:invalid_base64, "m"}}
  """
  @spec parse(binary(), encoding()) ::
          {:ok, [message()]} | {:error, :invalid_xml | {:invalid_base64, String.t()}}
  def parse(xml, encoding \\ :base64) when encoding in [:base64, :none] do
    with {:ok, items} <- Safe.run(fn -> parse_xml(xml) end) do
      decode_all(items, encoding, [])
    end
  end

  @doc """
  Builds a Put/Update Message XML body.

  ## Parameters

  * `content` - message text as a binary
  * `encoding` - `:base64` (default) or `:none`

  ## Returns

  An XML document string with a single `QueueMessage` / `MessageText` element.

  ## Examples

      iex> body = AzureSDK.Core.Xml.QueueMessages.encode_put("hello")
      iex> String.contains?(body, "<MessageText>aGVsbG8=</MessageText>")
      true

      iex> body = AzureSDK.Core.Xml.QueueMessages.encode_put("a & b", :none)
      iex> String.contains?(body, "<MessageText>a &amp; b</MessageText>")
      true
  """
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
