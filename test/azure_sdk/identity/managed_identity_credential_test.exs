defmodule AzureSDK.Identity.ManagedIdentityCredentialTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Identity.{AccessToken, ManagedIdentityCredential, TokenCredential}

  setup do
    bypass = Bypass.open()
    endpoint = "http://localhost:#{bypass.port}/metadata/identity/oauth2/token"
    credential = ManagedIdentityCredential.new(endpoint: endpoint, client_id: "mi-client")
    {:ok, bypass: bypass, credential: credential}
  end

  test "acquires token from IMDS", %{bypass: bypass, credential: credential} do
    Bypass.expect_once(bypass, "GET", "/metadata/identity/oauth2/token", fn conn ->
      assert Plug.Conn.get_req_header(conn, "metadata") == ["true"]
      assert conn.query_params["api-version"] == "2018-02-01"
      assert conn.query_params["resource"] == "https://storage.azure.com"
      assert conn.query_params["client_id"] == "mi-client"

      expires_on = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{
          "access_token" => "mi-token",
          "expires_on" => Integer.to_string(expires_on)
        })
      )
    end)

    assert {:ok, %AccessToken{token: "mi-token"}} =
             TokenCredential.get_token(credential, ["https://storage.azure.com/.default"])
  end
end
