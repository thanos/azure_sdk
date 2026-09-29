defmodule AzureSDK.Identity.TokenCache do
  @moduledoc """
  Supervised OTP token cache with expiry-aware refresh and request coalescing.

  Concurrent callers for the same cache key share a single in-flight
  `get_token/3` acquisition.

  Started by `AzureSDK.Application` under the name
  `AzureSDK.Identity.TokenCache`.

  ## State fields

  * `:tokens` — map of `{cache_key, sorted_scopes}` to `AccessToken`
  * `:inflight` — waiters for in-progress acquisitions

  ## Examples

      scopes = ["https://storage.azure.com/.default"]
      {:ok, token} = AzureSDK.Identity.TokenCache.fetch(credential, scopes)
      :ok = AzureSDK.Identity.TokenCache.invalidate(credential, scopes)
  """

  use GenServer

  alias AzureSDK.Identity.{AccessToken, TokenCredential}

  @default_buffer_seconds 300
  @name __MODULE__

  @typedoc "Internal GenServer state. Not part of the public API surface."
  @type state :: %{
          tokens: %{term() => AccessToken.t()},
          inflight: %{term() => [pid()]}
        }

  @doc false
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Returns a cached token or acquires one via the credential.

  ## Parameters

  * `credential` — `TokenCredential` implementer
  * `scopes` — list of OAuth scope strings
  * `opts` — optional keyword list:
    * `:buffer_seconds` — refresh buffer before expiry (default `300`)
    * `:server` — GenServer name (default `AzureSDK.Identity.TokenCache`)
    * `:force_refresh` — when `true`, bypass cache and re-acquire
    * other keys — forwarded to `TokenCredential.get_token/3`

  ## Returns

  * `{:ok, %AzureSDK.Identity.AccessToken{}}`
  * `{:error, %AzureSDK.Error{}}` — acquisition failure

  Raises if the cache GenServer is not running (`exit` / call timeout).

  ## Examples

      {:ok, token} =
        AzureSDK.Identity.TokenCache.fetch(
          credential,
          ["https://storage.azure.com/.default"],
          buffer_seconds: 60
        )
  """
  @spec fetch(TokenCredential.t(), [String.t()], keyword()) ::
          {:ok, AccessToken.t()} | {:error, AzureSDK.Error.t()}
  def fetch(credential, scopes, opts \\ []) when is_list(scopes) do
    server = Keyword.get(opts, :server, @name)
    buffer = Keyword.get(opts, :buffer_seconds, @default_buffer_seconds)
    force? = Keyword.get(opts, :force_refresh, false)
    key = {TokenCredential.cache_key(credential), Enum.sort(scopes)}

    GenServer.call(server, {:fetch, key, credential, scopes, opts, buffer, force?}, 60_000)
  end

  @doc """
  Invalidates a cached token for the credential and scopes.

  ## Parameters

  * `credential` — token credential
  * `scopes` — same scopes used for `fetch/3`
  * `opts` — optional `:server` name

  ## Returns

  `:ok`

  ## Examples

      iex> cred = AzureSDK.Identity.ManagedIdentityCredential.new()
      iex> AzureSDK.Identity.TokenCache.invalidate(cred, ["https://storage.azure.com/.default"])
      :ok
  """
  @spec invalidate(TokenCredential.t(), [String.t()], keyword()) :: :ok
  def invalidate(credential, scopes, opts \\ []) when is_list(scopes) do
    server = Keyword.get(opts, :server, @name)
    key = {TokenCredential.cache_key(credential), Enum.sort(scopes)}
    GenServer.call(server, {:invalidate, key})
  end

  @doc """
  Clears the entire cache.

  Intended for tests. Removes all tokens and inflight waiters.

  ## Options

  * `:server` — GenServer name (default `AzureSDK.Identity.TokenCache`)

  ## Returns

  `:ok`

  ## Examples

      iex> AzureSDK.Identity.TokenCache.clear()
      :ok
  """
  @spec clear(keyword()) :: :ok
  def clear(opts \\ []) do
    server = Keyword.get(opts, :server, @name)
    GenServer.call(server, :clear)
  end

  @impl true
  def init(_) do
    {:ok, %{tokens: %{}, inflight: %{}}}
  end

  @impl true
  def handle_call({:fetch, key, credential, scopes, opts, buffer, force?}, from, state) do
    cond do
      not force? and match?(%AccessToken{}, Map.get(state.tokens, key)) and
          not AccessToken.stale?(state.tokens[key], buffer) ->
        emit_cache(:hit, key)
        {:reply, {:ok, state.tokens[key]}, state}

      Map.has_key?(state.inflight, key) ->
        emit_cache(:miss, key)
        waiters = [from | Map.get(state.inflight, key, [])]
        {:noreply, put_in(state.inflight[key], waiters)}

      true ->
        emit_cache(:miss, key)
        parent = self()

        Task.start(fn ->
          start = System.monotonic_time()
          result = TokenCredential.get_token(credential, scopes, opts)
          duration = System.monotonic_time() - start

          :telemetry.execute(
            [:azure_sdk, :auth, :token, :acquire],
            %{duration: duration, count: 1},
            %{
              result: elem_result(result),
              cache_key_type: cache_key_type(key)
            }
          )

          send(parent, {:token_acquired, key, result})
        end)

        {:noreply, put_in(state.inflight[key], [from])}
    end
  end

  def handle_call({:invalidate, key}, _from, state) do
    {:reply, :ok, %{state | tokens: Map.delete(state.tokens, key)}}
  end

  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{tokens: %{}, inflight: %{}}}
  end

  @impl true
  def handle_info({:token_acquired, key, result}, state) do
    waiters = Map.get(state.inflight, key, [])
    state = update_in(state.inflight, &Map.delete(&1, key))

    state =
      case result do
        {:ok, %AccessToken{} = token} ->
          put_in(state.tokens[key], token)

        {:error, _} ->
          state
      end

    Enum.each(waiters, fn from -> GenServer.reply(from, result) end)
    {:noreply, state}
  end

  defp emit_cache(kind, key) do
    :telemetry.execute(
      [:azure_sdk, :auth, :token_cache, kind],
      %{count: 1},
      %{cache_key_type: cache_key_type(key)}
    )
  end

  defp cache_key_type({cred_key, _scopes}) when is_tuple(cred_key), do: elem(cred_key, 0)
  defp cache_key_type(_), do: :unknown

  defp elem_result({:ok, _}), do: :ok
  defp elem_result({:error, _}), do: :error
end
