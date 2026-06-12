defmodule ExAzure do
  @moduledoc """
  ExAzure is a long-term Azure platform SDK for Elixir and Erlang.

  v0.1.0 implements Blob Storage on top of a reusable core pipeline,
  identity plane, and telemetry system designed to grow into a full
  multi-service Azure SDK.

  ## Quick start

      credential =
        ExAzure.Identity.SharedKeyCredential.new(
          "myaccount",
          System.fetch_env!("AZURE_STORAGE_KEY")
        )

      client =
        ExAzure.Storage.Client.new(
          account: "myaccount",
          credential: credential
        )

      {:ok, container} = ExAzure.Storage.Container.create(client, "uploads")
      {:ok, blob} = ExAzure.Storage.Blob.upload(client, "uploads", "file.txt", "hello")

  See the guides in `guides/` and livebooks in `livebooks/` for deeper coverage.
  """

  @version "0.1.0"

  @doc "Returns the current ExAzure version."
  @spec version() :: String.t()
  def version, do: @version
end
