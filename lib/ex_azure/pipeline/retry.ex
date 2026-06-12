defmodule ExAzure.Pipeline.Retry do
  @moduledoc false

  @doc """
  Placeholder middleware module. Retry logic is orchestrated by
  `ExAzure.Core.Pipeline` and `ExAzure.Core.Retry`.
  """
  @spec policy() :: ExAzure.Core.Retry.policy()
  def policy, do: ExAzure.Core.Retry.default_policy()
end
