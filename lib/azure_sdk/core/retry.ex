defmodule AzureSDK.Core.Retry do
  @moduledoc """
  Retry policy for transient Azure failures.

  Retries HTTP 408, 429, and 5xx with exponential backoff, optional full jitter,
  and `Retry-After` / `x-ms-retry-after-ms` when present.

  Transport errors are retried only when the request is idempotent
  (`metadata.idempotent != false`). Authorization failures are not retried here.

  ## Policy fields

  * `:max_attempts` — maximum attempts including the first try
  * `:base_delay_ms` — base delay for exponential backoff
  * `:max_delay_ms` — upper bound for computed delays
  * `:jitter` — when `true`, delay is uniform in `0..capped`

  ## Examples

      iex> policy = AzureSDK.Core.Retry.default_policy()
      iex> policy.max_attempts
      3
  """

  alias AzureSDK.Core.{Request, Response}
  alias AzureSDK.Error

  @default_max_attempts 3
  @default_base_delay_ms 200

  @typedoc "Retry policy map. See the module documentation for field meanings."
  @opaque policy :: %{
            max_attempts: pos_integer(),
            base_delay_ms: pos_integer(),
            max_delay_ms: pos_integer(),
            jitter: boolean()
          }

  @doc """
  Returns the default retry policy.

  ## Examples

      iex> AzureSDK.Core.Retry.default_policy()
      %{max_attempts: 3, base_delay_ms: 200, max_delay_ms: 5000, jitter: true}
  """
  @spec default_policy() :: policy()
  def default_policy do
    %{
      max_attempts: @default_max_attempts,
      base_delay_ms: @default_base_delay_ms,
      max_delay_ms: 5_000,
      jitter: true
    }
  end

  @doc """
  Returns `true` when the HTTP response should be retried (408, 429, or 5xx).

  ## Examples

      iex> AzureSDK.Core.Retry.retryable?(%AzureSDK.Core.Response{status: 503})
      true
      iex> AzureSDK.Core.Retry.retryable?(%AzureSDK.Core.Response{status: 404})
      false
  """
  @spec retryable?(Response.t()) :: boolean()
  def retryable?(%Response{status: status})
      when status in [408, 429] or status in 500..599,
      do: true

  def retryable?(_), do: false

  @doc """
  Returns `true` when a transport error should be retried for this request.

  ## Examples

      iex> req = AzureSDK.Core.Request.new(method: :post, metadata: %{idempotent: false})
      iex> AzureSDK.Core.Retry.retry_transport?(req, AzureSDK.Error.new(message: "down"))
      false
  """
  @spec retry_transport?(Request.t(), Error.t()) :: boolean()
  def retry_transport?(%Request{} = request, %Error{}) do
    idempotent?(request)
  end

  @doc """
  Returns whether the request is considered idempotent for transport retries.

  Explicit `metadata.idempotent` wins. Otherwise GET/HEAD/PUT/DELETE are treated
  as idempotent.

  ## Examples

      iex> AzureSDK.Core.Retry.idempotent?(AzureSDK.Core.Request.new(method: :get))
      true
      iex> AzureSDK.Core.Retry.idempotent?(
      ...>   AzureSDK.Core.Request.new(method: :post, metadata: %{idempotent: true})
      ...> )
      true
  """
  @spec idempotent?(Request.t()) :: boolean()
  def idempotent?(%Request{metadata: metadata, method: method}) do
    case Map.fetch(metadata, :idempotent) do
      {:ok, false} -> false
      {:ok, true} -> true
      :error -> method in [:get, :head, :put, :delete]
    end
  end

  @doc """
  Computes the backoff delay in milliseconds for an attempt number.

  Attempt `1` uses `base_delay_ms`. With `jitter: false` the delay is exact.

  ## Examples

      iex> policy = %{AzureSDK.Core.Retry.default_policy() | jitter: false}
      iex> AzureSDK.Core.Retry.delay_ms(policy, 1)
      200
      iex> AzureSDK.Core.Retry.delay_ms(policy, 2)
      400
  """
  @spec delay_ms(policy(), pos_integer()) :: non_neg_integer()
  def delay_ms(policy, attempt) do
    exponential = (policy.base_delay_ms * :math.pow(2, attempt - 1)) |> round()
    capped = min(exponential, policy.max_delay_ms)

    if Map.get(policy, :jitter, true) do
      if capped == 0, do: 0, else: :rand.uniform(capped + 1) - 1
    else
      capped
    end
  end

  @doc """
  Computes delay, preferring `Retry-After` / `x-ms-retry-after-ms` when present.

  Integer `Retry-After` values are treated as seconds. Non-integer HTTP-date
  values fall back to exponential backoff.

  ## Examples

      iex> policy = %{AzureSDK.Core.Retry.default_policy() | jitter: false, max_delay_ms: 10_000}
      iex> resp = %AzureSDK.Core.Response{status: 429, headers: %{"retry-after" => "2"}}
      iex> AzureSDK.Core.Retry.delay_ms(policy, 1, resp)
      2000
  """
  @spec delay_ms(policy(), pos_integer(), Response.t() | nil) :: non_neg_integer()
  def delay_ms(policy, attempt, nil), do: delay_ms(policy, attempt)

  def delay_ms(policy, attempt, %Response{headers: headers}) do
    case retry_after_ms(headers) do
      nil -> delay_ms(policy, attempt)
      ms -> min(ms, policy.max_delay_ms)
    end
  end

  @doc """
  Sleeps for the computed backoff and emits `[:azure_sdk, :retry]` telemetry.

  Prefer calling this from the pipeline rather than application code. Sleeps
  the current process; avoid long delays in latency-sensitive paths.

  ## Parameters

  * `policy` — retry policy
  * `attempt` — 1-based attempt that just failed
  * `metadata` — telemetry metadata map
  * `response` — optional failed response for Retry-After parsing (`nil` for transport errors)

  ## Returns

  `:ok` after sleeping.

  ## Examples

  Used by `AzureSDK.Core.Pipeline` between attempts; not typically called from
  application code.
  """
  @spec backoff(policy(), pos_integer(), map()) :: :ok
  def backoff(policy, attempt, metadata) do
    backoff(policy, attempt, metadata, nil)
  end

  @doc """
  Same as `backoff/3`, with an optional failed response for Retry-After headers.

  See `backoff/3`.
  """
  @spec backoff(policy(), pos_integer(), map(), Response.t() | nil) :: :ok
  def backoff(policy, attempt, metadata, response) do
    delay = delay_ms(policy, attempt, response)

    :telemetry.execute(
      [:azure_sdk, :retry],
      %{count: 1, delay_ms: delay},
      Map.put(metadata, :attempt, attempt)
    )

    Process.sleep(delay)
  end

  defp retry_after_ms(headers) when is_map(headers) do
    cond do
      ms = header_ci(headers, "x-ms-retry-after-ms") ->
        parse_int_ms(ms)

      value = header_ci(headers, "retry-after") ->
        parse_retry_after(value)

      true ->
        nil
    end
  end

  defp header_ci(headers, name) do
    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(to_string(k)) == name, do: v
    end)
  end

  defp parse_int_ms(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, _} when int >= 0 -> int
      _ -> nil
    end
  end

  defp parse_int_ms(value) when is_integer(value) and value >= 0, do: value
  defp parse_int_ms(_), do: nil

  defp parse_retry_after(value) when is_binary(value) do
    trimmed = String.trim(value)

    case Integer.parse(trimmed) do
      {seconds, ""} when seconds >= 0 ->
        seconds * 1000

      _ ->
        nil
    end
  end

  defp parse_retry_after(_), do: nil
end
