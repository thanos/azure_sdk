defmodule ExAzure.Storage.Blob do
  @moduledoc """
  Azure Blob Storage operations.

  Supports binary and iodata uploads and downloads. `upload_stream/4` and
  `download_stream/4` accept enumerables but buffer content in memory in v0.1.0;
  chunked streaming is planned for a future release.
  """

  alias ExAzure.Core.{Pipeline, Request, Response, Telemetry}
  alias ExAzure.Storage.{Client, Metadata, Path}

  @type blob :: %{
          container: String.t(),
          name: String.t(),
          properties: map(),
          metadata: map(),
          content: binary() | nil
        }

  @doc """
  Uploads a blob from binary or iodata content.
  """
  @spec upload(Client.t(), String.t(), String.t(), iodata(), keyword()) ::
          {:ok, blob()} | {:error, ExAzure.Error.t()}
  def upload(client, container, name, content, opts \\ []) do
    Telemetry.emit_operation(:blob, :put, %{container: container, name: name})

    content = IO.iodata_to_binary(content)
    headers = upload_headers(opts, byte_size(content))

    request =
      Request.new(
        method: :put,
        path: blob_path(container, name),
        headers: headers,
        body: content,
        service: :blob,
        operation: :put,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, blob_from_response(container, name, response, content, opts)}
    end
  end

  @doc """
  Uploads a blob from an enumerable.

  In v0.1.0 the enumerable is fully materialized in memory before upload.
  """
  @spec upload_stream(Client.t(), String.t(), String.t(), Enumerable.t(), keyword()) ::
          {:ok, blob()} | {:error, ExAzure.Error.t()}
  def upload_stream(client, container, name, stream, opts \\ []) do
    Telemetry.emit_operation(:blob, :put, %{container: container, name: name, buffered: true})

    content = stream |> Enum.into([]) |> IO.iodata_to_binary()
    upload(client, container, name, content, opts)
  end

  @doc """
  Downloads a blob and returns its content.
  """
  @spec download(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, blob()} | {:error, ExAzure.Error.t()}
  def download(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :get, %{container: container, name: name})

    request =
      Request.new(
        method: :get,
        path: blob_path(container, name),
        headers: base_headers(client),
        service: :blob,
        operation: :get,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, blob_from_response(container, name, response, response.body, opts)}
    end
  end

  @doc """
  Downloads a blob as an enumerable.

  In v0.1.0 the full blob is downloaded into memory first, then exposed as a
  single-chunk enumerable. Chunked streaming is planned for a future release.
  """
  @spec download_stream(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, ExAzure.Error.t()}
  def download_stream(client, container, name, opts \\ []) do
    case download(client, container, name, opts) do
      {:ok, %{content: content}} when is_binary(content) ->
        {:ok,
         Stream.unfold(content, fn
           "" -> nil
           bin -> {bin, ""}
         end)}

      other ->
        other
    end
  end

  @doc """
  Deletes a blob.
  """
  @spec delete(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, :deleted} | {:error, ExAzure.Error.t()}
  def delete(client, container, name, _opts \\ []) do
    Telemetry.emit_operation(:blob, :delete, %{container: container, name: name})

    request =
      Request.new(
        method: :delete,
        path: blob_path(container, name),
        headers: base_headers(client),
        service: :blob,
        operation: :delete,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, _} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, :deleted}
    end
  end

  @doc """
  Returns blob metadata.
  """
  @spec metadata(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, ExAzure.Error.t()}
  def metadata(client, container, name, _opts \\ []) do
    Telemetry.emit_operation(:blob, :metadata, %{container: container, name: name})

    request =
      Request.new(
        method: :head,
        path: blob_path(container, name),
        headers: base_headers(client),
        service: :blob,
        operation: :metadata,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, response} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, Metadata.from_headers(response.headers)}
    end
  end

  @doc """
  Sets blob metadata. Replaces all existing metadata keys.

  Returns the metadata that was set.
  """
  @spec set_metadata(Client.t(), String.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, ExAzure.Error.t()}
  def set_metadata(client, container, name, metadata, _opts \\ []) do
    Telemetry.emit_operation(:blob, :set_metadata, %{container: container, name: name})

    headers =
      client
      |> base_headers()
      |> Map.merge(Metadata.headers(metadata))

    request =
      Request.new(
        method: :put,
        path: blob_path(container, name),
        query: [{"comp", "metadata"}],
        headers: headers,
        service: :blob,
        operation: :set_metadata,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, _} <- Pipeline.run(Client.to_core_client(client), request) do
      {:ok, metadata}
    end
  end

  defp blob_path(container, name) do
    Path.join([container | String.split(name, "/", parts: :infinity)])
  end

  defp upload_headers(opts, size) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    %{
      "Content-Type" => content_type,
      "Content-Length" => Integer.to_string(size),
      "x-ms-blob-type" => Keyword.get(opts, :blob_type, "BlockBlob")
    }
    |> Map.merge(Metadata.headers(Keyword.get(opts, :metadata, %{})))
  end

  defp base_headers(client) do
    %{"x-ms-version" => client.api_version}
  end

  defp blob_from_response(container, name, %Response{} = response, content, opts) do
    %{
      container: container,
      name: name,
      properties: %{
        content_type: response_header(response, "content-type"),
        content_length: content_length(response, content),
        etag: response_header(response, "etag"),
        last_modified: response_header(response, "last-modified")
      },
      metadata: Metadata.from_headers(response.headers),
      content: content_value(content, opts)
    }
  end

  defp content_value(content, opts) do
    if Keyword.get(opts, :include_content, true), do: content
  end

  defp response_header(%Response{headers: headers}, name) do
    Map.get(headers, name) || Map.get(headers, String.downcase(name))
  end

  defp content_length(_response, content) when is_binary(content), do: byte_size(content)
  defp content_length(response, _), do: response_header(response, "content-length")
end
