defmodule AzureSDK.Storage.Blob.BlockTest do
  use ExUnit.Case, async: true

  doctest AzureSDK.Storage.Blob.Block

  alias AzureSDK.Storage.Blob.Block

  test "block ids are stable base64 of padded indexes" do
    assert Block.block_id(0) == Base.encode64("000000")
    assert Block.block_id(42) == Base.encode64("000042")
  end

  test "block list xml lists Latest entries" do
    xml = Block.block_list_xml(["aa", "bb"])
    assert xml =~ "<Latest>aa</Latest>"
    assert xml =~ "<Latest>bb</Latest>"
  end
end
