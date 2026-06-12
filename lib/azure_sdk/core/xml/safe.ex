defmodule AzureSDK.Core.Xml.Safe do
  @moduledoc false

  @doc false
  @spec run((-> term())) :: {:ok, term()} | {:error, :invalid_xml}
  def run(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  catch
    :exit, _ -> {:error, :invalid_xml}
  end
end
