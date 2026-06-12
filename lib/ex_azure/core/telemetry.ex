defmodule ExAzure.Core.Telemetry do
  @moduledoc """
  Telemetry helpers for ExAzure operations.

  ## Events

  * `[:ex_azure, :request, :start]` — pipeline span started
  * `[:ex_azure, :request, :stop]` — pipeline span finished with duration
  * `[:ex_azure, :request, :attempt]` — emitted before each HTTP attempt
  * `[:ex_azure, :auth, :sign]` — emitted when a request is signed
  * `[:ex_azure, :retry]` — emitted on retry backoff
  * `[:ex_azure, :blob, :put | :get | :delete | ...]` — service operations

  Attach a handler:

      :telemetry.attach(
        "ex-azure-logger",
        [:ex_azure, :request, :stop],
        fn _event, measurements, metadata, _config ->
          IO.inspect({measurements, metadata}, label: "ex_azure request")
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
      [:ex_azure, :request, :attempt],
      %{count: 1},
      metadata
    )
  end

  @doc false
  @spec emit_request(map()) :: :ok
  def emit_request(metadata), do: emit_attempt(metadata)

  @doc """
  Emits an operation telemetry event for a service module.
  """
  @spec emit_operation(atom(), atom(), map()) :: :ok
  def emit_operation(service, operation, metadata) do
    :telemetry.execute(
      [:ex_azure, service, operation],
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
      [:ex_azure, :auth, :sign],
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

    :telemetry.execute([:ex_azure, :request, :start], %{}, metadata)

    try do
      fun.()
    after
      duration = System.monotonic_time() - start

      :telemetry.execute(
        [:ex_azure, :request, :stop],
        %{duration: duration},
        metadata
      )
    end
  end
end
