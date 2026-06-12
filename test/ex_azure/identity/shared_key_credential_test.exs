defmodule ExAzure.Identity.SharedKeyCredentialTest do
  use ExUnit.Case, async: true

  alias ExAzure.Core.Request
  alias ExAzure.Identity.{Credential, SharedKeyCredential}

  test "signs through credential behaviour" do
    credential =
      SharedKeyCredential.new("account", Base.encode64("password-password-password-password"))

    request =
      Request.new(
        method: :get,
        path: "/container",
        headers: %{"x-ms-version" => "2021-08-06"},
        metadata: %{api_version: "2021-08-06", emulator: true}
      )

    signed = Credential.sign_request(credential, request)

    assert signed.headers["Authorization"] =~ "SharedKey account:"
    assert signed.headers["x-ms-date"]
  end
end
