defmodule AzureSDK.Identity.TokenCache do
  @moduledoc """
  Supervised OTP token cache with expiry-aware refresh and request coalescing.

  Concurrent callers for the same cache key share a single in-flight
  `get_token/3` acquisition.

  Started by `AzureSDK.Application` under the name
  `AzureSDK.Identity.TokenCache`.

  ## State fields

  * `:tokens` - map of `{cache_key, sorted_scopes}` to `AccessToken`
  * `:inflight` - acquiring process and waiters for in-progress acquisitions

  Expired tokens are pruned whenever a new token is stored. If a credential
  raises or its acquiring process exits, every waiter receives
  `{:error, %AzureSDK.Error{code: "TokenAcquisitionFailed"}}`.

  ## Examples

      scopes = ["https://storage.azure.com/.default"]
      {:ok, token} = AzureSDK.Identity.TokenCache.fetch(credential, scopes)
      :ok = AzureSDK.Identity.TokenCache.invalidate(credential, scopes)
  """

  use GenServer

  alias AzureSDK.Core.Telemetry
  alias AzureSDK.Error
  alias AzureSDK.Identity.{AccessToken, TokenCredential}

  @default_buffer_seconds 300
  @name __MODULE__

  @typedoc "Internal GenServer state. Not part of the public API surface."
  @type state :: %{
          tokens: %{term() => AccessToken.t()},
          inflight: %{term() => %{pid: pid(), waiters: [GenServer.from()]}}
        }

  @doc false
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Returns a cached token or acquires one via the credential.

  ## Parameters

  * `credential` - `TokenCredential` implementer
  * `scopes` - list of OAuth scope strings
  * `opts` - optional keyword list:
    * `:buffer_seconds` - refresh buffer before expiry (default `300`)
    * `:server` - GenServer name (default `AzureSDK.Identity.TokenCache`)
    * `:force_refresh` - when `true`, bypass cache and re-acquire
    * other keys - forwarded to `TokenCredential.get_token/3`

  ## Returns

  * `{:ok, %AzureSDK.Identity.AccessToken{}}`
  * `{:error, %AzureSDK.Error{}}` - acquisition failure

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

  * `credential` - token credential
  * `scopes` - same scopes used for `fetch/3`
  * `opts` - optional `:server` name

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

  Intended for tests. Removes all tokens. Callers waiting on an in-progress
  acquisition receive `{:error, %AzureSDK.Error{code: "TokenAcquisitionFailed"}}`.

  ## Options

  * `:server` - GenServer name (default `AzureSDK.Identity.TokenCache`)

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
    cached = Map.get(state.tokens, key)

    cond do
      not force? and match?(%AccessToken{}, cached) and not AccessToken.stale?(cached, buffer) ->
        Telemetry.emit_token_cache(:hit, %{cache_key_type: cache_key_type(key)})
        {:reply, {:ok, cached}, state}

      Map.has_key?(state.inflight, key) ->
        Telemetry.emit_token_cache(:miss, %{cache_key_type: cache_key_type(key)})
        {:noreply, update_in(state.inflight[key].waiters, &[from | &1])}

      true ->
        Telemetry.emit_token_cache(:miss, %{cache_key_type: cache_key_type(key)})
        pid = start_acquire(key, credential, scopes, opts)
        {:noreply, put_in(state.inflight[key], %{pid: pid, waiters: [from]})}
    end
  end

  def handle_call({:invalidate, key}, _from, state) do
    {:reply, :ok, %{state | tokens: Map.delete(state.tokens, key)}}
  end

  def handle_call(:clear, _from, state) do
    error = acquire_error("Token cache was cleared while the token was being acquired")

    Enum.each(state.inflight, fn {_key, %{waiters: waiters}} ->
      Enum.each(waiters, &GenServer.reply(&1, {:error, error}))
    end)

    {:reply, :ok, %{tokens: %{}, inflight: %{}}}
  end

  @impl true
  def handle_info({:token_acquired, pid, key, result}, state) do
    case Map.get(state.inflight, key) do
      %{pid: ^pid, waiters: waiters} ->
        state = update_in(state.inflight, &Map.delete(&1, key))
        state = maybe_store(state, key, result)
        Enum.each(waiters, &GenServer.reply(&1, result))
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  # The acquiring process sends :token_acquired before exiting, so by the time
  # its :DOWN arrives the inflight entry is already gone. An entry that is still
  # present means the process died without reporting a result.
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    case Enum.find(state.inflight, fn {_key, entry} -> entry.pid == pid end) do
      {key, %{waiters: waiters}} ->
        error = acquire_error("Token acquisition process exited: #{inspect(reason)}")
        Enum.each(waiters, &GenServer.reply(&1, {:error, error}))
        {:noreply, update_in(state.inflight, &Map.delete(&1, key))}

      nil ->
        {:noreply, state}
    end
  end

  defp start_acquire(key, credential, scopes, opts) do
    parent = self()

    {pid, _ref} =
      spawn_monitor(fn ->
        start = System.monotonic_time()
        result = safe_get_token(credential, scopes, opts)
        duration = System.monotonic_time() - start

        :telemetry.execute(
          [:azure_sdk, :auth, :token, :acquire],
          %{duration: duration, count: 1},
          %{result: elem(result, 0), cache_key_type: cache_key_type(key)}
        )

        send(parent, {:token_acquired, self(), key, result})
      end)

    pid
  end

  defp safe_get_token(credential, scopes, opts) do
    case TokenCredential.get_token(credential, scopes, opts) do
      {:ok, %AccessToken{}} = ok -> ok
      {:error, %Error{}} = error -> error
    end
  rescue
    exception -> {:error, Error.from_exception(:identity, exception)}
  catch
    kind, reason -> {:error, acquire_error("Credential #{kind}: #{inspect(reason)}")}
  end

  defp maybe_store(state, key, {:ok, %AccessToken{} = token}) do
    tokens =
      state.tokens
      |> Map.reject(fn {_key, cached} -> AccessToken.stale?(cached, 0) end)
      |> Map.put(key, token)

    %{state | tokens: tokens}
  end

  defp maybe_store(state, _key, {:error, _}), do: state

  defp acquire_error(message) do
    Error.new(code: "TokenAcquisitionFailed", message: message, service: :identity)
  end

  defp cache_key_type({cred_key, _scopes}) when is_tuple(cred_key), do: elem(cred_key, 0)
  defp cache_key_type(_), do: :unknown
end
