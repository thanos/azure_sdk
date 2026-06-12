defmodule ExAzure.Core.PipelineTest do
  use ExAzure.AzureMockCase, async: false

  alias ExAzure.Core.{Pipeline, Request}
  alias ExAzure.Storage.Client

  test "executes a signed GET request against mock azure", %{bypass: bypass, client: client} do
    AzureMock.stub_list_containers(bypass, ["demo"])

    request =
      Request.new(
        method: :get,
        path: "/",
        query: [{"comp", "list"}],
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: :list_containers,
        metadata: Client.signing_metadata(client)
      )

    assert {:ok, response} = Pipeline.run(Client.to_core_client(client), request)
    assert response.status == 200
    assert response.body =~ "demo"
  end

  test "retries transient failures", %{bypass: bypass, client: client, account: account} do
    AzureMock.stub_retry_then_success(bypass, AzureMock.path([], account), 503, "retry-ok")

    request =
      Request.new(
        method: :get,
        path: "/",
        query: [{"comp", "list"}],
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: :list_containers,
        metadata: Client.signing_metadata(client)
      )

    assert {:ok, response} = Pipeline.run(Client.to_core_client(client), request)
    assert response.body == "retry-ok"
  end

  test "returns structured errors for non-2xx responses", %{
    bypass: bypass,
    client: client,
    account: account
  } do
    AzureMock.stub_error(
      bypass,
      "GET",
      AzureMock.path([], account),
      403,
      "AuthorizationFailure",
      "Forbidden"
    )

    request =
      Request.new(
        method: :get,
        path: "/",
        query: [{"comp", "list"}],
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: :list_containers,
        metadata: Client.signing_metadata(client)
      )

    assert {:error, %{code: "AuthorizationFailure", status: 403, service: :blob}} =
             Pipeline.run(Client.to_core_client(client), request)
  end

  test "uses SAS credentials without shared key signing", %{bypass: bypass} do
    sas =
      ExAzure.Identity.SASCredential.new(%{
        "sv" => "2021-06-08",
        "sr" => "c",
        "sig" => "mock-signature"
      })

    client =
      ExAzure.Storage.Client.new(
        account: "mockaccount",
        credential: sas,
        endpoint: AzureMock.endpoint(bypass)
      )

    AzureMock.stub_list_containers(bypass, ["sas-container"])

    request =
      Request.new(
        method: :get,
        path: "/",
        query: [{"comp", "list"}],
        headers: %{"x-ms-version" => client.api_version},
        service: :blob,
        operation: :list_containers,
        metadata: Client.signing_metadata(client)
      )

    assert {:ok, response} = Pipeline.run(Client.to_core_client(client), request)
    assert response.status == 200
    refute Map.has_key?(response.request.headers, "Authorization")
  end
end
