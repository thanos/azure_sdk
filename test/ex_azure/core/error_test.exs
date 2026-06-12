defmodule ExAzure.Core.ErrorTest do
  use ExUnit.Case, async: true

  alias ExAzure.Error

  test "builds errors from azure xml responses" do
    body = """
    <?xml version="1.0" encoding="utf-8"?>
    <Error>
      <Code>BlobNotFound</Code>
      <Message>The specified blob does not exist.</Message>
    </Error>
    """

    error =
      Error.from_response(:blob, 404, %{"x-ms-request-id" => "req-123"}, body)

    assert error.code == "BlobNotFound"
    assert error.message == "The specified blob does not exist."
    assert error.request_id == "req-123"
    assert error.service == :blob
  end

  test "falls back to default messages" do
    assert Error.from_response(:blob, 401, %{}, nil).message == "Unauthorized"
    assert Error.from_response(:blob, 418, %{}, nil).message == "HTTP 418"
  end

  test "builds errors from exceptions" do
    error = Error.from_exception(:blob, %RuntimeError{message: "connection reset"})

    assert error.message == "connection reset"
    assert error.service == :blob
    assert %RuntimeError{} = error.cause
  end

  test "creates custom errors" do
    assert %Error{code: "Test", message: "boom"} =
             Error.new(code: "Test", message: "boom")
  end
end
