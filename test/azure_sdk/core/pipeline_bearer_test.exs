defmodule AzureSDK.Core.PipelineBearerTest do
  use ExUnit.Case, async: false

  alias AzureSDK.Core.{Client, Pipeline, Request}
  alias AzureSDK.Identity.{AccessToken, TokenCache, TokenCredential}

  defmodule CountingCred do
    @behaviour TokenCredential
    defstruct [:counter]

    def cache_key(%__MODULE__{counter: counter}), do: {:counting, counter}

    def get_token(%__MODULE__{counter: counter}, _scopes, _opts) do
      n = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})
      {:ok, AccessToken.new("token-#{n}", DateTime.add(DateTime.utc_now(), 3600, :second))}
    end
  end

  defmodule StaticTokenCred do
    @behaviour TokenCredential
    defstruct [:token]

    def cache_key(%__MODULE__{token: token}), do: {:static, token}

    def get_token(%__MODULE__{token: token}, _scopes, _opts) do
      {:ok, AccessToken.new(token, DateTime.add(DateTime.utc_now(), 3600, :second))}
    end
  end

  setup do
    bypass = Bypass.open()
    cache = :"pipeline_bearer_cache_#{System.unique_integer([:positive])}"
    start_supervised!({TokenCache, name: cache})

    {:ok, bypass: bypass, cache: cache}
  end

  test "authorizes token credentials with Bearer header", %{bypass: bypass, cache: cache} do
    Bypass.expect_once(bypass, "GET", "/hello", fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer pipeline-token"]
      Plug.Conn.resp(conn, 200, "ok")
    end)

    client = %Client{
      credential: %StaticTokenCred{token: "pipeline-token"},
      endpoint: "http://localhost:#{bypass.port}",
      retry: %{max_attempts: 1, base_delay_ms: 1, max_delay_ms: 1, jitter: false},
      req_options: []
    }

    request = Request.new(method: :get, path: "/hello", service: :blob, operation: :get)

    assert {:ok, %{status: 200, body: "ok"}} =
             Pipeline.run(client, request, server: cache)
  end

  test "refreshes the token once on 401 and retries", %{bypass: bypass, cache: cache} do
    {:ok, acquisitions} = Agent.start_link(fn -> 0 end)
    {:ok, calls} = Agent.start_link(fn -> [] end)

    Bypass.expect(bypass, "GET", "/hello", fn conn ->
      [auth] = Plug.Conn.get_req_header(conn, "authorization")
      Agent.update(calls, &[auth | &1])

      if auth == "Bearer token-1",
        do: Plug.Conn.resp(conn, 401, ""),
        else: Plug.Conn.resp(conn, 200, "ok")
    end)

    client = bearer_client(bypass, %CountingCred{counter: acquisitions}, 1)
    request = Request.new(method: :get, path: "/hello", service: :blob, operation: :get)

    assert {:ok, %{status: 200}} = Pipeline.run(client, request, server: cache)
    assert Agent.get(calls, &Enum.reverse/1) == ["Bearer token-1", "Bearer token-2"]
    assert Agent.get(acquisitions, & &1) == 2
  end

  test "gives up after one refresh when 401 persists", %{bypass: bypass, cache: cache} do
    {:ok, acquisitions} = Agent.start_link(fn -> 0 end)
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    Bypass.expect(bypass, "GET", "/hello", fn conn ->
      Agent.update(calls, &(&1 + 1))
      Plug.Conn.resp(conn, 401, "")
    end)

    client = bearer_client(bypass, %CountingCred{counter: acquisitions}, 3)
    request = Request.new(method: :get, path: "/hello", service: :blob, operation: :get)

    assert {:error, %AzureSDK.Error{status: 401}} = Pipeline.run(client, request, server: cache)
    assert Agent.get(calls, & &1) == 2
    assert Agent.get(acquisitions, & &1) == 2
  end

  test "does not retry a 500 for a non-idempotent request", %{bypass: bypass, cache: cache} do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    Bypass.expect(bypass, "POST", "/messages", fn conn ->
      Agent.update(calls, &(&1 + 1))
      Plug.Conn.resp(conn, 500, "")
    end)

    client = bearer_client(bypass, %StaticTokenCred{token: "t"}, 3)

    request =
      Request.new(
        method: :post,
        path: "/messages",
        service: :queue,
        operation: :put_message,
        metadata: %{idempotent: false}
      )

    assert {:error, %AzureSDK.Error{status: 500}} = Pipeline.run(client, request, server: cache)
    assert Agent.get(calls, & &1) == 1
  end

  test "does not retry non-idempotent transport failures", %{cache: cache} do
    test_pid = self()

    client = %Client{
      credential: %StaticTokenCred{token: "t"},
      endpoint: "http://localhost",
      retry: %{max_attempts: 3, base_delay_ms: 1, max_delay_ms: 1, jitter: false},
      req_options: [
        plug: fn conn ->
          send(test_pid, :attempt)
          Req.Test.transport_error(conn, :econnrefused)
        end
      ]
    }

    request =
      Request.new(
        method: :post,
        path: "/messages",
        service: :queue,
        operation: :put_message,
        metadata: %{idempotent: false}
      )

    assert {:error, %AzureSDK.Error{cause: %Req.TransportError{}}} =
             Pipeline.run(client, request, server: cache)

    assert_received :attempt
    refute_received :attempt
  end

  defp bearer_client(bypass, credential, max_attempts) do
    %Client{
      credential: credential,
      endpoint: "http://localhost:#{bypass.port}",
      retry: %{max_attempts: max_attempts, base_delay_ms: 1, max_delay_ms: 1, jitter: false},
      req_options: []
    }
  end
end
