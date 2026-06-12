defmodule ExAzure.Storage.Container do
  @moduledoc """
  Azure Blob Storage container operations.

  `list/2` and `list_blobs/3` automatically follow Azure pagination markers until
  all results are retrieved.
  """

  alias ExAzure.Core.{Pipeline, Request, Telemetry}
  alias ExAzure.Core.Xml.{ListBlobs, ListContainers}
  alias ExAzure.Storage.{Client, Metadata, Path}

  @type container :: %{
          name: String.t(),
          properties: map(),
          metadata: map()
        }

  @doc """
  Creates a container.
  """
  @spec create(Client.t(), String.t(), keyword()) ::
          {:ok, container()} | {:error, ExAzure.Error.t()}
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
  """
  @spec delete(Client.t(), String.t(), keyword()) ::
          {:ok, :deleted} | {:error, ExAzure.Error.t()}
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
  """
  @spec list(Client.t(), keyword()) :: {:ok, [container()]} | {:error, ExAzure.Error.t()}
  def list(client, _opts \\ []) do
    Telemetry.emit_operation(:container, :list, %{})
    list_containers(client, nil, [])
  end

  @doc """
  Lists blobs in a container.

  Follows `NextMarker` pagination until all blobs are returned.
  """
  @spec list_blobs(Client.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, ExAzure.Error.t()}
  def list_blobs(client, container, _opts \\ []) do
    Telemetry.emit_operation(:container, :list_blobs, %{container: container})
    list_blobs_page(client, container, nil, [])
  end

  @doc """
  Returns container metadata.
  """
  @spec metadata(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, ExAzure.Error.t()}
  def metadata(client, name, _opts \\ []) do
    Telemetry.emit_operation(:container, :metadata, %{name: name})

    request =
      Request.new(
        method: :head,
        path: Path.join([name]),
        query: [{"restype", "container"}],
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: :container_metadata,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, Metadata.from_headers(response.headers)}
    end
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
