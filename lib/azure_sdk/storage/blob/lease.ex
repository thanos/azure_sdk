defmodule AzureSDK.Storage.Blob.Lease do
  @moduledoc """
  Blob lease operations (acquire, renew, change, release, break).

  Lease ids are opaque GUID strings. Pass them back via the `:lease_id` option
  on subsequent lease calls and on Blob write/delete ops.

  All functions return `{:error, %AzureSDK.Error{code: "InvalidArgument"}}`
  instead of raising when a required option is missing.

  ## Retries

  `acquire/4` always sends a proposed lease id (generated when you don't pass
  one), so a retry after a lost response re-acquires the same lease instead of
  failing with 409. `change/4` is never retried, because a retry after a
  successful change would present the old lease id.

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

  alias AzureSDK.Core.Telemetry
  alias AzureSDK.Storage.{Client, Conditions, Operation}

  @doc """
  Acquires a new lease on a blob.

  ## Parameters

  * `client` - `AzureSDK.Storage.Client`
  * `container` - container name
  * `name` - blob name
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:duration` - lease duration in seconds (`15..60`) or `-1` for infinite (default `60`)
  * `:proposed_lease_id` - GUID string; a random GUID is generated when omitted
  * condition opts from `AzureSDK.Storage.Conditions` (`:if_match`, `:if_none_match`,
    `:if_modified_since`, `:if_unmodified_since`)

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

    headers =
      opts
      |> Keyword.delete(:lease_id)
      |> Conditions.headers()
      |> Map.merge(%{
        "x-ms-lease-action" => "acquire",
        "x-ms-lease-duration" => Integer.to_string(Keyword.get(opts, :duration, 60)),
        "x-ms-proposed-lease-id" => Keyword.get_lazy(opts, :proposed_lease_id, &uuid4/0)
      })

    lease_request(client, container, name, headers, :lease_acquire)
  end

  @doc """
  Renews an active lease.

  ## Parameters

  * `client`, `container`, `name` - as in `acquire/4`
  * `opts` - keyword list

  ## Options

  * `:lease_id` (required) - active lease id
  * condition opts from `AzureSDK.Storage.Conditions` (except `:lease_id`, which
    is always the lease being renewed)

  ## Examples

      {:ok, ^lease_id} =
        AzureSDK.Storage.Blob.Lease.renew(client, "uploads", "a.txt", lease_id: lease_id)
  """
  @spec renew(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, AzureSDK.Error.t()}
  def renew(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :lease_renew, %{container: container, name: name})

    with {:ok, %{lease_id: lease_id}} <- Operation.require_opts(opts, [:lease_id], :blob) do
      headers = Map.put(Conditions.headers(opts), "x-ms-lease-action", "renew")

      lease_request(
        client,
        container,
        name,
        Map.put(headers, "x-ms-lease-id", lease_id),
        :lease_renew
      )
    end
  end

  @doc """
  Changes the lease id of an active lease.

  Not retried by the pipeline (see the module docs).

  ## Parameters

  * `client`, `container`, `name` - as in `acquire/4`
  * `opts` - keyword list

  ## Options

  * `:lease_id` (required) - current lease id
  * `:proposed_lease_id` (required) - new lease id
  * other condition opts from `AzureSDK.Storage.Conditions`

  ## Examples

      {:ok, new_id} =
        AzureSDK.Storage.Blob.Lease.change(client, "uploads", "a.txt",
          lease_id: lease_id,
          proposed_lease_id: "7c9e6679-7425-40de-944b-e07fc1f90ae7"
        )
  """
  @spec change(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, AzureSDK.Error.t()}
  def change(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :lease_change, %{container: container, name: name})

    with {:ok, %{lease_id: lease_id, proposed_lease_id: proposed}} <-
           Operation.require_opts(opts, [:lease_id, :proposed_lease_id], :blob) do
      headers =
        opts
        |> Conditions.headers()
        |> Map.merge(%{
          "x-ms-lease-action" => "change",
          "x-ms-lease-id" => lease_id,
          "x-ms-proposed-lease-id" => proposed
        })

      lease_request(client, container, name, headers, :lease_change, idempotent: false)
    end
  end

  @doc """
  Releases an active lease.

  ## Parameters

  * `client`, `container`, `name` - as in `acquire/4`
  * `opts` - keyword list

  ## Options

  * `:lease_id` (required) - active lease id
  * other condition opts from `AzureSDK.Storage.Conditions`

  ## Examples

      {:ok, :released} =
        AzureSDK.Storage.Blob.Lease.release(client, "uploads", "a.txt", lease_id: lease_id)
  """
  @spec release(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, :released} | {:error, AzureSDK.Error.t()}
  def release(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :lease_release, %{container: container, name: name})

    with {:ok, %{lease_id: lease_id}} <- Operation.require_opts(opts, [:lease_id], :blob),
         headers = Map.put(Conditions.headers(opts), "x-ms-lease-action", "release"),
         {:ok, _} <-
           lease_request(
             client,
             container,
             name,
             Map.put(headers, "x-ms-lease-id", lease_id),
             :lease_release
           ) do
      {:ok, :released}
    end
  end

  @doc """
  Breaks an active lease.

  ## Parameters

  * `client`, `container`, `name` - as in `acquire/4`
  * `opts` - optional keyword list (default `[]`)

  ## Options

  * `:break_period` - seconds (`0..60`) before the lease ends
  * condition opts from `AzureSDK.Storage.Conditions`

  ## Examples

      {:ok, :broken} =
        AzureSDK.Storage.Blob.Lease.break(client, "uploads", "a.txt", break_period: 0)
  """
  @spec break(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, :broken} | {:error, AzureSDK.Error.t()}
  def break(client, container, name, opts \\ []) do
    Telemetry.emit_operation(:blob, :lease_break, %{container: container, name: name})

    headers =
      opts
      |> Conditions.headers()
      |> Map.put("x-ms-lease-action", "break")
      |> Operation.put_present("x-ms-lease-break-period", Keyword.get(opts, :break_period))

    with {:ok, _} <- lease_request(client, container, name, headers, :lease_break) do
      {:ok, :broken}
    end
  end

  defp lease_request(client, container, name, headers, operation, metadata \\ []) do
    with {:ok, response} <-
           Operation.run(client,
             method: :put,
             path: Operation.blob_path(container, name),
             query: [{"comp", "lease"}],
             headers: Map.put(headers, "Content-Length", "0"),
             body: "",
             operation: operation,
             metadata: Map.new(metadata)
           ) do
      {:ok,
       Operation.header(response, "x-ms-lease-id") ||
         Map.get(headers, "x-ms-proposed-lease-id") ||
         Map.get(headers, "x-ms-lease-id")}
    end
  end

  # RFC 4122 version 4 UUID.
  defp uuid4 do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)
    <<u0::32, u1::16, u2::16, u3::16, u4::48>> = <<a::48, 4::4, b::12, 2::2, c::62>>

    [<<u0::32>>, <<u1::16>>, <<u2::16>>, <<u3::16>>, <<u4::48>>]
    |> Enum.map_join("-", &Base.encode16(&1, case: :lower))
  end
end
