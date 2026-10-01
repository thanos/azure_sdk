defmodule AzureSDK.Storage.Queue.Message do
  @moduledoc """
  Azure Queue Storage message operations.

  Message bodies are Base64-encoded in the Queue XML wire format. This module
  accepts `iodata()` on put/update and returns binary `:content` on get/peek.
  Decode UTF-8 strings yourself when needed.

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

  Put Message and Get Messages set `metadata.idempotent: false` so the pipeline
  does not retry ambiguous 5xx/transport failures (Get Messages has visibility
  side effects despite using GET).
  """

  alias AzureSDK.Core.Telemetry
  alias AzureSDK.Core.Xml.QueueMessages
  alias AzureSDK.Storage.{Client, Operation}

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

  * `:visibility_timeout` - seconds before the message becomes visible
  * `:message_ttl` - seconds until the message expires (`-1` for max TTL)

  ## Examples

      {:ok, [message]} =
        AzureSDK.Storage.Queue.Message.put(client, "jobs", "hello")

      {:ok, [message]} =
        AzureSDK.Storage.Queue.Message.put(client, "jobs", "hello",
          visibility_timeout: 0,
          message_ttl: 3600
        )
  """
  @spec put(Client.t(), String.t(), iodata(), keyword()) ::
          {:ok, [message()]} | {:error, AzureSDK.Error.t()}
  def put(client, queue, content, opts \\ []) do
    Telemetry.emit_operation(:queue, :put_message, %{name: queue})

    body = content |> IO.iodata_to_binary() |> QueueMessages.encode_put()

    query =
      []
      |> Operation.maybe_query("visibilitytimeout", Keyword.get(opts, :visibility_timeout))
      |> Operation.maybe_query("messagettl", Keyword.get(opts, :message_ttl))

    with {:ok, response} <-
           Operation.run(client,
             method: :post,
             path: Operation.queue_messages_path(queue),
             query: query,
             headers: %{
               "Content-Type" => "application/xml",
               "Content-Length" => Integer.to_string(byte_size(body))
             },
             body: body,
             service: :queue,
             operation: :put_message,
             metadata: %{idempotent: false}
           ) do
      {:ok, QueueMessages.parse(response.body || "")}
    end
  end

  @doc """
  Dequeues messages (makes them invisible for the visibility timeout).

  ## Options

  * `:number_of_messages` - 1..32 (default `1`)
  * `:visibility_timeout` - seconds the messages stay invisible

  ## Examples

      {:ok, [msg]} = AzureSDK.Storage.Queue.Message.get(client, "jobs")

      {:ok, messages} =
        AzureSDK.Storage.Queue.Message.get(client, "jobs",
          number_of_messages: 5,
          visibility_timeout: 30
        )
  """
  @spec get(Client.t(), String.t(), keyword()) ::
          {:ok, [message()]} | {:error, AzureSDK.Error.t()}
  def get(client, queue, opts \\ []) do
    Telemetry.emit_operation(:queue, :get_messages, %{name: queue})

    query =
      []
      |> Operation.maybe_query(
        "numofmessages",
        Keyword.get(opts, :number_of_messages, 1)
      )
      |> Operation.maybe_query("visibilitytimeout", Keyword.get(opts, :visibility_timeout))

    with {:ok, response} <-
           Operation.run(client,
             method: :get,
             path: Operation.queue_messages_path(queue),
             query: query,
             service: :queue,
             operation: :get_messages,
             metadata: %{idempotent: false}
           ) do
      {:ok, QueueMessages.parse(response.body || "")}
    end
  end

  @doc """
  Peeks messages without changing visibility.

  ## Options

  * `:number_of_messages` - 1..32 (default `1`)

  ## Examples

      {:ok, [msg]} = AzureSDK.Storage.Queue.Message.peek(client, "jobs")
  """
  @spec peek(Client.t(), String.t(), keyword()) ::
          {:ok, [message()]} | {:error, AzureSDK.Error.t()}
  def peek(client, queue, opts \\ []) do
    Telemetry.emit_operation(:queue, :peek_messages, %{name: queue})

    query =
      [{"peekonly", "true"}]
      |> Operation.maybe_query(
        "numofmessages",
        Keyword.get(opts, :number_of_messages, 1)
      )

    with {:ok, response} <-
           Operation.run(client,
             method: :get,
             path: Operation.queue_messages_path(queue),
             query: query,
             service: :queue,
             operation: :peek_messages
           ) do
      {:ok, QueueMessages.parse(response.body || "")}
    end
  end

  @doc """
  Deletes a message using its id and pop receipt.

  ## Options

  * `:pop_receipt` (required)

  ## Examples

      {:ok, :deleted} =
        AzureSDK.Storage.Queue.Message.delete(client, "jobs", message.id,
          pop_receipt: message.pop_receipt
        )
  """
  @spec delete(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, :deleted} | {:error, AzureSDK.Error.t()}
  def delete(client, queue, message_id, opts \\ []) do
    Telemetry.emit_operation(:queue, :delete_message, %{name: queue})

    with {:ok, req} <- Operation.require_opts(opts, [:pop_receipt], :queue),
         {:ok, _} <-
           Operation.run(client,
             method: :delete,
             path: Operation.queue_message_path(queue, message_id),
             query: [{"popreceipt", req.pop_receipt}],
             service: :queue,
             operation: :delete_message
           ) do
      {:ok, :deleted}
    end
  end

  @doc """
  Updates a message's visibility timeout and optionally its content.

  ## Options

  * `:pop_receipt` (required)
  * `:visibility_timeout` (required) - new visibility in seconds
  * `:content` - optional new body (iodata). Azure requires a message body on
    update; pass `:content` to replace, or re-send the previous content

  ## Examples

      {:ok, updated} =
        AzureSDK.Storage.Queue.Message.update(client, "jobs", message.id,
          pop_receipt: message.pop_receipt,
          visibility_timeout: 60,
          content: message.content
        )
  """
  @spec update(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, message()} | {:error, AzureSDK.Error.t()}
  def update(client, queue, message_id, opts \\ []) do
    Telemetry.emit_operation(:queue, :update_message, %{name: queue})

    with {:ok, req} <-
           Operation.require_opts(opts, [:pop_receipt, :visibility_timeout], :queue) do
      content = Keyword.get(opts, :content, "")
      body = content |> IO.iodata_to_binary() |> QueueMessages.encode_put()

      query = [
        {"popreceipt", req.pop_receipt},
        {"visibilitytimeout", to_string(req.visibility_timeout)}
      ]

      case Operation.run(client,
             method: :put,
             path: Operation.queue_message_path(queue, message_id),
             query: query,
             headers: %{
               "Content-Type" => "application/xml",
               "Content-Length" => Integer.to_string(byte_size(body))
             },
             body: body,
             service: :queue,
             operation: :update_message
           ) do
        {:ok, response} ->
          {:ok,
           %{
             id: message_id,
             pop_receipt: Operation.header(response, "x-ms-popreceipt"),
             insertion_time: nil,
             expiration_time: nil,
             time_next_visible: Operation.header(response, "x-ms-time-next-visible"),
             dequeue_count: nil,
             content: IO.iodata_to_binary(content)
           }}

        {:error, _} = error ->
          error
      end
    end
  end
end
