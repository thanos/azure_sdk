defmodule AzureSDK.Core.Xml.ListQueues do
  @moduledoc false

  import SweetXml

  alias AzureSDK.Core.Xml.Safe

  @type queue :: %{
          name: String.t(),
          metadata: map()
        }

  @type page :: %{
          items: [queue()],
          marker: String.t() | nil
        }

  @doc false
  @spec parse(binary()) :: [queue()]
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
        ~x"//Queues/Queue"l,
        name: ~x"./Name/text()"s
      )
      |> Enum.map(fn item ->
        %{
          name: item[:name],
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
end
