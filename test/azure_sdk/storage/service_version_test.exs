defmodule AzureSDK.Storage.ServiceVersionTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Storage.ServiceVersion

  test "default is validated latest" do
    assert ServiceVersion.default() == "2024-11-04"
    assert ServiceVersion.default() in ServiceVersion.known_versions()
  end

  test "validate!/1 rejects unknown versions" do
    assert_raise ArgumentError, fn -> ServiceVersion.validate!("1999-01-01") end
  end
end
