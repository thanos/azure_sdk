defmodule ExAzureTest do
  use ExUnit.Case, async: true

  test "version" do
    assert ExAzure.version() == "0.1.0"
  end
end
