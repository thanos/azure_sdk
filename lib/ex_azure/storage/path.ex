defmodule ExAzure.Storage.Path do
  @moduledoc false

  @doc false
  @spec encode_segment(String.t()) :: String.t()
  def encode_segment(segment) when is_binary(segment) do
    URI.encode(segment, &URI.char_unreserved?/1)
  end

  @doc false
  @spec join([String.t()]) :: String.t()
  def join(segments) when is_list(segments) do
    "/" <> Enum.map_join(segments, "/", &encode_segment/1)
  end
end
