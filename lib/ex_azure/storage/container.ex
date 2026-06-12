defmodule ExAzure.Storage.Container do
  @moduledoc """
  Azure Blob Storage container operations.
  """

  alias ExAzure.Core.{Pipeline, Request, Telemetry}
  alias ExAzure.Core.Xml.{ListBlobs, ListContainers}
  alias ExAzure.Storage.Client

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
      |> Map.merge(metadata_headers(Keyword.get(opts, :metadata, %{})))

    request =
      Request.new(
        method: :put,
        path: "/#{URI.encode(name)}",
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
  def delete(client, name, opts \\ []) do
    Telemetry.emit_operation(:container, :delete, %{name: name})

    request =
      Request.new(
        method: :delete,
        path: "/#{URI.encode(name)}",
        query: [{"restype", "container"}],
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: :delete_container,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, _} <- Pipeline.run(Client.to_core_client(client), request, opts) do
      {:ok, :deleted}
    end
  end

  @doc """
  Lists containers in the storage account.
  """
  @spec list(Client.t(), keyword()) :: {:ok, [container()]} | {:error, ExAzure.Error.t()}
  def list(client, opts \\ []) do
    Telemetry.emit_operation(:container, :list, %{})

    query = [{"comp", "list"}]

    request =
      Request.new(
        method: :get,
        path: "/",
        query: query,
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: :list_containers,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request, opts) do
      {:ok, ListContainers.parse(response.body || "")}
    end
  end

  @doc """
  Lists blobs in a container.
  """
  @spec list_blobs(Client.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, ExAzure.Error.t()}
  def list_blobs(client, container, opts \\ []) do
    Telemetry.emit_operation(:container, :list_blobs, %{container: container})

    request =
      Request.new(
        method: :get,
        path: "/#{URI.encode(container)}",
        query: [{"restype", "container"}, {"comp", "list"}],
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: :list_blobs,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request, opts) do
      {:ok, ListBlobs.parse(response.body || "")}
    end
  end

  @doc """
  Returns container metadata.
  """
  @spec metadata(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, ExAzure.Error.t()}
  def metadata(client, name, opts \\ []) do
    Telemetry.emit_operation(:container, :metadata, %{name: name})

    request =
      Request.new(
        method: :head,
        path: "/#{URI.encode(name)}",
        query: [{"restype", "container"}],
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: :container_metadata,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request, opts) do
      {:ok, metadata_from_headers(response.headers)}
    end
  end

  defp public_access_header(opts) do
    case Keyword.get(opts, :public_access) do
      nil -> %{}
      level -> %{"x-ms-blob-public-access" => to_string(level)}
    end
  end

  defp metadata_headers(metadata) do
    metadata
    |> Enum.map(fn {k, v} -> {"x-ms-meta-#{k}", to_string(v)} end)
    |> Map.new()
  end

  defp metadata_from_headers(headers) do
    headers
    |> Enum.filter(fn {k, _} -> String.starts_with?(String.downcase(k), "x-ms-meta-") end)
    |> Map.new(fn {k, v} ->
      key = k |> String.downcase() |> String.replace_prefix("x-ms-meta-", "")
      {key, v}
    end)
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
