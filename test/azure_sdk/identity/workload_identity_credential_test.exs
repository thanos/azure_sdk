defmodule AzureSDK.Identity.WorkloadIdentityCredentialTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Identity.{AccessToken, TokenCredential, WorkloadIdentityCredential}

  setup do
    bypass = Bypass.open()

    path =
      Path.join(System.tmp_dir!(), "azure_sdk_federated_#{System.unique_integer([:positive])}")

    File.write!(path, "federated-jwt\n")
    on_exit(fn -> File.rm(path) end)

    credential =
      WorkloadIdentityCredential.new(
        tenant_id: "tenant",
        client_id: "client",
        federated_token_file: path,
        authority_host: "http://localhost:#{bypass.port}"
      )

    {:ok, bypass: bypass, credential: credential, path: path}
  end

  test "exchanges federated token for access token", %{bypass: bypass, credential: credential} do
    Bypass.expect_once(bypass, "POST", "/tenant/oauth2/v2.0/token", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)

      assert params["client_assertion"] == "federated-jwt"

      assert params["client_assertion_type"] ==
               "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{"access_token" => "wi-token", "expires_in" => 3600})
      )
    end)

    assert {:ok, %AccessToken{token: "wi-token"}} =
             TokenCredential.get_token(credential, ["https://storage.azure.com/.default"])
  end

  test "errors when federated token file is missing" do
    credential =
      WorkloadIdentityCredential.new(
        tenant_id: "t",
        client_id: "c",
        federated_token_file: "/tmp/does-not-exist-#{System.unique_integer([:positive])}"
      )

    assert {:error, %{code: "FederatedTokenUnavailable"}} =
             TokenCredential.get_token(credential, ["https://storage.azure.com/.default"])
  end
end
