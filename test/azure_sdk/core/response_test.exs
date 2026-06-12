defmodule AzureSDK.Core.ResponseTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Core.{Request, Response}

  test "normalizes req responses" do
    req_response = %Req.Response{
      status: 200,
      headers: %{"etag" => ["\"0x1\""]},
      body: "payload"
    }

    request = Request.new(method: :get, path: "/")
    response = Response.from_req(req_response, request)

    assert response.status == 200
    assert response.body == "payload"
    assert response.headers["etag"] == "\"0x1\""
    assert response.request == request
    assert Response.success?(response)
  end

  test "identifies non-success responses" do
    refute Response.success?(%Response{status: 404})
  end
end
