defmodule ExAzure.Core.Xml.ListBlobs do
  @moduledoc false

  import SweetXml

  alias ExAzure.Core.Xml.Safe

  @type blob :: %{
          name: String.t(),
          properties: map(),
          metadata: map()
        }

  @type page :: %{
          items: [blob()],
          marker: String.t() | nil
        }

  @doc false
  @spec parse(binary()) :: [blob()]
  def parse(xml) do
    case parse_page(xml) do
      %{items: items} -> items
    end
  end

  @doc false
  @spec parse_page(binary()) :: page()
  def parse_page(xml) do
    case Safe.run(fn -> parse_page_xml(xml) end) do
      {:ok, page} -> page
      {:error, :invalid_xml} -> %{items: [], marker: nil}
    end
  end

  defp parse_page_xml(xml) do
    items =
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

    marker =
      xml
      |> xpath(~x"//NextMarker/text()"s)
      |> blank_to_nil()

    %{items: items, marker: marker}
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
