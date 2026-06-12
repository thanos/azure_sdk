defmodule AzureSDK.Pipeline.SharedKeyTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Core.Request
  alias AzureSDK.Identity.SharedKeyCredential
  alias AzureSDK.Pipeline.SharedKey

  @account "testaccount"
  @key "cGFzc3dvcmQ="

  test "canonicalized headers are sorted and lowercased" do
    request =
      Request.new(
        method: :get,
        path: "/container/blob",
        headers: %{
          "x-ms-version" => "2024-11-04",
          "x-ms-date" => "Wed, 01 Jan 2025 00:00:00 GMT"
        }
      )

    string = SharedKey.string_to_sign(request, @account)

    assert string =~ "x-ms-date:Wed, 01 Jan 2025 00:00:00 GMT\nx-ms-version:2024-11-04"
    assert String.ends_with?(string, "/testaccount/container/blob")
  end

  test "path-style signing duplicates account in canonicalized resource" do
    request =
      Request.new(
        method: :get,
        path: "/container/blob",
        metadata: %{path_style: true}
      )

    string = SharedKey.string_to_sign(request, @account)
    assert String.ends_with?(string, "/testaccount/testaccount/container/blob")
  end

  test "host-style signing uses a single account prefix" do
    request =
      Request.new(
        method: :get,
        path: "/container/blob",
        metadata: %{path_style: false}
      )

    string = SharedKey.string_to_sign(request, @account)
    assert String.ends_with?(string, "/testaccount/container/blob")
    refute String.contains?(string, "/testaccount/testaccount/")
  end

  test "adds Authorization header" do
    credential = SharedKeyCredential.new(@account, @key)

    request =
      Request.new(
        method: :get,
        path: "/container",
        query: [{"restype", "container"}, {"comp", "list"}],
        headers: %{"x-ms-version" => "2024-11-04"},
        service: :blob,
        operation: :list
      )

    signed = SharedKey.apply(request, credential)

    assert signed.headers["Authorization"] =~ "SharedKey #{@account}:"
  end
end
