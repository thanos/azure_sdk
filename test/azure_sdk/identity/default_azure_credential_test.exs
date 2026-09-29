defmodule AzureSDK.Identity.DefaultAzureCredentialTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Error
  alias AzureSDK.Identity.{AccessToken, DefaultAzureCredential, TokenCache, TokenCredential}

  defmodule FailingCred do
    @behaviour TokenCredential
    defstruct [:code]

    def cache_key(%__MODULE__{code: code}), do: {:failing, code}

    def get_token(%__MODULE__{code: code}, _scopes, _opts) do
      {:error, Error.new(code: code, message: code, service: :identity)}
    end
  end

  defmodule SucceedingCred do
    @behaviour TokenCredential
    defstruct token: "ok-token"

    def cache_key(%__MODULE__{token: token}), do: {:succeeding, token}

    def get_token(%__MODULE__{token: token}, _scopes, _opts) do
      {:ok, AccessToken.new(token, DateTime.add(DateTime.utc_now(), 3600, :second))}
    end
  end

  test "uses first successful credential in the chain" do
    cred =
      DefaultAzureCredential.new(
        credentials: [
          %FailingCred{code: "CredentialUnavailable"},
          %SucceedingCred{},
          %FailingCred{code: "should_not_run"}
        ]
      )

    assert {:ok, %AccessToken{token: "ok-token"}} =
             TokenCredential.get_token(cred, ["https://storage.azure.com/.default"])
  end

  test "returns the last CredentialUnavailable when nothing is usable" do
    cred =
      DefaultAzureCredential.new(
        credentials: [
          %FailingCred{code: "CredentialUnavailable"},
          %FailingCred{code: "CredentialUnavailable"}
        ]
      )

    assert {:error, %{code: "CredentialUnavailable"}} =
             TokenCredential.get_token(cred, ["https://storage.azure.com/.default"])
  end

  test "stops at the first error that is not CredentialUnavailable" do
    cred =
      DefaultAzureCredential.new(
        credentials: [
          %FailingCred{code: "CredentialUnavailable"},
          %FailingCred{code: "invalid_client"},
          %SucceedingCred{}
        ]
      )

    assert {:error, %{code: "invalid_client"}} =
             TokenCredential.get_token(cred, ["https://storage.azure.com/.default"])
  end

  test "default chain is environment then managed identity" do
    cred = DefaultAzureCredential.new(env: %{})

    assert [
             %AzureSDK.Identity.EnvironmentCredential{},
             %AzureSDK.Identity.ManagedIdentityCredential{}
           ] =
             cred.credentials
  end

  test "chains with different identities do not share cached tokens" do
    server = :"dac_cache_#{System.unique_integer([:positive])}"
    start_supervised!({TokenCache, name: server})

    a = DefaultAzureCredential.new(credentials: [%SucceedingCred{token: "identity-a"}])
    b = DefaultAzureCredential.new(credentials: [%SucceedingCred{token: "identity-b"}])

    assert {:ok, %AccessToken{token: "identity-a"}} = TokenCache.fetch(a, ["s"], server: server)
    assert {:ok, %AccessToken{token: "identity-b"}} = TokenCache.fetch(b, ["s"], server: server)
  end
end
