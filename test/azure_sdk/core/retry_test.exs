defmodule AzureSDK.Core.RetryTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Core.{Request, Response, Retry}
  alias AzureSDK.Error

  test "retryable status codes" do
    assert Retry.retryable?(%Response{status: 429})
    assert Retry.retryable?(%Response{status: 503})
    refute Retry.retryable?(%Response{status: 404})
  end

  test "exponential backoff delay without jitter" do
    policy = %{Retry.default_policy() | jitter: false}
    assert Retry.delay_ms(policy, 1) == 200
    assert Retry.delay_ms(policy, 2) == 400
  end

  test "honors Retry-After seconds header" do
    policy = %{Retry.default_policy() | jitter: false}
    response = %Response{status: 429, headers: %{"retry-after" => "2"}}
    assert Retry.delay_ms(policy, 1, response) == 2000
  end

  test "honors x-ms-retry-after-ms header" do
    policy = %{Retry.default_policy() | jitter: false}
    response = %Response{status: 503, headers: %{"x-ms-retry-after-ms" => "1500"}}
    assert Retry.delay_ms(policy, 1, response) == 1500
  end

  test "transport retries respect idempotent metadata" do
    error = Error.new(message: "timeout", service: :blob)
    idempotent = Request.new(method: :post, path: "/", metadata: %{idempotent: true})
    non_idempotent = Request.new(method: :post, path: "/", metadata: %{idempotent: false})

    assert Retry.retry_transport?(idempotent, error)
    refute Retry.retry_transport?(non_idempotent, error)
  end

  test "emits retry telemetry during backoff" do
    ref = make_ref()

    :ok =
      :telemetry.attach(
        ref,
        [:azure_sdk, :retry],
        fn event, measurements, metadata, _ ->
          send(self(), {event, measurements, metadata})
        end,
        nil
      )

    policy = %{Retry.default_policy() | jitter: false, base_delay_ms: 0, max_delay_ms: 0}
    Retry.backoff(policy, 1, %{service: :blob})
    assert_received {[:azure_sdk, :retry], %{delay_ms: 0}, %{service: :blob, attempt: 1}}
    :telemetry.detach(ref)
  end
end
