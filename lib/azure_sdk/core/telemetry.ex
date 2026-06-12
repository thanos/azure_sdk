defmodule AzureSDK.Core.Telemetry do
  @moduledoc """
  Telemetry helpers for AzureSDK operations.

  ## Events

  * `[:azure_sdk, :request, :start]` — pipeline span started
  * `[:azure_sdk, :request, :stop]` — pipeline span finished with duration
  * `[:azure_sdk, :request, :attempt]` — emitted before each HTTP attempt
  * `[:azure_sdk, :auth, :sign]` — emitted when a request is signed
  * `[:azure_sdk, :retry]` — emitted on retry backoff
  * `[:azure_sdk, :blob, :put | :get | :delete | ...]` — service operations

  Attach a handler:

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
  Wraps a function with request duration telemetry.
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
