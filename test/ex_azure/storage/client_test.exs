defmodule ExAzure.Storage.ClientTest do
  use ExUnit.Case, async: true

  alias ExAzure.Storage.Client

  test "builds default blob endpoint" do
    credential = ExAzure.AzureMock.credential()

    client =
      Client.new(
        account: "myaccount",
        credential: credential
      )

    assert client.endpoint == "https://myaccount.blob.core.windows.net"
    assert client.api_version == "2024-11-04"
    refute Client.emulator?(client)
  end

  test "builds queue, table, and file endpoints" do
    credential = ExAzure.AzureMock.credential()

    assert Client.new(account: "a", credential: credential, service: :queue).endpoint ==
             "https://a.queue.core.windows.net"

    assert Client.new(account: "a", credential: credential, service: :table).endpoint ==
             "https://a.table.core.windows.net"

    assert Client.new(account: "a", credential: credential, service: :file).endpoint ==
             "https://a.file.core.windows.net"
  end

  test "detects emulator endpoints" do
    credential = ExAzure.AzureMock.credential()

    client =
      Client.new(
        account: "mockaccount",
        credential: credential,
        endpoint: "http://127.0.0.1:10000/mockaccount"
      )

    assert Client.emulator?(client)
    assert %{emulator: true, api_version: "2024-11-04"} = Client.signing_metadata(client)
  end

  test "converts to core client" do
    credential = ExAzure.AzureMock.credential()

    storage =
      Client.new(
        account: "mockaccount",
        credential: credential,
        endpoint: "http://localhost/mockaccount",
        retry: %{max_attempts: 1, base_delay_ms: 1, max_delay_ms: 1}
      )

    core = Client.to_core_client(storage)
    assert core.credential == credential
    assert core.endpoint == "http://localhost/mockaccount"
    assert core.retry.max_attempts == 1
  end
end
