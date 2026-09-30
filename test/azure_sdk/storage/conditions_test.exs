defmodule AzureSDK.Storage.ConditionsTest do
  use ExUnit.Case, async: true

  doctest AzureSDK.Storage.Conditions

  alias AzureSDK.Storage.Conditions

  test "builds conditional and lease headers" do
    assert Conditions.headers(
             if_match: "\"1\"",
             if_none_match: "*",
             lease_id: "lease-1"
           ) == %{
             "If-Match" => "\"1\"",
             "If-None-Match" => "*",
             "x-ms-lease-id" => "lease-1"
           }
  end
end
