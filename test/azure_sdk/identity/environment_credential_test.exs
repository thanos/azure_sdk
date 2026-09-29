defmodule AzureSDK.Identity.EnvironmentCredentialTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Identity.{
    ClientSecretCredential,
    EnvironmentCredential,
    TokenCredential,
    WorkloadIdentityCredential
  }

  test "builds client secret credential from env" do
    cred =
      EnvironmentCredential.new(
        env: %{
          "AZURE_TENANT_ID" => "tenant",
          "AZURE_CLIENT_ID" => "client",
          "AZURE_CLIENT_SECRET" => "secret"
        }
      )

    assert %EnvironmentCredential{inner: %ClientSecretCredential{}} = cred
  end

  test "builds workload identity credential from env" do
    path = Path.join(System.tmp_dir!(), "azure_sdk_env_wi_#{System.unique_integer([:positive])}")
    File.write!(path, "jwt")
    on_exit(fn -> File.rm(path) end)

    cred =
      EnvironmentCredential.new(
        env: %{
          "AZURE_TENANT_ID" => "tenant",
          "AZURE_CLIENT_ID" => "client",
          "AZURE_FEDERATED_TOKEN_FILE" => path
        }
      )

    assert %EnvironmentCredential{inner: %WorkloadIdentityCredential{}} = cred
  end

  test "returns CredentialUnavailable when env incomplete" do
    cred = EnvironmentCredential.new(env: %{})

    assert {:error, %{code: "CredentialUnavailable"}} =
             TokenCredential.get_token(cred, ["https://storage.azure.com/.default"])
  end
end
