defmodule AzureSDK.Pipeline.Telemetry do
  @moduledoc false

  @doc """
  Attaches request metadata for downstream telemetry emission.
  """
  @spec apply(AzureSDK.Core.Request.t(), map()) :: AzureSDK.Core.Request.t()
  def apply(%AzureSDK.Core.Request{} = request, metadata) do
    AzureSDK.Core.Telemetry.emit_attempt(metadata)
    request
  end
end
