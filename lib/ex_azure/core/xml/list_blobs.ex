defmodule ExAzure.Core.Xml.ListBlobs do
  @moduledoc false

  import SweetXml

  @type blob :: %{
          name: String.t(),
          properties: map(),
          metadata: map()
        }

  @doc false
  @spec parse(binary()) :: [blob()]
  def parse(xml) do
    xml
    |> xpath(
      ~x"//Blobs/Blob"l,
      name: ~x"./Name/text()"s,
      content_type: ~x"./Properties/Content-Type/text()"s,
      content_length: ~x"./Properties/Content-Length/text()"s,
      etag: ~x"./Properties/Etag/text()"s,
      last_modified: ~x"./Properties/Last-Modified/text()"s,
      blob_type: ~x"./Properties/BlobType/text()"s
    )
    |> Enum.map(fn item ->
      %{
        name: item[:name],
        properties: %{
          content_type: blank_to_nil(item[:content_type]),
          content_length: parse_integer(item[:content_length]),
          etag: blank_to_nil(item[:etag]),
          last_modified: blank_to_nil(item[:last_modified]),
          blob_type: blank_to_nil(item[:blob_type])
        },
        metadata: %{}
      }
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil

  defp parse_integer(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end
end
