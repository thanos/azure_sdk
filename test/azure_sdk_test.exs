defmodule AzureSDKTest do
  use ExUnit.Case, async: true

  test "version" do
    assert AzureSDK.version() == "0.3.0"
  end
end
