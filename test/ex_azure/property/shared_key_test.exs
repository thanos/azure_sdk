defmodule ExAzure.Property.SharedKeyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExAzure.Core.Request
  alias ExAzure.Pipeline.SharedKey

  @tag :property
  property "string_to_sign always ends with canonicalized resource path" do
    check all(
            account <- string(:alphanumeric, min_length: 3, max_length: 20),
            container <- string(:alphanumeric, min_length: 1, max_length: 20),
            blob <- string(:alphanumeric, min_length: 1, max_length: 20)
          ) do
      request =
        Request.new(
          method: :get,
          path: "/#{container}/#{blob}",
          headers: %{
            "x-ms-date" => "Wed, 01 Jan 2025 00:00:00 GMT",
            "x-ms-version" => "2024-11-04"
          }
        )

      string = SharedKey.string_to_sign(request, account)
      assert String.ends_with?(string, "/#{account}/#{container}/#{blob}")
    end
  end
end
