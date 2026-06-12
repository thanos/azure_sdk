defmodule AzureSDK.Core.Retry do
  @moduledoc """
  Retry policy for transient Azure failures.

  Retries on HTTP 408, 429, and 5xx responses with exponential backoff.
  """

  @default_max_attempts 3
  @default_base_delay_ms 200

  @type policy :: %{
          max_attempts: pos_integer(),
          base_delay_ms: pos_integer(),
          max_delay_ms: pos_integer()
        }

  @doc """
  Returns the default retry policy.
  """
  @spec default_policy() :: %{
          max_attempts: 3,
          base_delay_ms: 200,
          max_delay_ms: 5000
        }
  def default_policy do
    %{
      max_attempts: @default_max_attempts,
      base_delay_ms: @default_base_delay_ms,
      max_delay_ms: 5_000
    }
  end

  @doc """
  Returns true when the response should be retried.
  """
  @spec retryable?(AzureSDK.Core.Response.t()) :: boolean()
  def retryable?(%AzureSDK.Core.Response{status: status})
      when status in [408, 429] or status in 500..599,
      do: true

  def retryable?(_), do: false

  @doc """
  Computes the backoff delay in milliseconds for a given attempt number.
  """
  @spec delay_ms(policy(), pos_integer()) :: non_neg_integer()
  def delay_ms(policy, attempt) do
    delay = (policy.base_delay_ms * :math.pow(2, attempt - 1)) |> round()
    min(delay, policy.max_delay_ms)
  end

  @doc """
  Sleeps for the computed backoff duration and emits retry telemetry.
  """
  @spec backoff(policy(), pos_integer(), map()) :: :ok
  def backoff(policy, attempt, metadata) do
    delay = delay_ms(policy, attempt)

    :telemetry.execute(
      [:azure_sdk, :retry],
      %{count: 1, delay_ms: delay},
      Map.put(metadata, :attempt, attempt)
    )

    Process.sleep(delay)
  end
end
