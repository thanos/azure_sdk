defmodule AzureSDK.Core.Xml.Safe do
  @moduledoc false

  @doc false
  @spec run((-> term())) :: {:ok, term()} | {:error, :invalid_xml}
  def run(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  catch
    :exit, _ -> {:error, :invalid_xml}
  end

  @doc false
  # XPath string results are "" when a node is missing; callers want nil.
  @spec blank_to_nil(String.t() | nil) :: String.t() | nil
  def blank_to_nil(""), do: nil
  def blank_to_nil(value), do: value
end
