defmodule AzureSDK.Pipeline.BearerTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Core.Request
  alias AzureSDK.Identity.AccessToken
  alias AzureSDK.Pipeline.Bearer

  test "sets Authorization bearer header" do
    token = AccessToken.new("abc", DateTime.add(DateTime.utc_now(), 60, :second))
    request = Request.new(method: :get, path: "/", service: :blob, operation: :get)

    authorized = Bearer.apply(request, token)
    assert authorized.headers["Authorization"] == "Bearer abc"
  end
end
