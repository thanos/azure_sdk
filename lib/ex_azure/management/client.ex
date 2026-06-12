defmodule ExAzure.Management.Client do
  @moduledoc """
  Azure Resource Manager (management plane) client.

  Planned for v0.5.0. See `plans/data-plane-vs-management-plane.md`.
  """

  defstruct [:subscription_id, :credential, :endpoint, :api_version]

  @type t :: %__MODULE__{
          subscription_id: String.t() | nil,
          credential: ExAzure.Identity.Credential.t() | nil,
          endpoint: String.t() | nil,
          api_version: String.t() | nil
        }

  @doc """
  Creates a management plane client. Full ARM support is planned for v0.5.0.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    struct!(__MODULE__, opts)
  end
end
