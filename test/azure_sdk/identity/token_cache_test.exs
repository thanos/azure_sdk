defmodule AzureSDK.Identity.TokenCacheTest do
  use ExUnit.Case, async: false

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
end
