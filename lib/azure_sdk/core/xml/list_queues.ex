defmodule AzureSDK.Core.Xml.ListQueues do
  @moduledoc false

  import SweetXml

  alias AzureSDK.Core.Xml.Safe

  @type queue :: %{
          name: String.t(),
          metadata: %{String.t() => String.t()} | nil
        }

  @type page :: %{
          items: [queue()],
          marker: String.t() | nil
        }

  @doc false
  # `metadata` is parsed only when the request asked for it (`include=metadata`);
  # otherwise it is `nil`, so "not requested" is never mistaken for "empty".
  @spec parse_page(binary(), boolean()) :: page()
  def parse_page(xml, include_metadata? \\ false) do
    case Safe.run(fn -> parse_page_xml(xml, include_metadata?) end) do
      {:ok, page} -> page
      {:error, :invalid_xml} -> %{items: [], marker: nil}
    end
  end

  defp parse_page_xml(xml, include_metadata?) do
    items =
      xml
      |> xpath(~x"//Queues/Queue"l,
        name: ~x"./Name/text()"s,
        metadata: [~x"./Metadata/*"l, key: ~x"name(.)"s, value: ~x"string(.)"s]
      )
      |> Enum.map(fn item ->
        %{
          name: item.name,
          metadata: if(include_metadata?, do: Map.new(item.metadata, &{&1.key, &1.value}))
        }
      end)

    %{items: items, marker: xml |> xpath(~x"//NextMarker/text()"s) |> Safe.blank_to_nil()}
  end
end
