defmodule ExAzure.Storage.ClientTest do
  use ExUnit.Case, async: true

  alias ExAzure.Core.Request
  alias ExAzure.Pipeline.SharedKey
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
    refute Client.path_style?(client)
  end

  test "builds queue, table, and file endpoints without path-style signing" do
    credential = ExAzure.AzureMock.credential()

    for service <- [:queue, :table, :file] do
      client = Client.new(account: "a", credential: credential, service: service)
      refute Client.path_style?(client)
      assert %{path_style: false} = Client.signing_metadata(client)
    end
  end

  test "detects path-style endpoints" do
    credential = ExAzure.AzureMock.credential()

    client =
      Client.new(
        account: "mockaccount",
        credential: credential,
        endpoint: "http://127.0.0.1:10000/mockaccount"
      )

    assert Client.path_style?(client)
    assert %{path_style: true, api_version: "2024-11-04"} = Client.signing_metadata(client)
  end

  test "sovereign cloud endpoints use host-style signing" do
    credential = ExAzure.AzureMock.credential()

    client =
      Client.new(
        account: "acct",
        credential: credential,
        endpoint: "https://acct.blob.core.usgovcloudapi.net"
      )

    refute Client.path_style?(client)

    request =
      Request.new(
        method: :get,
        path: "/container/blob",
        metadata: Client.signing_metadata(client)
      )

    string = SharedKey.string_to_sign(request, "acct")
    assert String.ends_with?(string, "/acct/container/blob")
    refute String.contains?(string, "/acct/acct/")
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
