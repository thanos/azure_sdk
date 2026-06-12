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
          },
          metadata: %{path_style: false}
        )

      string = SharedKey.string_to_sign(request, account)
      assert String.ends_with?(string, "/#{account}/#{container}/#{blob}")
    end
  end

  @tag :property
  property "canonicalized x-ms headers are sorted and lowercased" do
    check all(
            version <- string(:alphanumeric, min_length: 4, max_length: 8),
            date <- string(:printable, min_length: 10, max_length: 30)
          ) do
      request =
        Request.new(
          method: :get,
          path: "/container",
          headers: %{
            "x-ms-version" => version,
            "x-ms-date" => date
          }
        )

      string = SharedKey.string_to_sign(request, "acct")
      assert string =~ "x-ms-date:#{date}\nx-ms-version:#{version}"
    end
  end
end
