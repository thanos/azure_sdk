defmodule ExAzure.Core.TelemetryTest do
  use ExUnit.Case, async: true

  alias ExAzure.Core.Telemetry

  test "emits attempt telemetry" do
    ref =
      attach_counter([:ex_azure, :request, :attempt], %{count: 1}, %{
        service: :blob,
        operation: :get
      })

    Telemetry.emit_attempt(%{service: :blob, operation: :get})

    assert_received {[:ex_azure, :request, :attempt], %{count: 1},
                     %{service: :blob, operation: :get}}

    detach(ref)
  end

  test "span emits start and stop events" do
    start_ref = attach_counter([:ex_azure, :request, :start], %{}, %{service: :blob})
    stop_ref = attach_counter([:ex_azure, :request, :stop], %{duration: 0}, %{service: :blob})

    Telemetry.span(%{service: :blob}, fn -> :ok end)

    assert_received {[:ex_azure, :request, :start], %{}, %{service: :blob}}
    assert_received {[:ex_azure, :request, :stop], %{duration: duration}, %{service: :blob}}
    assert is_integer(duration)

    detach(start_ref)
    detach(stop_ref)
  end

  test "emits sign telemetry" do
    ref = attach_counter([:ex_azure, :auth, :sign], %{count: 1}, %{scheme: :shared_key})

    Telemetry.emit_sign(%{scheme: :shared_key})
    assert_received {[:ex_azure, :auth, :sign], %{count: 1}, %{scheme: :shared_key}}
    detach(ref)
  end

  defp attach_counter(event, _measurements, _metadata) do
    ref = make_ref()

    :ok =
      :telemetry.attach(
        ref,
        event,
        fn evt, meas, meta, _ ->
          send(self(), {evt, meas, meta})
        end,
        nil
      )

    ref
  end

  defp detach(ref), do: :telemetry.detach(ref)
end
