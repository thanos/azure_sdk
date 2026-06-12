defmodule ExAzure.Identity.ManagedIdentityCredential do
  @moduledoc """
  Managed Identity credential for Azure-hosted workloads.

  Planned for v0.2.0. Will acquire tokens from the Azure Instance Metadata
  Service (IMDS) or workload identity endpoints.
  """

  @behaviour ExAzure.Identity.Credential

  defstruct [:client_id]

  @type t :: %__MODULE__{client_id: String.t() | nil}

  @doc false
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct!(__MODULE__, opts)
  end

  @impl ExAzure.Identity.Credential
  @dialyzer {:nowarn_function, sign_request: 2}
  def sign_request(%__MODULE__{}, _request) do
    raise RuntimeError,
          "ManagedIdentityCredential is not implemented in v0.1.0. See plans/identity-architecture.md"
  end
end
