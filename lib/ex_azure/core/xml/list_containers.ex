defmodule ExAzure.Core.Xml.ListContainers do
  @moduledoc false

  import SweetXml

  @type container :: %{
          name: String.t(),
          properties: map()
        }

  @doc false
  @spec parse(binary()) :: [container()]
  def parse(xml) do
    xml
    |> xpath(
      ~x"//Containers/Container"l,
      name: ~x"./Name/text()"s,
      last_modified: ~x"./Properties/Last-Modified/text()"s,
      etag: ~x"./Properties/Etag/text()"s,
      lease_status: ~x"./Properties/LeaseStatus/text()"s,
      lease_state: ~x"./Properties/LeaseState/text()"s,
      public_access: ~x"./Properties/PublicAccess/text()"s
    )
    |> Enum.map(fn item ->
      %{
        name: item[:name],
        properties: %{
          last_modified: blank_to_nil(item[:last_modified]),
          etag: blank_to_nil(item[:etag]),
          lease_status: blank_to_nil(item[:lease_status]),
          lease_state: blank_to_nil(item[:lease_state]),
          public_access: blank_to_nil(item[:public_access])
        }
      }
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
