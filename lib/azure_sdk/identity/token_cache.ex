defmodule AzureSDK.Identity.TokenCache do
  @moduledoc """
  OTP-based token cache for Azure credentials.

  Planned for v0.2.0 alongside OAuth credential support. The cache will use
  a supervised `Agent` or `Cachex` process to store tokens with TTL-based
  refresh and telemetry on cache hits and misses.
  """

  @doc false
  @spec get(term()) :: {:ok, String.t()} | :miss
  def get(_key), do: :miss

  @doc false
  @spec put(term(), String.t(), keyword()) :: :ok
  def put(_key, _token, _opts \\ []), do: :ok
end
