defmodule AzureSDK.Storage.Queue.Message do
  @moduledoc """
  Azure Queue Storage message operations.

  ## Message encoding

  The service stores message text as-is; whether that text is Base64 is a
  convention between producers and consumers. Every function that sends or
  reads message text takes `:message_encoding`:

  * `:base64` (default) - bodies are Base64 of the raw bytes. Matches Azure
    Functions and the v11 SDKs, and can carry any binary. Reading text that is
    not valid Base64 returns `{:error, %AzureSDK.Error{code: "InvalidMessageEncoding"}}`
    rather than guessing.
  * `:none` - bodies are the text itself (XML-escaped on the wire). Matches the
    default of the v12 Python and .NET SDKs. Content must be valid UTF-8 and may
    not contain XML-illegal control characters.

  Producers and consumers of one queue must agree on the encoding.

  ## Message map (`t:message/0`)

      %{
        id: "...",
        pop_receipt: "...",
        insertion_time: "...",
        expiration_time: "...",
        time_next_visible: "...",
        dequeue_count: 1,
        content: "hello"
      }

  `content` is `nil` when the response carries no message text (Put Message,
  and Update Message without `:content`), and `""` for an empty message.

  ## Limits

  A message may be up to 64 KiB after encoding (about 48 KiB of raw content
  with `:base64`). `:number_of_messages` is `1..32`, and visibility timeouts are
  at most 7 days (`604_800` seconds). Out-of-range values return
  `{:error, %AzureSDK.Error{code: "InvalidArgument"}}` without a request.

  ## Retries

  Put Message, Get Messages and Update Message set `metadata.idempotent: false`,
  so ambiguous 5xx and transport failures are not retried: Put would enqueue a
  duplicate, Get has visibility side effects, and a successful Update issues a
  new pop receipt that a retry would not know. Peek and Delete are retried.
  """

  alias AzureSDK.Core.Telemetry
  alias AzureSDK.Core.Xml.QueueMessages
  alias AzureSDK.Error
  alias AzureSDK.Storage.{Client, Operation}

  @max_message_bytes 64 * 1024
  @max_visibility 604_800

  @typedoc """
  Queue message result map.
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
  Enqueues a message.

  ## Parameters

  * `client` - queue `Storage.Client`
  * `queue` - queue name
  * `content` - binary or iodata body
  * `opts` - optional keyword list

  ## Options

  * `:message_encoding` - `:base64` (default) or `:none`; see the module docs
  * `:visibility_timeout` - seconds (`0..604_800`) before the message becomes visible
  * `:message_ttl` - seconds until the message expires (`-1` for no expiry)

  Returns the new message's id, pop receipt and times; `:content` is `nil`
  because the service does not echo it.

  ## Examples

      {:ok, %{id: id}} = AzureSDK.Storage.Queue.Message.put(client, "jobs", "hello")

      {:ok, message} =
        AzureSDK.Storage.Queue.Message.put(client, "jobs", ~s({"job": 1}),
          message_encoding: :none,
          visibility_timeout: 0,
          message_ttl: 3600
        )
  """
  @spec put(Client.t(), String.t(), iodata(), keyword()) ::
          {:ok, message()} | {:error, Error.t()}
  def put(client, queue, content, opts \\ []) do
    Telemetry.emit_operation(:queue, :put_message, %{name: queue})

    with {:ok, encoding} <- encoding(opts),
         :ok <- check_range(opts, :visibility_timeout, 0..@max_visibility),
         :ok <- check_ttl(Keyword.get(opts, :message_ttl)),
         {:ok, body} <- message_body(content, encoding),
         {:ok, response} <-
           Operation.run(client,
             method: :post,
             path: Operation.queue_messages_path(queue),
             query:
               []
               |> Operation.maybe_query(
                 "visibilitytimeout",
                 Keyword.get(opts, :visibility_timeout)
               )
               |> Operation.maybe_query("messagettl", Keyword.get(opts, :message_ttl)),
             headers: body_headers(body),
             body: body,
             service: :queue,
             operation: :put_message,
             metadata: %{idempotent: false}
           ),
         {:ok, messages} <- parse(response, encoding) do
      case messages do
        [message | _] -> {:ok, message}
        [] -> {:error, invalid_response("Put Message response contained no message")}
      end
    end
  end

  @doc """
  Dequeues messages (makes them invisible for the visibility timeout).

  ## Options

  * `:number_of_messages` - `1..32` (default `1`)
  * `:visibility_timeout` - seconds (`1..604_800`) the messages stay invisible
  * `:message_encoding` - `:base64` (default) or `:none`

  ## Examples

      {:ok, [msg]} = AzureSDK.Storage.Queue.Message.get(client, "jobs")

      {:ok, messages} =
        AzureSDK.Storage.Queue.Message.get(client, "jobs",
          number_of_messages: 5,
          visibility_timeout: 30
        )
  """
  @spec get(Client.t(), String.t(), keyword()) ::
          {:ok, [message()]} | {:error, Error.t()}
  def get(client, queue, opts \\ []) do
    Telemetry.emit_operation(:queue, :get_messages, %{name: queue})

    with {:ok, encoding} <- encoding(opts),
         :ok <- check_range(opts, :number_of_messages, 1..32),
         :ok <- check_range(opts, :visibility_timeout, 1..@max_visibility),
         {:ok, response} <-
           Operation.run(client,
             method: :get,
             path: Operation.queue_messages_path(queue),
             query:
               [{"numofmessages", to_string(Keyword.get(opts, :number_of_messages, 1))}]
               |> Operation.maybe_query(
                 "visibilitytimeout",
                 Keyword.get(opts, :visibility_timeout)
               ),
             service: :queue,
             operation: :get_messages,
             metadata: %{idempotent: false}
           ) do
      parse(response, encoding)
    end
  end

  @doc """
  Peeks messages without changing visibility.

  ## Options

  * `:number_of_messages` - `1..32` (default `1`)
  * `:message_encoding` - `:base64` (default) or `:none`

  ## Examples

      {:ok, [msg]} = AzureSDK.Storage.Queue.Message.peek(client, "jobs")
  """
  @spec peek(Client.t(), String.t(), keyword()) ::
          {:ok, [message()]} | {:error, Error.t()}
  def peek(client, queue, opts \\ []) do
    Telemetry.emit_operation(:queue, :peek_messages, %{name: queue})

    with {:ok, encoding} <- encoding(opts),
         :ok <- check_range(opts, :number_of_messages, 1..32),
         {:ok, response} <-
           Operation.run(client,
             method: :get,
             path: Operation.queue_messages_path(queue),
             query: [
               {"peekonly", "true"},
               {"numofmessages", to_string(Keyword.get(opts, :number_of_messages, 1))}
             ],
             service: :queue,
             operation: :peek_messages
           ) do
      parse(response, encoding)
    end
  end

  @doc """
  Deletes a message using its id and pop receipt.

  A message that no longer exists (`404 MessageNotFound`) counts as deleted:
  it was already deleted, possibly by an earlier attempt of this same call
  whose response was lost, or it expired. A stale pop receipt still returns
  `{:error, %AzureSDK.Error{status: 400, code: "PopReceiptMismatch"}}`.

  ## Options

  * `:pop_receipt` (required)

  ## Examples

      {:ok, :deleted} =
        AzureSDK.Storage.Queue.Message.delete(client, "jobs", message.id,
          pop_receipt: message.pop_receipt
        )
  """
  @spec delete(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, :deleted} | {:error, Error.t()}
  def delete(client, queue, message_id, opts \\ []) do
    Telemetry.emit_operation(:queue, :delete_message, %{name: queue})

    with {:ok, req} <- Operation.require_opts(opts, [:pop_receipt], :queue) do
      case Operation.run(client,
             method: :delete,
             path: Operation.queue_message_path(queue, message_id),
             query: [{"popreceipt", req.pop_receipt}],
             service: :queue,
             operation: :delete_message
           ) do
        {:ok, _} -> {:ok, :deleted}
        {:error, %Error{status: 404, code: "MessageNotFound"}} -> {:ok, :deleted}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Updates a message's visibility timeout and optionally its content.

  Without `:content`, only the visibility timeout changes and the message body
  is kept. Not retried by the pipeline (see the module docs).

  ## Options

  * `:pop_receipt` (required)
  * `:visibility_timeout` (required) - new visibility in seconds (`0..604_800`)
  * `:content` - new body (iodata); omit to keep the current body
  * `:message_encoding` - `:base64` (default) or `:none`, for `:content`

  Returns the message id, the new pop receipt and next-visible time. `:content`
  is the new body when given, otherwise `nil`.

  ## Examples

      {:ok, updated} =
        AzureSDK.Storage.Queue.Message.update(client, "jobs", message.id,
          pop_receipt: message.pop_receipt,
          visibility_timeout: 60
        )

      {:ok, updated} =
        AzureSDK.Storage.Queue.Message.update(client, "jobs", message.id,
          pop_receipt: message.pop_receipt,
          visibility_timeout: 0,
          content: "retry later"
        )
  """
  @spec update(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, message()} | {:error, Error.t()}
  def update(client, queue, message_id, opts \\ []) do
    Telemetry.emit_operation(:queue, :update_message, %{name: queue})

    with {:ok, req} <-
           Operation.require_opts(opts, [:pop_receipt, :visibility_timeout], :queue),
         {:ok, encoding} <- encoding(opts),
         :ok <- check_range(opts, :visibility_timeout, 0..@max_visibility),
         {:ok, content, body} <- update_body(Keyword.get(opts, :content), encoding),
         {:ok, response} <-
           Operation.run(client,
             method: :put,
             path: Operation.queue_message_path(queue, message_id),
             query: [
               {"popreceipt", req.pop_receipt},
               {"visibilitytimeout", to_string(req.visibility_timeout)}
             ],
             headers: body_headers(body),
             body: body,
             service: :queue,
             operation: :update_message,
             metadata: %{idempotent: false}
           ) do
      {:ok,
       %{
         id: message_id,
         pop_receipt: Operation.header(response, "x-ms-popreceipt"),
         insertion_time: nil,
         expiration_time: nil,
         time_next_visible: Operation.header(response, "x-ms-time-next-visible"),
         dequeue_count: nil,
         content: content
       }}
    end
  end

  defp update_body(nil, _encoding), do: {:ok, nil, ""}

  defp update_body(content, encoding) do
    with {:ok, body} <- message_body(content, encoding) do
      {:ok, IO.iodata_to_binary(content), body}
    end
  end

  defp message_body(content, encoding) do
    content = IO.iodata_to_binary(content)

    with :ok <- check_text(content, encoding) do
      body = QueueMessages.encode_put(content, encoding)
      text_bytes = byte_size(body) - byte_size(QueueMessages.encode_put("", encoding))

      if text_bytes > @max_message_bytes do
        {:error,
         invalid_argument(
           "Message is #{text_bytes} bytes after #{encoding} encoding; the limit is #{@max_message_bytes}"
         )}
      else
        {:ok, body}
      end
    end
  end

  defp body_headers(""), do: %{"Content-Length" => "0"}

  defp body_headers(body) do
    %{"Content-Type" => "application/xml", "Content-Length" => Integer.to_string(byte_size(body))}
  end

  defp parse(response, encoding) do
    case QueueMessages.parse(response.body || "", encoding) do
      {:ok, messages} ->
        {:ok, messages}

      {:error, :invalid_xml} ->
        {:error, invalid_response("Queue messages response is not valid XML")}

      {:error, {:invalid_base64, id}} ->
        {:error,
         Error.new(
           code: "InvalidMessageEncoding",
           message:
             "Message #{inspect(id)} is not valid Base64; read it with message_encoding: :none " <>
               "if its producer does not Base64-encode",
           service: :queue
         )}
    end
  end

  defp encoding(opts) do
    case Keyword.get(opts, :message_encoding, :base64) do
      encoding when encoding in [:base64, :none] ->
        {:ok, encoding}

      other ->
        {:error,
         invalid_argument(":message_encoding must be :base64 or :none, got #{inspect(other)}")}
    end
  end

  defp check_text(_content, :base64), do: :ok

  defp check_text(content, :none) do
    cond do
      not String.valid?(content) ->
        {:error, invalid_argument("message_encoding: :none requires valid UTF-8 content")}

      String.match?(content, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/) ->
        {:error, invalid_argument("message_encoding: :none cannot carry XML control characters")}

      true ->
        :ok
    end
  end

  defp check_range(opts, key, range) do
    case Keyword.get(opts, key) do
      nil ->
        :ok

      value when is_integer(value) ->
        if value in range, do: :ok, else: range_error(key, value, range)

      value ->
        range_error(key, value, range)
    end
  end

  defp range_error(key, value, first..last//_) do
    {:error,
     invalid_argument(
       "#{inspect(key)} must be an integer in #{first}..#{last}, got #{inspect(value)}"
     )}
  end

  defp check_ttl(nil), do: :ok
  defp check_ttl(-1), do: :ok
  defp check_ttl(ttl) when is_integer(ttl) and ttl > 0, do: :ok

  defp check_ttl(ttl) do
    {:error,
     invalid_argument(":message_ttl must be -1 or a positive integer, got #{inspect(ttl)}")}
  end

  defp invalid_argument(message) do
    Error.new(code: "InvalidArgument", message: message, service: :queue)
  end

  defp invalid_response(message) do
    Error.new(code: "InvalidResponse", message: message, service: :queue)
  end
end
