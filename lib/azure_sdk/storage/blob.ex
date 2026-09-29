defmodule AzureSDK.Storage.Blob do
  @moduledoc """
  Azure Blob Storage operations.

  Binary and iodata uploads/downloads are supported. `upload_stream/4` and
  `download_stream/4` accept enumerables but buffer content in memory in this
  release; chunked streaming is planned later.

  ## Blob map

  Successful upload/download returns a map:

      %{
        container: "uploads",
        name: "file.txt",
        properties: %{
          content_type: "text/plain",
          content_length: 5,
          etag: "...",
          last_modified: "..."
        },
        metadata: %{"owner" => "app"},
        content: "hello"
      }

  ## Errors

  Failures return `{:error, %AzureSDK.Error{}}` (HTTP errors, auth failures,
  transport issues after retries). Functions do not raise for Azure failures.

  ## Examples

      credential =
        AzureSDK.Identity.SharedKeyCredential.new(account, key)

      client =
        AzureSDK.Storage.Client.new(account: account, credential: credential)

      {:ok, blob} =
        AzureSDK.Storage.Blob.upload(client, "uploads", "file.txt", "hello",
          content_type: "text/plain",
          metadata: %{"owner" => "app"}
        )

      {:ok, %{content: "hello"}} =
        AzureSDK.Storage.Blob.download(client, "uploads", "file.txt")
  """

  alias AzureSDK.Core.{Pipeline, Request, Response, Telemetry}
  alias AzureSDK.Storage.{Client, Metadata, Path}

  @typedoc """
  Blob result map.

  * `:container` — container name
  * `:name` — blob name (may include `/` path segments)
  * `:properties` — content type, length, etag, last modified
  * `:metadata` — user metadata (without the `x-ms-meta-` prefix)
  * `:content` — body bytes when included, otherwise `nil`
  """
  @type blob :: %{
          container: String.t(),
          name: String.t(),
          properties: map(),
          metadata: map(),
          content: binary() | nil
        }

  @doc """
  Uploads a blob from binary or iodata content.

  ## Parameters

  * `client` — `AzureSDK.Storage.Client`
  * `container` — container name
  * `name` — blob name (path segments allowed)
  * `content` — binary or iodata
  * `opts` — optional keyword list:
    * `:content_type` — defaults to `"application/octet-stream"`
    * `:blob_type` — defaults to `"BlockBlob"`
    * `:metadata` — string-keyed user metadata map
    * `:include_content` — when `false`, returned `:content` is `nil` (default `true`)

  ## Returns

  * `{:ok, blob()}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, blob} =
        AzureSDK.Storage.Blob.upload(client, "uploads", "a.txt", "hi",
          content_type: "text/plain"
        )
  """
  @spec upload(Client.t(), String.t(), String.t(), iodata(), keyword()) ::
          {:ok, blob()} | {:error, AzureSDK.Error.t()}
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

  The enumerable is fully materialized in memory before upload.

  ## Parameters

  Same as `upload/5`, with `stream` an `Enumerable` of iodata chunks.

  ## Returns

  * `{:ok, blob()}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, _} =
        AzureSDK.Storage.Blob.upload_stream(client, "uploads", "a.txt", ["hel", "lo"])
  """
  @spec upload_stream(Client.t(), String.t(), String.t(), Enumerable.t(), keyword()) ::
          {:ok, blob()} | {:error, AzureSDK.Error.t()}
  def upload_stream(client, container, name, stream, opts \\ []) do
    Telemetry.emit_operation(:blob, :put, %{container: container, name: name, buffered: true})

    content = stream |> Enum.into([]) |> IO.iodata_to_binary()
    upload(client, container, name, content, opts)
  end

  @doc """
  Downloads a blob and returns its content.

  ## Parameters

  * `client` — storage client
  * `container` — container name
  * `name` — blob name
  * `opts` — optional:
    * `:include_content` — when `false`, `:content` is `nil` (default `true`)

  ## Returns

  * `{:ok, blob()}`
  * `{:error, %AzureSDK.Error{}}` — including 404 when the blob is missing

  ## Examples

      {:ok, %{content: body}} =
        AzureSDK.Storage.Blob.download(client, "uploads", "a.txt")
  """
  @spec download(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, blob()} | {:error, AzureSDK.Error.t()}
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

  The full blob is downloaded into memory first, then exposed as a single-chunk
  enumerable.

  ## Returns

  * `{:ok, Enumerable.t()}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, stream} = AzureSDK.Storage.Blob.download_stream(client, "uploads", "a.txt")
      IO.iodata_to_binary(Enum.to_list(stream))
  """
  @spec download_stream(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, AzureSDK.Error.t()}
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

  ## Returns

  * `{:ok, :deleted}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, :deleted} = AzureSDK.Storage.Blob.delete(client, "uploads", "a.txt")
  """
  @spec delete(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, :deleted} | {:error, AzureSDK.Error.t()}
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
  Returns blob user metadata (keys without the `x-ms-meta-` prefix).

  ## Returns

  * `{:ok, map()}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, meta} = AzureSDK.Storage.Blob.metadata(client, "uploads", "a.txt")
  """
  @spec metadata(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, AzureSDK.Error.t()}
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

  ## Parameters

  * `metadata` — string-keyed map of user metadata values

  ## Returns

  * `{:ok, map()}` — the metadata that was written
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, %{"owner" => "app"}} =
        AzureSDK.Storage.Blob.set_metadata(client, "uploads", "a.txt", %{"owner" => "app"})
  """
  @spec set_metadata(Client.t(), String.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, AzureSDK.Error.t()}
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
