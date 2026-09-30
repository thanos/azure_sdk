defmodule AzureSDK do
  @moduledoc """
  AzureSDK is a long-term Azure platform SDK for Elixir and Erlang.

  v0.3.0 adds production Blob streams, leases, lazy listing, and SAS generation
  on top of the v0.2.0 identity and retry foundation.

  ## Quick start

      credential =
        AzureSDK.Identity.SharedKeyCredential.new(
          "myaccount",
          System.fetch_env!("AZURE_STORAGE_KEY")
        )

      client =
        AzureSDK.Storage.Client.new(
          account: "myaccount",
          credential: credential
        )

      {:ok, _container} = AzureSDK.Storage.Container.create(client, "uploads")
      {:ok, _blob} = AzureSDK.Storage.Blob.upload(client, "uploads", "file.txt", "hello")

  ## Entra ID

      credential =
        AzureSDK.Identity.ClientSecretCredential.new(
          tenant_id: System.fetch_env!("AZURE_TENANT_ID"),
          client_id: System.fetch_env!("AZURE_CLIENT_ID"),
          client_secret: System.fetch_env!("AZURE_CLIENT_SECRET")
        )

  See the guides in `guides/` and Livebooks in `livebooks/` for deeper coverage.
  """

  @doc """
  Returns the current AzureSDK application version string.

  ## Returns

  Version string from the application spec (for example `"0.3.0"`).

  ## Examples

      iex> version = AzureSDK.version()
      iex> is_binary(version) and String.contains?(version, ".")
      true
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:azure_sdk, :vsn) |> to_string()
  end
end
