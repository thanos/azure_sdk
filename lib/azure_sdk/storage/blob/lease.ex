defmodule AzureSDK.Storage.Blob.Lease do
  @moduledoc """
  Blob lease operations (acquire, renew, change, release, break).

  Lease ids are opaque GUID strings returned by Azure. Pass them back via the
  `:lease_id` option on subsequent lease calls and on Blob write/delete ops.

  ## Examples

      {:ok, lease_id} =
        AzureSDK.Storage.Blob.Lease.acquire(client, "uploads", "a.txt",
          duration: 60,
          proposed_lease_id: "550e8400-e29b-41d4-a716-446655440000"
        )

      {:ok, lease_id} =
        AzureSDK.Storage.Blob.Lease.renew(client, "uploads", "a.txt", lease_id: lease_id)

      {:ok, :released} =
        AzureSDK.Storage.Blob.Lease.release(client, "uploads", "a.txt", lease_id: lease_id)
  """

  alias AzureSDK.Core.{Pipeline, Request, Response, Telemetry}
  alias AzureSDK.Storage.{Client, Conditions, Path}

  @doc """
  Acquires a new lease on a blob.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `container` - container name
  * `name` - blob name
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:duration` - lease duration in seconds (`15..60`) or `-1` for infinite (default `60`)
  * `:proposed_lease_id` - optional GUID string
  * condition opts from `AzureSDK.Storage.Conditions` (`:if_match`, `:if_none_match`,
    `:if_modified_since`, `:if_unmodified_since`)

  ## Returns

  * `{:ok, lease_id}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, lease_id} = AzureSDK.Storage.Blob.Lease.acquire(client, "uploads", "a.txt")

      {:ok, lease_id} =
        AzureSDK.Storage.Blob.Lease.acquire(client, "uploads", "a.txt",
          duration: -1,
          proposed_lease_id: "550e8400-e29b-41d4-a716-446655440000",
          if_match: etag
        )
  """
  @spec acquire(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, AzureSDK.Error.t()}
  def acquire(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :lease_acquire, %{container: container, name: name})

    duration = Keyword.get(opts, :duration, 60)

    headers =
      %{
        "x-ms-version" => client.api_version,
        "x-ms-lease-action" => "acquire",
        "x-ms-lease-duration" => Integer.to_string(duration),
        "Content-Length" => "0"
      }
      |> maybe_put("x-ms-proposed-lease-id", Keyword.get(opts, :proposed_lease_id))
      |> Map.merge(Conditions.headers(opts))

    lease_request(client, container, name, headers, :lease_acquire)
  end

  @doc """
  Renews an existing lease.

  ## Parameters

  * `client`, `container`, `name` - as in `acquire/4`
  * `opts` - keyword list

  ## Options

  * `:lease_id` (required) - current lease id
  * other condition opts from `AzureSDK.Storage.Conditions` (except `:lease_id` is the lease itself)

  ## Returns

  * `{:ok, lease_id}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, lease_id} =
        AzureSDK.Storage.Blob.Lease.renew(client, "uploads", "a.txt", lease_id: lease_id)
  """
  @spec renew(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, AzureSDK.Error.t()}
  def renew(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :lease_renew, %{container: container, name: name})
    lease_id = Keyword.fetch!(opts, :lease_id)

    headers =
      %{
        "x-ms-version" => client.api_version,
        "x-ms-lease-action" => "renew",
        "x-ms-lease-id" => lease_id,
        "Content-Length" => "0"
      }
      |> Map.merge(Conditions.headers(Keyword.delete(opts, :lease_id)))
      |> Map.put("x-ms-lease-id", lease_id)

    lease_request(client, container, name, headers, :lease_renew)
  end

  @doc """
  Changes the lease id.

  ## Parameters

  * `client`, `container`, `name` - as in `acquire/4`
  * `opts` - keyword list

  ## Options

  * `:lease_id` (required) - current lease
  * `:proposed_lease_id` (required) - new lease id
  * condition opts from `AzureSDK.Storage.Conditions`

  ## Returns

  * `{:ok, new_lease_id}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, new_id} =
        AzureSDK.Storage.Blob.Lease.change(client, "uploads", "a.txt",
          lease_id: lease_id,
          proposed_lease_id: "550e8400-e29b-41d4-a716-446655440001"
        )
  """
  @spec change(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, AzureSDK.Error.t()}
  def change(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :lease_change, %{container: container, name: name})
    lease_id = Keyword.fetch!(opts, :lease_id)
    proposed = Keyword.fetch!(opts, :proposed_lease_id)

    headers =
      %{
        "x-ms-version" => client.api_version,
        "x-ms-lease-action" => "change",
        "x-ms-lease-id" => lease_id,
        "x-ms-proposed-lease-id" => proposed,
        "Content-Length" => "0"
      }
      |> Map.merge(Conditions.headers(opts))

    lease_request(client, container, name, headers, :lease_change)
  end

  @doc """
  Releases a lease.

  ## Parameters

  * `client`, `container`, `name` - as in `acquire/4`
  * `opts` - keyword list

  ## Options

  * `:lease_id` (required)
  * condition opts from `AzureSDK.Storage.Conditions`

  ## Returns

  * `{:ok, :released}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, :released} =
        AzureSDK.Storage.Blob.Lease.release(client, "uploads", "a.txt", lease_id: lease_id)
  """
  @spec release(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, :released} | {:error, AzureSDK.Error.t()}
  def release(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :lease_release, %{container: container, name: name})
    lease_id = Keyword.fetch!(opts, :lease_id)

    headers =
      %{
        "x-ms-version" => client.api_version,
        "x-ms-lease-action" => "release",
        "x-ms-lease-id" => lease_id,
        "Content-Length" => "0"
      }
      |> Map.merge(Conditions.headers(Keyword.delete(opts, :lease_id)))
      |> Map.put("x-ms-lease-id", lease_id)

    case lease_request(client, container, name, headers, :lease_release) do
      {:ok, _} -> {:ok, :released}
      error -> error
    end
  end

  @doc """
  Breaks a lease.

  ## Parameters

  * `client`, `container`, `name` - as in `acquire/4`
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:break_period` - optional seconds before the lease breaks
  * condition opts from `AzureSDK.Storage.Conditions`

  ## Returns

  * `{:ok, :broken}`
  * `{:error, %AzureSDK.Error{}}`

  ## Examples

      {:ok, :broken} = AzureSDK.Storage.Blob.Lease.break(client, "uploads", "a.txt")

      {:ok, :broken} =
        AzureSDK.Storage.Blob.Lease.break(client, "uploads", "a.txt", break_period: 15)
  """
  @spec break(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, :broken} | {:error, AzureSDK.Error.t()}
  def break(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :lease_break, %{container: container, name: name})

    headers =
      %{
        "x-ms-version" => client.api_version,
        "x-ms-lease-action" => "break",
        "Content-Length" => "0"
      }
      |> maybe_put("x-ms-lease-break-period", Keyword.get(opts, :break_period))
      |> Map.merge(Conditions.headers(opts))

    case lease_request(client, container, name, headers, :lease_break) do
      {:ok, _} -> {:ok, :broken}
      error -> error
    end
  end

  defp lease_request(client, container, name, headers, operation) do
    request =
      Request.new(
        method: :put,
        path: blob_path(container, name),
        query: [{"comp", "lease"}],
        headers: headers,
        body: "",
        service: :blob,
        operation: operation,
        metadata: Client.signing_metadata(client)
      )

    with {:ok, %Response{} = response} <- Pipeline.run(Client.to_core_client(client), request) do
      lease_id =
        response_header(response, "x-ms-lease-id") ||
          Map.get(headers, "x-ms-proposed-lease-id") ||
          Map.get(headers, "x-ms-lease-id")

      {:ok, lease_id}
    end
  end

  defp blob_path(container, name) do
    Path.join([container | String.split(name, "/", parts: :infinity)])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, to_string(value))

  defp response_header(%Response{headers: headers}, name) do
    Map.get(headers, name) || Map.get(headers, String.downcase(name))
  end
end
