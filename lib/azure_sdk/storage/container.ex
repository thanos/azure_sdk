defmodule AzureSDK.Storage.Container do
  @moduledoc """
  Azure Blob Storage container operations.

  Eager helpers (`list/2`, `list_blobs/3`) follow pagination until complete.
  Page and stream APIs expose markers for lazy consumption.

  ## Container map (`t:container/0`)

      %{
        name: "uploads",
        properties: %{etag: "\\"0x8D…\\"", last_modified: "Wed, 01 Jan 2025 00:00:00 GMT"},
        metadata: %{"env" => "dev"}
      }

  ## List page (`t:page/0`)

      %{items: [%{name: "uploads", ...}], marker: nil}
      %{items: [%{name: "a.txt", ...}], marker: "continuation-token"}
  """

  alias AzureSDK.Core.Telemetry
  alias AzureSDK.Core.Xml.{ListBlobs, ListContainers}
  alias AzureSDK.Storage.{Client, Metadata, Operation, Path}

  @typedoc """
  Container result map.

  * `:name` - container name
  * `:properties` - typically `etag` and `last_modified`
  * `:metadata` - user metadata without the `x-ms-meta-` prefix
  """
  @type container :: %{
          name: String.t(),
          properties: map(),
          metadata: map()
        }

  @typedoc """
  A single list page with continuation marker.

  * `:items` - containers or blob maps for this page
  * `:marker` - opaque continuation token, or `nil` when finished
  """
  @type page :: %{items: [map()], marker: String.t() | nil}

  @doc """
  Creates a container.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `name` - container name
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:public_access` - `:blob` or `:container`
  * `:metadata` - string-keyed user metadata

  ## Examples

      {:ok, container} = AzureSDK.Storage.Container.create(client, "uploads")

      {:ok, container} =
        AzureSDK.Storage.Container.create(client, "public",
          public_access: :blob,
          metadata: %{"env" => "dev"}
        )
  """
  @spec create(Client.t(), String.t(), keyword()) ::
          {:ok, container()} | {:error, AzureSDK.Error.t()}
  def create(client, name, opts \\ []) do
    Telemetry.emit_operation(:container, :create, %{name: name})

    headers =
      %{}
      |> Operation.put_present("x-ms-blob-public-access", Keyword.get(opts, :public_access))
      |> Map.merge(Metadata.headers(Keyword.get(opts, :metadata, %{})))

    with {:ok, response} <-
           Operation.run(client,
             method: :put,
             path: Path.join([name]),
             query: [{"restype", "container"}],
             headers: headers,
             body: "",
             operation: :create_container
           ) do
      {:ok, container_from_response(name, response, opts)}
    end
  end

  @doc """
  Deletes a container.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `name` - container name
  * `opts` - accepted for API symmetry; currently unused (default `[]`)

  ## Examples

      {:ok, :deleted} = AzureSDK.Storage.Container.delete(client, "uploads")
  """
  @spec delete(Client.t(), String.t(), keyword()) ::
          {:ok, :deleted} | {:error, AzureSDK.Error.t()}
  def delete(client, name, _opts \\ []) do
    Telemetry.emit_operation(:container, :delete, %{name: name})

    with {:ok, _} <-
           Operation.run(client,
             method: :delete,
             path: Path.join([name]),
             query: [{"restype", "container"}],
             operation: :delete_container
           ) do
      {:ok, :deleted}
    end
  end

  @doc """
  Lists all containers (eager).

  Follows continuation markers until complete. Accepts the same options as
  `list_page/2`. `:max_results` is the page size, not a limit on the total;
  `:marker` is managed internally.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `opts` - optional keyword list (default `[]`)

  ## Examples

      {:ok, containers} = AzureSDK.Storage.Container.list(client)

      {:ok, containers} =
        AzureSDK.Storage.Container.list(client, prefix: "prod-", max_results: 100)
  """
  @spec list(Client.t(), keyword()) :: {:ok, [container()]} | {:error, AzureSDK.Error.t()}
  def list(client, opts \\ []) do
    Telemetry.emit_operation(:container, :list, %{})
    Operation.collect_pages(&list_page(client, Keyword.put(opts, :marker, &1)))
  end

  @doc """
  Lists one page of containers.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:marker` - continuation token from a previous page
  * `:max_results` - page size (the service caps it at 5,000)
  * `:prefix` - name prefix filter

  ## Examples

      {:ok, %{items: items, marker: nil}} =
        AzureSDK.Storage.Container.list_page(client, max_results: 50, prefix: "app-")

      {:ok, %{items: more, marker: next}} =
        AzureSDK.Storage.Container.list_page(client, marker: marker, max_results: 50)
  """
  @spec list_page(Client.t(), keyword()) :: {:ok, page()} | {:error, AzureSDK.Error.t()}
  def list_page(client, opts \\ []) do
    Telemetry.emit_operation(:container, :list_page, %{})

    with {:ok, response} <-
           Operation.run(client,
             method: :get,
             path: "/",
             query: [{"comp", "list"} | Operation.list_query(opts)],
             operation: :list_containers
           ) do
      page = ListContainers.parse_page(response.body || "")
      {:ok, %{items: page.items, marker: Operation.blank_to_nil(page.marker)}}
    end
  end

  @doc """
  Lazily streams containers across pages.

  Accepts the same options as `list_page/2`. Mid-stream failures raise
  `AzureSDK.Storage.Container.StreamError`.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `opts` - optional keyword list (default `[]`)

  ## Examples

      names =
        client
        |> AzureSDK.Storage.Container.list_stream(prefix: "app-")
        |> Enum.map(& &1.name)
  """
  @spec list_stream(Client.t(), keyword()) :: Enumerable.t()
  def list_stream(client, opts \\ []) do
    Operation.page_stream(
      &list_page(client, Keyword.put(opts, :marker, &1)),
      AzureSDK.Storage.Container.StreamError
    )
  end

  @doc """
  Lists all blobs in a container (eager).

  Accepts the same options as `list_blobs_page/3`. `:max_results` is the page
  size, not a limit on the total; `:marker` is managed internally.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `container` - container name
  * `opts` - optional keyword list (default `[]`)

  ## Examples

      {:ok, blobs} = AzureSDK.Storage.Container.list_blobs(client, "uploads")

      {:ok, blobs} =
        AzureSDK.Storage.Container.list_blobs(client, "uploads",
          prefix: "logs/",
          max_results: 200
        )
  """
  @spec list_blobs(Client.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, AzureSDK.Error.t()}
  def list_blobs(client, container, opts \\ []) do
    Telemetry.emit_operation(:container, :list_blobs, %{container: container})

    Operation.collect_pages(&list_blobs_page(client, container, Keyword.put(opts, :marker, &1)))
  end

  @doc """
  Lists one page of blobs in a container.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `container` - container name
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:marker` - continuation token
  * `:max_results` - page size (the service caps it at 5,000)
  * `:prefix` - blob name prefix filter

  ## Examples

      {:ok, %{items: blobs, marker: marker}} =
        AzureSDK.Storage.Container.list_blobs_page(client, "uploads",
          prefix: "2025/",
          max_results: 100
        )
  """
  @spec list_blobs_page(Client.t(), String.t(), keyword()) ::
          {:ok, page()} | {:error, AzureSDK.Error.t()}
  def list_blobs_page(client, container, opts \\ []) do
    Telemetry.emit_operation(:container, :list_blobs_page, %{container: container})

    with {:ok, response} <-
           Operation.run(client,
             method: :get,
             path: Path.join([container]),
             query: [{"restype", "container"}, {"comp", "list"} | Operation.list_query(opts)],
             operation: :list_blobs
           ) do
      page = ListBlobs.parse_page(response.body || "")
      {:ok, %{items: page.items, marker: Operation.blank_to_nil(page.marker)}}
    end
  end

  @doc """
  Lazily streams blobs across pages.

  Accepts the same options as `list_blobs_page/3`. Mid-stream failures raise
  `AzureSDK.Storage.Container.StreamError`.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `container` - container name
  * `opts` - optional keyword list (default `[]`)

  ## Examples

      names =
        client
        |> AzureSDK.Storage.Container.list_blobs_stream("uploads", prefix: "logs/")
        |> Enum.map(& &1.name)
  """
  @spec list_blobs_stream(Client.t(), String.t(), keyword()) :: Enumerable.t()
  def list_blobs_stream(client, container, opts \\ []) do
    Operation.page_stream(
      &list_blobs_page(client, container, Keyword.put(opts, :marker, &1)),
      AzureSDK.Storage.Container.StreamError
    )
  end

  @doc """
  Returns whether the container exists.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `name` - container name
  * `opts` - accepted for API symmetry; currently unused (default `[]`)

  ## Returns

  * `true` / `false` when the HEAD succeeds or reports not found
  * `{:error, %AzureSDK.Error{}}` for other failures

  ## Examples

      true = AzureSDK.Storage.Container.exists?(client, "uploads")
      false = AzureSDK.Storage.Container.exists?(client, "missing")
  """
  @spec exists?(Client.t(), String.t(), keyword()) ::
          boolean() | {:error, AzureSDK.Error.t()}
  def exists?(client, name, _opts \\ []) do
    Telemetry.emit_operation(:container, :exists, %{name: name})

    case head_container(client, name, :container_exists) do
      {:ok, _} -> true
      {:error, %{status: 404}} -> false
      {:error, %{code: "ContainerNotFound"}} -> false
      {:error, _} = error -> error
    end
  end

  @doc """
  Returns container user metadata.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `name` - container name
  * `opts` - accepted for API symmetry; currently unused (default `[]`)

  ## Examples

      {:ok, %{"env" => "dev"}} = AzureSDK.Storage.Container.metadata(client, "uploads")
  """
  @spec metadata(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, AzureSDK.Error.t()}
  def metadata(client, name, _opts \\ []) do
    Telemetry.emit_operation(:container, :metadata, %{name: name})

    with {:ok, response} <- head_container(client, name, :container_metadata) do
      {:ok, Metadata.from_headers(response.headers)}
    end
  end

  defp head_container(client, name, operation) do
    Operation.run(client,
      method: :head,
      path: Path.join([name]),
      query: [{"restype", "container"}],
      operation: operation
    )
  end

  defp container_from_response(name, response, opts) do
    %{
      name: name,
      properties: %{
        etag: Map.get(response.headers, "etag"),
        last_modified: Map.get(response.headers, "last-modified")
      },
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end

defmodule AzureSDK.Storage.Container.StreamError do
  @moduledoc """
  Raised when a mid-stream list page fails inside `list_stream/2` or
  `list_blobs_stream/3`.

  ## Fields

  * `:reason` - typically `%AzureSDK.Error{}` from a failed list page

  ## Examples

      try do
        Enum.to_list(AzureSDK.Storage.Container.list_stream(client))
      rescue
        e in AzureSDK.Storage.Container.StreamError ->
          e.reason
      end
  """
  defexception [:reason]

  @impl true
  def message(%{reason: reason}), do: "container stream failed: #{inspect(reason)}"
end
