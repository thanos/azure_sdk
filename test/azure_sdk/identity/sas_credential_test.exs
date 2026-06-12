defmodule AzureSDK.Identity.SASCredentialTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Core.Request
  alias AzureSDK.Identity.{Credential, SASCredential}
  alias AzureSDK.Pipeline.SAS

  test "parses token strings and maps" do
    assert %SASCredential{params: %{"sv" => "2021-06-08", "sig" => "abc"}} =
             SASCredential.new("?sv=2021-06-08&sig=abc")

    assert %SASCredential{params: %{"sp" => "r"}} =
             SASCredential.new(%{sp: "r"})
  end

  test "applies sas query parameters to requests" do
    credential = SASCredential.new(%{"sv" => "2021-06-08", "sig" => "abc"})

    request =
      Request.new(
        method: :get,
        path: "/container",
        query: [{"restype", "container"}]
      )

    signed = SAS.apply(request, credential)

    assert {"restype", "container"} in signed.query
    assert {"sv", "2021-06-08"} in signed.query
    assert {"sig", "abc"} in signed.query
  end

  test "signs through credential behaviour" do
    credential = SASCredential.new(%{"sig" => "abc"})
    request = Request.new(method: :get, path: "/")

    signed = Credential.sign_request(credential, request)
    assert {"sig", "abc"} in signed.query
  end
end
