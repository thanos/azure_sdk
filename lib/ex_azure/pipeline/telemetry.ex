defmodule ExAzure.Pipeline.Telemetry do
  @moduledoc false

  @doc """
  Attaches request metadata for downstream telemetry emission.
  """
  @spec apply(ExAzure.Core.Request.t(), map()) :: ExAzure.Core.Request.t()
  def apply(%ExAzure.Core.Request{} = request, metadata) do
    ExAzure.Core.Telemetry.emit_attempt(metadata)
    request
  end
end
