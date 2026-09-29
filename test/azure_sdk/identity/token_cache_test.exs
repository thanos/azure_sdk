defmodule AzureSDK.Identity.TokenCacheTest do
  use ExUnit.Case, async: false

  alias AzureSDK.Error
  alias AzureSDK.Identity.{AccessToken, TokenCache, TokenCredential}

  defmodule SlowCred do
    @behaviour TokenCredential
    defstruct [:pid, :token]

    def cache_key(%__MODULE__{token: token}), do: {:slow, token}

    def get_token(%__MODULE__{pid: pid, token: token}, _scopes, _opts) do
      send(pid, :acquire_started)
      Process.sleep(50)
      send(pid, :acquire_finished)

      {:ok, AccessToken.new(token, DateTime.add(DateTime.utc_now(), 3600, :second))}
    end
  end

  defmodule RaisingCred do
    @behaviour TokenCredential
    defstruct [:name]

    def cache_key(%__MODULE__{name: name}), do: {:raising, name}
    def get_token(%__MODULE__{}, _scopes, _opts), do: raise("boom")
  end

  defmodule FailingCred do
    @behaviour TokenCredential
    defstruct [:pid]

    def cache_key(%__MODULE__{}), do: {:failing, :one}

    def get_token(%__MODULE__{pid: pid}, _scopes, _opts) do
      send(pid, :acquire_started)
      Process.sleep(20)
      {:error, Error.new(code: "invalid_client", service: :identity)}
    end
  end

  defmodule ExpiringCred do
    @behaviour TokenCredential
    defstruct [:pid, :lifetime]

    def cache_key(%__MODULE__{}), do: {:expiring, :one}

    def get_token(%__MODULE__{pid: pid, lifetime: lifetime}, _scopes, _opts) do
      send(pid, :acquire_started)
      {:ok, AccessToken.new("t", DateTime.add(DateTime.utc_now(), lifetime, :second))}
    end
  end

  defmodule BlockingCred do
    @behaviour TokenCredential
    defstruct [:pid]

    def cache_key(%__MODULE__{}), do: {:blocking, :one}

    def get_token(%__MODULE__{pid: pid}, _scopes, _opts) do
      send(pid, {:acquiring, self()})

      receive do
        :release -> {:ok, AccessToken.new("late", DateTime.add(DateTime.utc_now(), 3600))}
      end
    end
  end

  setup do
    name = :"token_cache_#{System.unique_integer([:positive])}"
    start_supervised!({TokenCache, name: name})
    {:ok, server: name}
  end

  test "coalesces concurrent fetches into a single acquire", %{server: server} do
    cred = %SlowCred{pid: self(), token: "shared"}

    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          TokenCache.fetch(cred, ["scope"], server: server)
        end)
      end

    results = Task.await_many(tasks)

    assert Enum.all?(results, fn {:ok, %AccessToken{token: "shared"}} -> true end)
    assert_received :acquire_started
    assert_received :acquire_finished
    refute_received :acquire_started
  end

  test "returns cached token on subsequent fetch", %{server: server} do
    cred = %SlowCred{pid: self(), token: "cached"}

    assert {:ok, _} = TokenCache.fetch(cred, ["scope"], server: server)
    assert_received :acquire_started

    assert {:ok, %AccessToken{token: "cached"}} =
             TokenCache.fetch(cred, ["scope"], server: server)

    refute_received :acquire_started
  end

  test "force_refresh bypasses cache", %{server: server} do
    cred = %SlowCred{pid: self(), token: "force"}

    assert {:ok, _} = TokenCache.fetch(cred, ["scope"], server: server)
    assert_received :acquire_started

    assert {:ok, _} = TokenCache.fetch(cred, ["scope"], server: server, force_refresh: true)
    assert_received :acquire_started
  end

  test "a raising credential returns an error and does not wedge the key", %{server: server} do
    cred = %RaisingCred{name: "r"}

    assert {:error, %Error{service: :identity}} =
             TokenCache.fetch(cred, ["scope"], server: server)

    assert {:error, %Error{}} = TokenCache.fetch(cred, ["scope"], server: server)
    assert :sys.get_state(server).inflight == %{}
  end

  test "errors reach every coalesced waiter and are not cached", %{server: server} do
    cred = %FailingCred{pid: self()}

    results =
      1..3
      |> Enum.map(fn _ ->
        Task.async(fn -> TokenCache.fetch(cred, ["scope"], server: server) end)
      end)
      |> Task.await_many()

    assert Enum.all?(results, &match?({:error, %Error{code: "invalid_client"}}, &1))
    assert_received :acquire_started
    refute_received :acquire_started

    assert {:error, _} = TokenCache.fetch(cred, ["scope"], server: server)
    assert_received :acquire_started
  end

  test "a token inside the refresh buffer is re-acquired", %{server: server} do
    cred = %ExpiringCred{pid: self(), lifetime: 60}

    assert {:ok, _} = TokenCache.fetch(cred, ["scope"], server: server, buffer_seconds: 300)
    assert {:ok, _} = TokenCache.fetch(cred, ["scope"], server: server, buffer_seconds: 300)
    assert_received :acquire_started
    assert_received :acquire_started
  end

  test "invalidate forces the next fetch to acquire", %{server: server} do
    cred = %ExpiringCred{pid: self(), lifetime: 3600}

    assert {:ok, _} = TokenCache.fetch(cred, ["scope"], server: server)
    assert :ok = TokenCache.invalidate(cred, ["scope"], server: server)
    assert {:ok, _} = TokenCache.fetch(cred, ["scope"], server: server)
    assert_received :acquire_started
    assert_received :acquire_started
  end

  test "expired tokens are pruned when a new token is stored", %{server: server} do
    stale = AccessToken.new("old", DateTime.add(DateTime.utc_now(), -10, :second))
    :sys.replace_state(server, &put_in(&1.tokens[{:gone, ["scope"]}], stale))

    assert {:ok, _} =
             TokenCache.fetch(%ExpiringCred{pid: self(), lifetime: 3600}, ["scope"],
               server: server
             )

    refute Map.has_key?(:sys.get_state(server).tokens, {:gone, ["scope"]})
  end

  test "clear replies with an error to callers waiting on an acquisition", %{server: server} do
    cred = %BlockingCred{pid: self()}
    task = Task.async(fn -> TokenCache.fetch(cred, ["scope"], server: server) end)
    assert_receive {:acquiring, acquirer}

    assert :ok = TokenCache.clear(server: server)
    assert {:error, %Error{code: "TokenAcquisitionFailed"}} = Task.await(task)

    send(acquirer, :release)
    Process.sleep(20)
    assert :sys.get_state(server).tokens == %{}
  end
end
