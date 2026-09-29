defmodule AzureSDK.Core.Retry do
  @moduledoc """
  Retry policy for transient Azure failures.

  Retries HTTP 408, 429, and 5xx with exponential backoff, optional full jitter,
  and `Retry-After` / `x-ms-retry-after-ms` when present.

  HTTP 429 and 503 mean the service did not process the request, so they are
  always retried. HTTP 408, 500, 502 and 504 may arrive after the request took
  effect, so they are retried only for idempotent requests, as are transport
  errors (see `idempotent?/1`). Authorization failures are not retried here.

  ## Policy fields

  * `:max_attempts` - maximum attempts including the first try
  * `:base_delay_ms` - base delay for exponential backoff
  * `:max_delay_ms` - upper bound for computed delays
  * `:jitter` - when `true`, delay is uniform in `0..capped`
  * `:max_retry_after_ms` - upper bound for server-requested `Retry-After`
    delays (default `60_000`); larger requests are clamped to this value

  ## Examples

      iex> policy = AzureSDK.Core.Retry.default_policy()
      iex> policy.max_attempts
      3
  """

  alias AzureSDK.Core.{Request, Response}
  alias AzureSDK.Error

  @default_max_attempts 3
  @default_base_delay_ms 200
  @default_max_retry_after_ms 60_000

  @typedoc "Retry policy map. See the module documentation for field meanings."
  @type policy :: %{
          required(:max_attempts) => pos_integer(),
          required(:base_delay_ms) => non_neg_integer(),
          required(:max_delay_ms) => non_neg_integer(),
          optional(:jitter) => boolean(),
          optional(:max_retry_after_ms) => non_neg_integer()
        }

  @doc """
  Returns the default retry policy.

  ## Examples

      iex> AzureSDK.Core.Retry.default_policy()
      %{max_attempts: 3, base_delay_ms: 200, max_delay_ms: 5000, jitter: true, max_retry_after_ms: 60000}
  """
  # The success typing is the literal map; the public contract is policy().
  @dialyzer {:nowarn_function, default_policy: 0}
  @spec default_policy() :: policy()
  def default_policy do
    %{
      max_attempts: @default_max_attempts,
      base_delay_ms: @default_base_delay_ms,
      max_delay_ms: 5_000,
      jitter: true,
      max_retry_after_ms: @default_max_retry_after_ms
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
  Returns `true` when a failed HTTP response should be retried for this request.

  429 and 503 are always retried. 408, 500, 502 and 504 are retried only when
  the request is idempotent.

  ## Examples

      iex> post = AzureSDK.Core.Request.new(method: :post, metadata: %{idempotent: false})
      iex> AzureSDK.Core.Retry.retry_response?(post, %AzureSDK.Core.Response{status: 503})
      true
      iex> AzureSDK.Core.Retry.retry_response?(post, %AzureSDK.Core.Response{status: 500})
      false
  """
  @spec retry_response?(Request.t(), Response.t()) :: boolean()
  def retry_response?(%Request{}, %Response{status: status}) when status in [429, 503], do: true

  def retry_response?(%Request{} = request, %Response{} = response) do
    retryable?(response) and idempotent?(request)
  end

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
  values fall back to exponential backoff. Server-requested delays are capped
  by `:max_retry_after_ms`, not `:max_delay_ms`.

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
      ms -> min(ms, Map.get(policy, :max_retry_after_ms, @default_max_retry_after_ms))
    end
  end

  @doc """
  Sleeps for the computed backoff and emits `[:azure_sdk, :retry]` telemetry.

  `AzureSDK.Core.Pipeline` calls this between attempts. It blocks the calling
  process for the delay.

  ## Parameters

  * `policy` - retry policy
  * `attempt` - 1-based attempt that just failed
  * `metadata` - telemetry metadata map
  * `response` - optional failed response for Retry-After parsing (`nil` for transport errors)
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
