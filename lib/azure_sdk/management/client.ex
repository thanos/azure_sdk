defmodule AzureSDK.Management.Client do
  @moduledoc false
  # Namespace reserved for v0.6.0 ARM client. See README.md#roadmap.

  defstruct [:subscription_id, :credential, :endpoint, :api_version]

  @spec new(keyword()) :: %__MODULE__{}
  def new(opts) do
    struct!(__MODULE__, opts)
  end
end
