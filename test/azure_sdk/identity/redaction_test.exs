defmodule AzureSDK.Identity.RedactionTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Identity.{
    AccessToken,
    ClientSecretCredential,
    EnvironmentCredential,
    SASCredential,
    SharedKeyCredential
  }

  test "credentials and tokens do not expose secrets through inspect" do
    secret_values = [
      ClientSecretCredential.new(tenant_id: "t", client_id: "c", client_secret: "secret-value"),
      SharedKeyCredential.new("acct", Base.encode64("secret-value")),
      SASCredential.new("sv=2021-06-08&sig=secret-value"),
      AccessToken.new("secret-value", ~U[2030-01-01 00:00:00Z]),
      EnvironmentCredential.new(
        env: %{
          "AZURE_TENANT_ID" => "t",
          "AZURE_CLIENT_ID" => "c",
          "AZURE_CLIENT_SECRET" => "secret-value"
        }
      )
    ]

    for value <- secret_values do
      inspected = inspect(value)
      refute inspected =~ "secret-value"
      refute inspected =~ Base.encode64("secret-value")
    end
  end
end
