defmodule ExAzure.Core.Xml.Error do
  @moduledoc false

  import SweetXml

  @type parsed :: %{
          optional(:code) => String.t() | nil,
          optional(:message) => String.t() | nil,
          optional(:details) => map()
        }

  @doc false
  @spec parse(binary() | nil) :: parsed()
  def parse(nil), do: %{}
  def parse(""), do: %{}

  def parse(xml) when is_binary(xml) do
    xml
    |> xpath(
      ~x"/Error"l,
      code: ~x"./Code/text()"s,
      message: ~x"./Message/text()"s
    )
    |> case do
      [] ->
        %{}

      [error | _] ->
        %{
          code: blank_to_nil(error[:code]),
          message: blank_to_nil(error[:message]),
          details: Map.drop(error, [:code, :message])
        }
    end
  rescue
    _ -> %{}
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
