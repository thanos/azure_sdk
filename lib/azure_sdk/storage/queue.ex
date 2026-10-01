defmodule AzureSDK.Storage.Queue do
  @moduledoc """
  Azure Queue Storage queue operations.

  Build a client with `service: :queue`, or point `:endpoint` at Azurite Queue
  (`http://127.0.0.1:10001/devstoreaccount1`). Message APIs live in
  `AzureSDK.Storage.Queue.Message`.

  ## Queue map (`t:queue/0`)

  Returned by `create/3`:

      %{
        name: "jobs",
        properties: %{
          etag: "\\"0x8D…\\"",
          last_modified: "Wed, 01 Jan 2025 00:00:00 GMT"
        },
        metadata: %{"env" => "dev"}
      }

  ## List item (`t:list_item/0`) and page (`t:page/0`)

  `:metadata` is filled only when you list with `include_metadata: true`;
  otherwise it is `nil` (not `%{}`), so "not requested" is never confused with
  "empty".

      %{items: [%{name: "jobs", metadata: nil}], marker: nil}
      %{items: [%{name: "jobs", metadata: %{"env" => "dev"}}], marker: "next"}

  ## Errors

  Failures return `{:error, %AzureSDK.Error{}}` with `service: :queue`.
  `list_stream/2` is the exception: a failed page raises
  `AzureSDK.Storage.Queue.StreamError`.
  """

  alias AzureSDK.Core.Telemetry
  alias AzureSDK.Core.Xml.ListQueues
  alias AzureSDK.Storage.{Client, Metadata, Operation}

  @typedoc """
  Queue result from `create/3`.

  * `:name` - queue name
  * `:properties` - `:etag` and `:last_modified` when the service returns them
  * `:metadata` - user metadata without the `x-ms-meta-` prefix (the map you
    passed on create, or `%{}`)
  """
  @type queue :: %{
          name: String.t(),
          properties: map(),
          metadata: map()
        }

  @typedoc """
  One queue in a list page.

  * `:name` - queue name
  * `:metadata` - user metadata when listed with `include_metadata: true`,
    otherwise `nil`
  """
  @type list_item :: %{name: String.t(), metadata: map() | nil}

  @typedoc """
  One page of queue names.

  * `:items` - `t:list_item/0` entries for this page
  * `:marker` - continuation token, or `nil` when finished
  """
  @type page :: %{items: [list_item()], marker: String.t() | nil}

  @typedoc """
  Result of `properties/3`.

  * `:approximate_message_count` - service estimate (may include invisible or
    soon-to-expire messages), or `nil` if the header is missing
  * `:metadata` - user metadata without the `x-ms-meta-` prefix
  """
  @type properties :: %{approximate_message_count: non_neg_integer() | nil, metadata: map()}

  @doc """
  Creates a queue.

  ## Parameters

  * `client` - queue `AzureSDK.Storage.Client` (`service: :queue` or Queue endpoint)
  * `name` - queue name
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:metadata` - string-keyed user metadata (default `%{}`)

  ## Returns

  * `{:ok, t:queue/0}`
  * `{:error, %AzureSDK.Error{}}` - for example `QueueAlreadyExists` or auth failure

  ## Examples

      {:ok, queue} = AzureSDK.Storage.Queue.create(client, "jobs")

      {:ok, %{name: "jobs", metadata: %{"env" => "dev"}}} =
        AzureSDK.Storage.Queue.create(client, "jobs", metadata: %{"env" => "dev"})
  """
  @spec create(Client.t(), String.t(), keyword()) ::
          {:ok, queue()} | {:error, AzureSDK.Error.t()}
  def create(client, name, opts \\ []) do
    Telemetry.emit_operation(:queue, :create, %{name: name})

    with {:ok, response} <-
           Operation.run(client,
             method: :put,
             path: Operation.queue_path(name),
             headers: Metadata.headers(Keyword.get(opts, :metadata, %{})),
             body: "",
             service: :queue,
             operation: :create
           ) do
      {:ok,
       %{
         name: name,
         properties: %{
           etag: Operation.header(response, "etag"),
           last_modified: Operation.header(response, "last-modified")
         },
         metadata: Keyword.get(opts, :metadata, %{})
       }}
    end
  end

  @doc """
  Deletes a queue and all of its messages.

  ## Parameters

  * `client` - queue `Storage.Client`
  * `name` - queue name
  * `opts` - accepted for API symmetry; currently unused (default `[]`)

  ## Returns

  * `{:ok, :deleted}`
  * `{:error, %AzureSDK.Error{}}` - for example `QueueNotFound`

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

  ## Parameters

  * `client` - queue `Storage.Client`
  * `name` - queue name
  * `opts` - accepted for API symmetry; currently unused (default `[]`)

  ## Returns

  * `true` / `false` when the service answers or reports not found
  * `{:error, %AzureSDK.Error{}}` for other failures (auth, 5xx, …)

  Match all three; do not treat the return as a plain boolean.

  ## Examples

      case AzureSDK.Storage.Queue.exists?(client, "jobs") do
        true -> :ok
        false -> AzureSDK.Storage.Queue.create(client, "jobs")
        {:error, error} -> {:error, error}
      end
  """
  @spec exists?(Client.t(), String.t(), keyword()) ::
          boolean() | {:error, AzureSDK.Error.t()}
  def exists?(client, name, _opts \\ []) do
    Telemetry.emit_operation(:queue, :exists, %{name: name})

    case get_metadata(client, name, :exists) do
      {:ok, _} -> true
      {:error, %{status: 404}} -> false
      {:error, %{code: "QueueNotFound"}} -> false
      {:error, _} = error -> error
    end
  end

  @doc """
  Returns queue user metadata (keys without the `x-ms-meta-` prefix).

  ## Parameters

  * `client` - queue `Storage.Client`
  * `name` - queue name
  * `opts` - accepted for API symmetry; currently unused (default `[]`)

  ## Returns

  * `{:ok, map()}` - possibly empty
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, %{"env" => "dev"}} = AzureSDK.Storage.Queue.metadata(client, "jobs")
  """
  @spec metadata(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, AzureSDK.Error.t()}
  def metadata(client, name, _opts \\ []) do
    Telemetry.emit_operation(:queue, :metadata, %{name: name})

    with {:ok, response} <- get_metadata(client, name, :metadata) do
      {:ok, Metadata.from_headers(response.headers)}
    end
  end

  @doc """
  Returns the approximate message count and user metadata.

  The count is an estimate: the service may include invisible or soon-to-expire
  messages.

  ## Parameters

  * `client` - queue `Storage.Client`
  * `name` - queue name
  * `opts` - accepted for API symmetry; currently unused (default `[]`)

  ## Returns

  * `{:ok, t:properties/0}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, %{approximate_message_count: 3, metadata: %{}}} =
        AzureSDK.Storage.Queue.properties(client, "jobs")
  """
  @spec properties(Client.t(), String.t(), keyword()) ::
          {:ok, properties()} | {:error, AzureSDK.Error.t()}
  def properties(client, name, _opts \\ []) do
    Telemetry.emit_operation(:queue, :properties, %{name: name})

    with {:ok, response} <- get_metadata(client, name, :properties) do
      count =
        case response
             |> Operation.header("x-ms-approximate-messages-count")
             |> to_string()
             |> Integer.parse() do
          {count, ""} -> count
          _ -> nil
        end

      {:ok,
       %{approximate_message_count: count, metadata: Metadata.from_headers(response.headers)}}
    end
  end

  @doc """
  Sets queue metadata. Replaces all existing metadata keys.

  ## Parameters

  * `client` - queue `Storage.Client`
  * `name` - queue name
  * `metadata` - string-keyed map of user metadata
  * `opts` - accepted for API symmetry; currently unused (default `[]`)

  ## Returns

  * `{:ok, metadata}` - the map you passed
  * `{:error, %AzureSDK.Error{}}`

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

  Follows continuation markers until complete. Accepts the same options as
  `list_page/2`. `:max_results` is the page size, not a total cap; `:marker` is
  managed internally.

  ## Parameters

  * `client` - queue `Storage.Client`
  * `opts` - optional keyword list (default `[]`)

  ## Returns

  * `{:ok, [t:list_item/0]}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, queues} = AzureSDK.Storage.Queue.list(client)

      {:ok, queues} =
        AzureSDK.Storage.Queue.list(client, prefix: "job-", include_metadata: true)
  """
  @spec list(Client.t(), keyword()) :: {:ok, [list_item()]} | {:error, AzureSDK.Error.t()}
  def list(client, opts \\ []) do
    Telemetry.emit_operation(:queue, :list, %{})
    Operation.collect_pages(&list_page(client, Keyword.put(opts, :marker, &1)))
  end

  @doc """
  Lists one page of queues.

  ## Parameters

  * `client` - queue `Storage.Client`
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:marker` - continuation token from a previous page
  * `:max_results` - page size (the service caps it at 5,000)
  * `:prefix` - name prefix filter
  * `:include_metadata` - when `true`, each item's `:metadata` is a map
    (default `false`, which leaves `:metadata` as `nil`)

  ## Returns

  * `{:ok, t:page/0}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, %{items: items, marker: nil}} =
        AzureSDK.Storage.Queue.list_page(client, max_results: 50, prefix: "job-")

      {:ok, %{items: [%{name: "jobs", metadata: meta}], marker: next}} =
        AzureSDK.Storage.Queue.list_page(client, include_metadata: true)
  """
  @spec list_page(Client.t(), keyword()) :: {:ok, page()} | {:error, AzureSDK.Error.t()}
  def list_page(client, opts \\ []) do
    Telemetry.emit_operation(:queue, :list_page, %{})
    include_metadata? = Keyword.get(opts, :include_metadata, false)

    query =
      [{"comp", "list"} | Operation.list_query(opts)]
      |> Operation.maybe_query("include", if(include_metadata?, do: "metadata"))

    with {:ok, response} <-
           Operation.run(client,
             method: :get,
             path: "/",
             query: query,
             service: :queue,
             operation: :list_page
           ) do
      page = ListQueues.parse_page(response.body || "", include_metadata?)
      {:ok, %{items: page.items, marker: page.marker}}
    end
  end

  @doc """
  Lazily streams queues across pages.

  Accepts the same options as `list_page/2`.

  ## Parameters

  * `client` - queue `Storage.Client`
  * `opts` - optional keyword list (default `[]`)

  ## Returns

  An `Enumerable` of `t:list_item/0`. Mid-stream HTTP failures raise
  `AzureSDK.Storage.Queue.StreamError` (they are not returned as `{:error, _}`).

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

  ## Parameters

  * `client` - queue `Storage.Client`
  * `name` - queue name
  * `opts` - accepted for API symmetry; currently unused (default `[]`)

  ## Returns

  * `{:ok, :cleared}`
  * `{:error, %AzureSDK.Error{}}`

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

  defp get_metadata(client, name, operation) do
    Operation.run(client,
      method: :get,
      path: Operation.queue_path(name),
      query: [{"comp", "metadata"}],
      service: :queue,
      operation: operation
    )
  end
end

defmodule AzureSDK.Storage.Queue.StreamError do
  @moduledoc """
  Raised when a mid-stream list page fails inside `Queue.list_stream/2`.

  Ordinary Queue CRUD and message calls return `{:error, %AzureSDK.Error{}}`
  instead of raising.

  ## Fields

  * `:reason` - typically `%AzureSDK.Error{}` from the failed list page

  ## Examples

      iex> Exception.message(%AzureSDK.Storage.Queue.StreamError{reason: :timeout})
      "queue stream failed: :timeout"

      try do
        Enum.to_list(AzureSDK.Storage.Queue.list_stream(client))
      rescue
        e in AzureSDK.Storage.Queue.StreamError ->
          e.reason
      end
  """
  defexception [:reason]

  @impl true
  def message(%{reason: reason}), do: "queue stream failed: #{inspect(reason)}"
end
