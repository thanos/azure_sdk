defmodule AzureSDK.Core.PipelineBearerTest do
  use ExUnit.Case, async: false

  alias AzureSDK.Core.{Client, Pipeline, Request}
  alias AzureSDK.Identity.{AccessToken, TokenCache, TokenCredential}

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

  test "does not retry non-idempotent transport failures", %{bypass: bypass, cache: cache} do
    Bypass.down(bypass)

    client = %Client{
      credential: %StaticTokenCred{token: "t"},
      endpoint: "http://localhost:#{bypass.port}",
      retry: %{max_attempts: 3, base_delay_ms: 1, max_delay_ms: 1, jitter: false},
      req_options: []
    }

    request =
      Request.new(
        method: :post,
        path: "/messages",
        service: :queue,
        operation: :put_message,
        metadata: %{idempotent: false}
      )

    assert {:error, _} = Pipeline.run(client, request, server: cache)
  end
end
