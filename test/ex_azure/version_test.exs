defmodule ExAzure.VersionTest do
  use ExUnit.Case, async: true

  test "version matches mix project" do
    assert ExAzure.version() == to_string(Mix.Project.config()[:version])
  end
end
