defmodule AzureSDK.Storage.PathTest do
  use ExUnit.Case, async: true

  alias AzureSDK.Storage.Path

  test "encodes reserved characters in path segments" do
    assert Path.encode_segment("file?v=1.txt") == "file%3Fv%3D1.txt"
    assert Path.encode_segment("file#1.txt") == "file%231.txt"
    assert Path.encode_segment("a b.txt") == "a%20b.txt"
  end

  test "joins encoded segments preserving virtual directories" do
    assert Path.join(["uploads", "dir", "sub#1.txt"]) == "/uploads/dir/sub%231.txt"
    assert Path.join(["uploads", "file?v=1.txt"]) == "/uploads/file%3Fv%3D1.txt"
  end
end
