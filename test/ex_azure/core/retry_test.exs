defmodule ExAzure.Core.RetryTest do
  use ExUnit.Case, async: true

  alias ExAzure.Core.{Response, Retry}

  test "retryable status codes" do
    assert Retry.retryable?(%Response{status: 429})
    assert Retry.retryable?(%Response{status: 503})
    refute Retry.retryable?(%Response{status: 404})
  end

  test "exponential backoff delay" do
    policy = Retry.default_policy()
    assert Retry.delay_ms(policy, 1) == 200
    assert Retry.delay_ms(policy, 2) == 400
  end

  test "emits retry telemetry during backoff" do
    ref = make_ref()

    :ok =
      :telemetry.attach(
        ref,
        [:ex_azure, :retry],
        fn event, measurements, metadata, _ ->
          send(self(), {event, measurements, metadata})
        end,
        nil
      )

    Retry.backoff(Retry.default_policy(), 1, %{service: :blob})
    assert_received {[:ex_azure, :retry], %{delay_ms: 200}, %{service: :blob, attempt: 1}}
    :telemetry.detach(ref)
  end
end
