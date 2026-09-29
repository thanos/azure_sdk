defmodule AzureSDK.Storage.Path do
  @moduledoc """
  Path helpers for Azure Storage resource URLs.

  Encodes path segments so names containing reserved characters (spaces,
  `?`, `#`, …) are safe in Shared Key signing and HTTP requests.

  ## Examples

      iex> AzureSDK.Storage.Path.join(["uploads", "a b.txt"])
      "/uploads/a%20b.txt"
  """

  @doc """
  Percent-encodes a single path segment, leaving unreserved characters intact.

  ## Parameters

  * `segment` — container name, blob name segment, or similar

  ## Examples

      iex> AzureSDK.Storage.Path.encode_segment("hello world")
      "hello%20world"
      iex> AzureSDK.Storage.Path.encode_segment("a/b")
      "a%2Fb"
  """
  @spec encode_segment(String.t()) :: String.t()
  def encode_segment(segment) when is_binary(segment) do
    URI.encode(segment, &URI.char_unreserved?/1)
  end

  @doc """
  Joins path segments into an absolute path starting with `/`.

  ## Parameters

  * `segments` — list of path segments in order

  ## Examples

      iex> AzureSDK.Storage.Path.join(["container", "folder/file.txt"])
      "/container/folder%2Ffile.txt"
  """
  @spec join([String.t()]) :: String.t()
  def join(segments) when is_list(segments) do
    "/" <> Enum.map_join(segments, "/", &encode_segment/1)
  end
end
