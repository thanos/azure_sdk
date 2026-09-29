defmodule AzureSDK.Storage.Container do
  @moduledoc """
  Azure Blob Storage container operations.

  `list/2` and `list_blobs/3` follow Azure pagination markers until all results
  are retrieved.

  ## Container map

      %{
        name: "uploads",
        properties: %{etag: "...", last_modified: "..."},
        metadata: %{"env" => "dev"}
      }

  ## Errors

  Failures return `{:error, %AzureSDK.Error{}}`. Functions do not raise for
  Azure HTTP failures. `exists?/2` is the exception among return shapes: it
  returns a boolean on success or not-found, and `{:error, error}` otherwise.

  ## Examples

      {:ok, container} =
        AzureSDK.Storage.Container.create(client, "uploads",
          metadata: %{"env" => "dev"}
        )

      true = AzureSDK.Storage.Container.exists?(client, "uploads")
      {:ok, containers} = AzureSDK.Storage.Container.list(client)
      {:ok, :deleted} = AzureSDK.Storage.Container.delete(client, "uploads")
  """

  alias AzureSDK.Core.{Pipeline, Request, Telemetry}
  alias AzureSDK.Core.Xml.{ListBlobs, ListContainers}
  alias AzureSDK.Storage.{Client, Metadata, Path}

  @typedoc """
  Container result map.

  * `:name` - container name
  * `:properties` - etag and last modified when known
  * `:metadata` - user metadata
  """
  @type container :: %{
          name: String.t(),
          properties: map(),
          metadata: map()
        }

  @doc """
  Creates a container.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `name` - container name
  * `opts` - optional keyword list:
    * `:public_access` - public access level (for example `:blob` or `:container`)
    * `:metadata` - string-keyed user metadata

  ## Returns

  * `{:ok, container()}`
  * `{:error, %AzureSDK.Error{}}` - including conflict when the container exists

  ## Examples

      {:ok, %{name: "uploads"}} =
        AzureSDK.Storage.Container.create(client, "uploads")
  """
  @spec create(Client.t(), String.t(), keyword()) ::
          {:ok, container()} | {:error, AzureSDK.Error.t()}
  def create(client, name, opts \\ []) do
    Telemetry.emit_operation(:container, :create, %{name: name})

    headers =
      %{"x-ms-version" => client.api_version}
      |> Map.merge(public_access_header(opts))
      |> Map.merge(Metadata.headers(Keyword.get(opts, :metadata, %{})))

    request =
      Request.new(
        method: :put,
        path: Path.join([name]),
        query: [{"restype", "container"}],
        headers: headers,
        body: "",
        service: :blob,
        operation: :create_container,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, container_from_response(name, response, opts)}
    end
  end

  @doc """
  Deletes a container.

  ## Returns

  * `{:ok, :deleted}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, :deleted} = AzureSDK.Storage.Container.delete(client, "uploads")
  """
  @spec delete(Client.t(), String.t(), keyword()) ::
          {:ok, :deleted} | {:error, AzureSDK.Error.t()}
  def delete(client, name, _opts \\ []) do
    Telemetry.emit_operation(:container, :delete, %{name: name})

    request =
      Request.new(
        method: :delete,
        path: Path.join([name]),
        query: [{"restype", "container"}],
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: :delete_container,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, _} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, :deleted}
    end
  end

  @doc """
  Lists containers in the storage account.

  Follows `NextMarker` pagination until all containers are returned.

  ## Returns

  * `{:ok, [container()]}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, containers} = AzureSDK.Storage.Container.list(client)
  """
  @spec list(Client.t(), keyword()) :: {:ok, [container()]} | {:error, AzureSDK.Error.t()}
  def list(client, _opts \\ []) do
    Telemetry.emit_operation(:container, :list, %{})
    list_containers(client, nil, [])
  end

  @doc """
  Lists blobs in a container.

  Follows `NextMarker` pagination until all blobs are returned.

  ## Returns

  * `{:ok, [map()]}` - parsed blob entries from the list XML
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, blobs} = AzureSDK.Storage.Container.list_blobs(client, "uploads")
  """
  @spec list_blobs(Client.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, AzureSDK.Error.t()}
  def list_blobs(client, container, _opts \\ []) do
    Telemetry.emit_operation(:container, :list_blobs, %{container: container})
    list_blobs_page(client, container, nil, [])
  end

  @doc """
  Returns whether the container exists.

  Uses a HEAD request (`Get Container Properties`).

  ## Returns

  * `true` - container exists
  * `false` - Azure reported missing (HTTP 404 / `ContainerNotFound`)
  * `{:error, %AzureSDK.Error{}}` - auth, network, or other failures

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

  ## Returns

  * `{:ok, map()}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, meta} = AzureSDK.Storage.Container.metadata(client, "uploads")
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
    request =
      Request.new(
        method: :head,
        path: Path.join([name]),
        query: [{"restype", "container"}],
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: operation,
        metadata: Client.signing_metadata(client)
      )

    Pipeline.run(Client.to_core_client(client), request)
  end

  defp list_containers(client, marker, acc) do
    request =
      Request.new(
        method: :get,
        path: "/",
        query: [{"comp", "list"} | marker_query(marker)],
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: :list_containers,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request) do
      page = ListContainers.parse_page(response.body || "")
      acc = acc ++ page.items

      if page.marker in [nil, ""] do
        {:ok, acc}
      else
        list_containers(client, page.marker, acc)
      end
    end
  end

  defp list_blobs_page(client, container, marker, acc) do
    request =
      Request.new(
        method: :get,
        path: Path.join([container]),
        query: [{"restype", "container"}, {"comp", "list"} | marker_query(marker)],
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: :list_blobs,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request) do
      page = ListBlobs.parse_page(response.body || "")
      acc = acc ++ page.items

      if page.marker in [nil, ""] do
        {:ok, acc}
      else
        list_blobs_page(client, container, page.marker, acc)
      end
    end
  end

  defp marker_query(nil), do: []
  defp marker_query(marker), do: [{"marker", marker}]

  defp public_access_header(opts) do
    case Keyword.get(opts, :public_access) do
      nil -> %{}
      level -> %{"x-ms-blob-public-access" => to_string(level)}
    end
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
