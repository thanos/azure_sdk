defmodule AzureSDK.Identity.ClientSecretCredentialTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Identity.{AccessToken, ClientSecretCredential, TokenCredential}

  setup do
    bypass = Bypass.open()
    host = "http://localhost:#{bypass.port}"

    credential =
      ClientSecretCredential.new(
        tenant_id: "tenant",
        client_id: "client",
        client_secret: "secret",
        authority_host: host
      )

    {:ok, bypass: bypass, credential: credential}
  end

  test "acquires token via client credentials grant", %{bypass: bypass, credential: credential} do
    Bypass.expect_once(bypass, "POST", "/tenant/oauth2/v2.0/token", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)

      assert params["grant_type"] == "client_credentials"
      assert params["client_id"] == "client"
      assert params["client_secret"] == "secret"
      assert params["scope"] == "https://storage.azure.com/.default"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{
          "access_token" => "tok-123",
          "expires_in" => 3600,
          "token_type" => "Bearer"
        })
      )
    end)

    assert {:ok, %AccessToken{token: "tok-123"}} =
             TokenCredential.get_token(credential, ["https://storage.azure.com/.default"])
  end

  test "returns error on token endpoint failure", %{bypass: bypass, credential: credential} do
    Bypass.expect_once(bypass, "POST", "/tenant/oauth2/v2.0/token", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        401,
        Jason.encode!(%{"error" => "invalid_client", "error_description" => "bad"})
      )
    end)

    assert {:error, %{status: 401, code: "invalid_client"}} =
             TokenCredential.get_token(credential, ["https://storage.azure.com/.default"])
  end
end
