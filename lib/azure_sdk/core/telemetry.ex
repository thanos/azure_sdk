defmodule AzureSDK.Core.Telemetry do
  @moduledoc """
  Telemetry helpers for AzureSDK operations.

  ## Events

  * `[:azure_sdk, :request, :start]` — pipeline span started
  * `[:azure_sdk, :request, :stop]` — pipeline span finished with duration
  * `[:azure_sdk, :request, :attempt]` — emitted before each HTTP attempt
  * `[:azure_sdk, :auth, :sign]` — emitted when a request is signed
  * `[:azure_sdk, :auth, :token_cache, :hit | :miss]` — token cache lookups
  * `[:azure_sdk, :auth, :token, :acquire]` — token acquisition duration
  * `[:azure_sdk, :retry]` — emitted on retry backoff
  * `[:azure_sdk, :blob, :put | :get | :delete | ...]` — service operations

  ## Attach example

      :telemetry.attach(
        "ex-azure-logger",
        [:azure_sdk, :request, :stop],
        fn _event, measurements, metadata, _config ->
          IO.inspect({measurements, metadata}, label: "azure_sdk request")
        end,
        nil
      )
  """

  @doc """
  Emits a per-attempt request telemetry event.

  ## Parameters

  * `metadata` — map with at least `:service`, `:operation`, `:method`, `:path`

  ## Returns

  `:ok`

  ## Examples

      iex> AzureSDK.Core.Telemetry.emit_attempt(%{service: :blob, operation: :get})
      :ok
  """
  @spec emit_attempt(map()) :: :ok
  def emit_attempt(metadata) do
    :telemetry.execute(
      [:azure_sdk, :request, :attempt],
      %{count: 1},
      metadata
    )
  end

  @doc """
  Emits an operation telemetry event for a service module.

  ## Parameters

  * `service` — service atom (for example `:blob` or `:container`)
  * `operation` — operation atom (for example `:put`)
  * `metadata` — additional metadata map

  ## Returns

  `:ok`

  ## Examples

      iex> AzureSDK.Core.Telemetry.emit_operation(:blob, :put, %{container: "c", name: "b"})
      :ok
  """
  @spec emit_operation(atom(), atom(), map()) :: :ok
  def emit_operation(service, operation, metadata) do
    :telemetry.execute(
      [:azure_sdk, service, operation],
      %{count: 1},
      metadata
    )
  end

  @doc """
  Emits a signing telemetry event.

  ## Parameters

  * `metadata` — typically includes `:scheme`, `:service`, `:operation`

  ## Returns

  `:ok`

  ## Examples

      iex> AzureSDK.Core.Telemetry.emit_sign(%{scheme: :shared_key, service: :blob})
      :ok
  """
  @spec emit_sign(map()) :: :ok
  def emit_sign(metadata) do
    :telemetry.execute(
      [:azure_sdk, :auth, :sign],
      %{count: 1},
      metadata
    )
  end

  @doc """
  Emits a token-cache hit or miss event.

  ## Parameters

  * `kind` — `:hit` or `:miss`
  * `metadata` — additional metadata

  ## Returns

  `:ok`

  ## Examples

      iex> AzureSDK.Core.Telemetry.emit_token_cache(:hit, %{cache_key_type: :client_secret})
      :ok
  """
  @spec emit_token_cache(:hit | :miss, map()) :: :ok
  def emit_token_cache(kind, metadata) when kind in [:hit, :miss] do
    :telemetry.execute(
      [:azure_sdk, :auth, :token_cache, kind],
      %{count: 1},
      metadata
    )
  end

  @doc """
  Wraps a function with request duration telemetry.

  Emits `:start` before invoking `fun`, then `:stop` with `:duration` in an
  `after` block (including when `fun` raises).

  ## Parameters

  * `metadata` — request metadata map
  * `fun` — zero-arity function

  ## Returns

  The return value of `fun`. Re-raises if `fun` raises.

  ## Examples

      iex> AzureSDK.Core.Telemetry.span(%{service: :blob}, fn -> :done end)
      :done
  """
  @spec span(map(), (-> term())) :: term()
  def span(metadata, fun) do
    start = System.monotonic_time()

    :telemetry.execute([:azure_sdk, :request, :start], %{}, metadata)

    try do
      fun.()
    after
      duration = System.monotonic_time() - start

      :telemetry.execute(
        [:azure_sdk, :request, :stop],
        %{duration: duration},
        metadata
      )
    end
  end
end
