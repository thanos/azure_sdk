defmodule AzureSDK.Identity.DefaultAzureCredentialTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Error
  alias AzureSDK.Identity.{AccessToken, DefaultAzureCredential, TokenCredential}

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
    defstruct []

    def cache_key(%__MODULE__{}), do: :succeeding

    def get_token(%__MODULE__{}, _scopes, _opts) do
      {:ok, AccessToken.new("ok-token", DateTime.add(DateTime.utc_now(), 3600, :second))}
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

  test "returns last error when all fail" do
    cred =
      DefaultAzureCredential.new(
        credentials: [
          %FailingCred{code: "CredentialUnavailable"},
          %FailingCred{code: "boom"}
        ]
      )

    assert {:error, %{code: "boom"}} =
             TokenCredential.get_token(cred, ["https://storage.azure.com/.default"])
  end
end
