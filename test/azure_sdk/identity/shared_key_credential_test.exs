defmodule AzureSDK.Identity.SharedKeyCredentialTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Core.Request
  alias AzureSDK.Identity.{Credential, SharedKeyCredential}

  test "signs through credential behaviour" do
    credential =
      SharedKeyCredential.new("account", Base.encode64("password-password-password-password"))

    request =
      Request.new(
        method: :get,
        path: "/container",
        headers: %{"x-ms-version" => "2021-08-06"},
        metadata: %{api_version: "2021-08-06", path_style: true}
      )

    signed = Credential.sign_request(credential, request)

    assert signed.headers["Authorization"] =~ "SharedKey account:"
    assert signed.headers["x-ms-date"]
  end
end
