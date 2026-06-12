defmodule AzureSDK do
  @moduledoc """
  AzureSDK is a long-term Azure platform SDK for Elixir and Erlang.

  v0.1.0 implements Blob Storage on top of a reusable core pipeline,
  identity plane, and telemetry system designed to grow into a full
  multi-service Azure SDK.

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

      {:ok, container} = AzureSDK.Storage.Container.create(client, "uploads")
      {:ok, blob} = AzureSDK.Storage.Blob.upload(client, "uploads", "file.txt", "hello")

  See the guides in `guides/` and livebooks in `livebooks/` for deeper coverage.
  """

  @doc "Returns the current AzureSDK version."
  @spec version() :: String.t()
  def version do
    Application.spec(:azure_sdk, :vsn) |> to_string()
  end
end
