defmodule AzureSDK.VersionTest do
  use ExUnit.Case, async: true

  test "version matches mix project" do
    assert AzureSDK.version() == to_string(Mix.Project.config()[:version])
  end
end
