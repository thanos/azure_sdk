defmodule AzureSDKTest do
  use ExUnit.Case, async: true

  test "version" do
    assert AzureSDK.version() == "0.4.0"
  end
end
