defmodule AzureSDK.Core.RequestTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Core.Request

  test "builds and updates requests" do
    request =
      Request.new(
        method: :put,
        path: "/container/blob",
        query: [{"comp", "metadata"}],
        headers: %{"x-ms-version" => "2021-08-06"}
      )

    request =
      request
      |> Request.put_header("Content-Type", "text/plain")
      |> Request.merge_headers(%{"x-ms-meta-env" => "test"})
      |> Request.append_query([{"timeout", "30"}])

    assert request.method == :put
    assert request.headers["Content-Type"] == "text/plain"
    assert request.headers["x-ms-meta-env"] == "test"
    assert request.query == [{"comp", "metadata"}, {"timeout", "30"}]
    assert Request.url_path(request) == "/container/blob?comp=metadata&timeout=30"
  end
end
