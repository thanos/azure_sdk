defmodule AzureSDK.Core.PipelineErrorTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Core.{Client, Pipeline, Request}
  alias AzureSDK.Storage.Client, as: StorageClient

  test "returns transport errors after retries are exhausted" do
    credential = AzureSDK.AzureMock.credential()

    client =
      StorageClient.new(
        account: "mockaccount",
        credential: credential,
        endpoint: "http://127.0.0.1:1",
        retry: %{max_attempts: 1, base_delay_ms: 1, max_delay_ms: 1}
      )

    request =
      Request.new(
        method: :get,
        path: "/",
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        metadata: StorageClient.signing_metadata(client)
      )

    assert {:error, %AzureSDK.Error{service: :blob, message: message}} =
             Pipeline.run(StorageClient.to_core_client(client), request)

    assert message =~ "connect" or message =~ "nxdomain" or message =~ "econnrefused"
  end

  test "runs without a credential for unsigned requests" do
    client = %Client{
      endpoint: "http://127.0.0.1:1",
      retry: %{max_attempts: 1, base_delay_ms: 1, max_delay_ms: 1}
    }

    request = Request.new(method: :get, path: "/", service: :blob)

    assert {:error, %AzureSDK.Error{}} = Pipeline.run(client, request)
  end
end
