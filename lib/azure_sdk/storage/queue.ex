defmodule AzureSDK.Storage.Queue do
  @moduledoc """
  Azure Queue Storage queue operations.

  Build a client with `service: :queue` (or an Azurite Queue endpoint on port
  10001). Message APIs live in `AzureSDK.Storage.Queue.Message`.

  ## Queue map (`t:queue/0`)

      %{
        name: "jobs",
        properties: %{approximate_message_count: "0"},
        metadata: %{"env" => "dev"}
      }

  ## List page (`t:page/0`)

      %{items: [%{name: "jobs", metadata: %{}}], marker: nil}
  """

  alias AzureSDK.Core.Telemetry
  alias AzureSDK.Core.Xml.ListQueues
  alias AzureSDK.Storage.{Client, Metadata, Operation}

  @typedoc """
  Queue result map.

  * `:name` - queue name
  * `:properties` - service properties when returned (for example approximate count)
  * `:metadata` - user metadata without the `x-ms-meta-` prefix
  """
  @type queue :: %{
          name: String.t(),
          properties: map(),
          metadata: map()
        }

  @typedoc """
  A single list page with continuation marker.
  """
  @type page :: %{items: [map()], marker: String.t() | nil}

  @doc """
  Creates a queue.

  ## Options

  * `:metadata` - string-keyed user metadata

  ## Examples

      {:ok, queue} = AzureSDK.Storage.Queue.create(client, "jobs")

      {:ok, queue} =
        AzureSDK.Storage.Queue.create(client, "jobs", metadata: %{"env" => "dev"})
  """
  @spec create(Client.t(), String.t(), keyword()) ::
          {:ok, queue()} | {:error, AzureSDK.Error.t()}
  def create(client, name, opts \\ []) do
    Telemetry.emit_operation(:queue, :create, %{name: name})

    headers = Metadata.headers(Keyword.get(opts, :metadata, %{}))

    with {:ok, response} <-
           Operation.run(client,
             method: :put,
             path: Operation.queue_path(name),
             headers: headers,
             body: "",
             service: :queue,
             operation: :create
           ) do
      {:ok, queue_from_response(name, response, opts)}
    end
  end

  @doc """
  Deletes a queue.

  ## Examples

      {:ok, :deleted} = AzureSDK.Storage.Queue.delete(client, "jobs")
  """
  @spec delete(Client.t(), String.t(), keyword()) ::
          {:ok, :deleted} | {:error, AzureSDK.Error.t()}
  def delete(client, name, _opts \\ []) do
    Telemetry.emit_operation(:queue, :delete, %{name: name})

    with {:ok, _} <-
           Operation.run(client,
             method: :delete,
             path: Operation.queue_path(name),
             service: :queue,
             operation: :delete
           ) do
      {:ok, :deleted}
    end
  end

  @doc """
  Returns whether the queue exists.

  ## Examples

      true = AzureSDK.Storage.Queue.exists?(client, "jobs")
  """
  @spec exists?(Client.t(), String.t(), keyword()) ::
          boolean() | {:error, AzureSDK.Error.t()}
  def exists?(client, name, _opts \\ []) do
    Telemetry.emit_operation(:queue, :exists, %{name: name})

    case head_metadata(client, name, :exists) do
      {:ok, _} -> true
      {:error, %{status: 404}} -> false
      {:error, %{code: "QueueNotFound"}} -> false
      {:error, _} = error -> error
    end
  end

  @doc """
  Returns queue user metadata.

  ## Examples

      {:ok, %{"env" => "dev"}} = AzureSDK.Storage.Queue.metadata(client, "jobs")
  """
  @spec metadata(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, AzureSDK.Error.t()}
  def metadata(client, name, _opts \\ []) do
    Telemetry.emit_operation(:queue, :metadata, %{name: name})

    with {:ok, response} <- head_metadata(client, name, :metadata) do
      {:ok, Metadata.from_headers(response.headers)}
    end
  end

  @doc """
  Sets queue metadata. Replaces all existing metadata keys.

  ## Examples

      {:ok, %{"env" => "prod"}} =
        AzureSDK.Storage.Queue.set_metadata(client, "jobs", %{"env" => "prod"})
  """
  @spec set_metadata(Client.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, AzureSDK.Error.t()}
  def set_metadata(client, name, metadata, _opts \\ []) do
    Telemetry.emit_operation(:queue, :set_metadata, %{name: name})

    with {:ok, _} <-
           Operation.run(client,
             method: :put,
             path: Operation.queue_path(name),
             query: [{"comp", "metadata"}],
             headers: Metadata.headers(metadata),
             body: "",
             service: :queue,
             operation: :set_metadata
           ) do
      {:ok, metadata}
    end
  end

  @doc """
  Lists all queues (eager).

  Accepts the same options as `list_page/2`. `:max_results` is the page size;
  `:marker` is managed internally.

  ## Examples

      {:ok, queues} = AzureSDK.Storage.Queue.list(client)
      {:ok, queues} = AzureSDK.Storage.Queue.list(client, prefix: "job-", max_results: 50)
  """
  @spec list(Client.t(), keyword()) :: {:ok, [queue()]} | {:error, AzureSDK.Error.t()}
  def list(client, opts \\ []) do
    Telemetry.emit_operation(:queue, :list, %{})
    Operation.collect_pages(&list_page(client, Keyword.put(opts, :marker, &1)))
  end

  @doc """
  Lists one page of queues.

  ## Options

  * `:marker` - continuation token
  * `:max_results` - page size
  * `:prefix` - name prefix filter

  ## Examples

      {:ok, %{items: items, marker: nil}} =
        AzureSDK.Storage.Queue.list_page(client, max_results: 50, prefix: "job-")
  """
  @spec list_page(Client.t(), keyword()) :: {:ok, page()} | {:error, AzureSDK.Error.t()}
  def list_page(client, opts \\ []) do
    Telemetry.emit_operation(:queue, :list_page, %{})

    query =
      [{"comp", "list"}]
      |> Operation.maybe_query("marker", Keyword.get(opts, :marker))
      |> Operation.maybe_query("maxresults", Keyword.get(opts, :max_results))
      |> Operation.maybe_query("prefix", Keyword.get(opts, :prefix))

    with {:ok, response} <-
           Operation.run(client,
             method: :get,
             path: "/",
             query: query,
             service: :queue,
             operation: :list_page
           ) do
      page = ListQueues.parse_page(response.body || "")
      {:ok, %{items: page.items, marker: blank_to_nil(page.marker)}}
    end
  end

  @doc """
  Lazily streams queues across pages.

  Mid-stream failures raise `AzureSDK.Storage.Queue.StreamError`.

  ## Examples

      names =
        client
        |> AzureSDK.Storage.Queue.list_stream(prefix: "job-")
        |> Enum.map(& &1.name)
  """
  @spec list_stream(Client.t(), keyword()) :: Enumerable.t()
  def list_stream(client, opts \\ []) do
    Operation.page_stream(
      &list_page(client, Keyword.put(opts, :marker, &1)),
      AzureSDK.Storage.Queue.StreamError
    )
  end

  @doc """
  Deletes all messages in a queue.

  ## Examples

      {:ok, :cleared} = AzureSDK.Storage.Queue.clear_messages(client, "jobs")
  """
  @spec clear_messages(Client.t(), String.t(), keyword()) ::
          {:ok, :cleared} | {:error, AzureSDK.Error.t()}
  def clear_messages(client, name, _opts \\ []) do
    Telemetry.emit_operation(:queue, :clear, %{name: name})

    with {:ok, _} <-
           Operation.run(client,
             method: :delete,
             path: Operation.queue_messages_path(name),
             service: :queue,
             operation: :clear
           ) do
      {:ok, :cleared}
    end
  end

  defp head_metadata(client, name, operation) do
    Operation.run(client,
      method: :get,
      path: Operation.queue_path(name),
      query: [{"comp", "metadata"}],
      service: :queue,
      operation: operation
    )
  end

  defp queue_from_response(name, response, opts) do
    %{
      name: name,
      properties: %{
        etag: Operation.header(response, "etag"),
        last_modified: Operation.header(response, "last-modified"),
        approximate_message_count: Operation.header(response, "x-ms-approximate-messages-count")
      },
      metadata: Keyword.get(opts, :metadata, Metadata.from_headers(response.headers))
    }
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end

defmodule AzureSDK.Storage.Queue.StreamError do
  @moduledoc """
  Raised when a mid-stream list page fails inside `Queue.list_stream/2`.

  ## Fields

  * `:reason` - typically `%AzureSDK.Error{}` from a failed list page
  """
  defexception [:reason]

  @impl true
  def message(%{reason: reason}), do: "queue stream failed: #{inspect(reason)}"
end
