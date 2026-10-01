defmodule AzureSDK.Core.Xml.ListQueues do
  @moduledoc """
  Parses Azure Queue Storage List Queues XML responses.

  Used by `AzureSDK.Storage.Queue.list_page/2`. Prefer the Storage APIs unless
  you are inspecting raw service responses.

  ## Page map (`t:page/0`)

      %{items: [%{name: "jobs", metadata: nil}], marker: nil}
      %{items: [%{name: "jobs", metadata: %{"env" => "dev"}}], marker: "next"}

  `:metadata` is parsed only when `include_metadata?` is `true`; otherwise it is
  `nil`, so "not requested" is never mistaken for "empty".
  """

  import SweetXml

  alias AzureSDK.Core.Xml.Safe

  @typedoc """
  One queue in a list page.

  * `:name` - queue name
  * `:metadata` - user metadata when `include_metadata?` is `true`, otherwise `nil`
  """
  @type queue :: %{
          name: String.t(),
          metadata: %{String.t() => String.t()} | nil
        }

  @typedoc """
  One list page.

  * `:items` - `t:queue/0` entries
  * `:marker` - continuation token, or `nil` when finished
  """
  @type page :: %{
          items: [queue()],
          marker: String.t() | nil
        }

  @doc """
  Parses a List Queues XML body into a page.

  Invalid XML yields an empty page (`items: []`, `marker: nil`) rather than an
  error tuple, matching the Storage list helpers' tolerance for empty bodies.

  ## Parameters

  * `xml` - response body
  * `include_metadata?` - when `true`, each item's `:metadata` is a map
    (default `false`, which leaves `:metadata` as `nil`)

  ## Returns

  A `t:page/0` map.

  ## Examples

      iex> xml = ~s(<EnumerationResults><Queues><Queue><Name>jobs</Name></Queue></Queues><NextMarker>next</NextMarker></EnumerationResults>)
      iex> AzureSDK.Core.Xml.ListQueues.parse_page(xml)
      %{items: [%{name: "jobs", metadata: nil}], marker: "next"}

      iex> xml = ~s(<EnumerationResults><Queues><Queue><Name>jobs</Name><Metadata><env>dev</env></Metadata></Queue></Queues><NextMarker></NextMarker></EnumerationResults>)
      iex> AzureSDK.Core.Xml.ListQueues.parse_page(xml, true)
      %{items: [%{name: "jobs", metadata: %{"env" => "dev"}}], marker: nil}

      iex> AzureSDK.Core.Xml.ListQueues.parse_page("not-xml")
      %{items: [], marker: nil}
  """
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
