defmodule ExAzure.Identity.DefaultAzureCredential do
  @moduledoc """
  Credential chain that tries multiple authentication methods in order.

  Planned for v0.2.0, inspired by `azure-identity` DefaultAzureCredential.
  """

  @behaviour ExAzure.Identity.Credential

  defstruct [:credentials]

  @type t :: %__MODULE__{credentials: list() | nil}

  @impl ExAzure.Identity.Credential
  @dialyzer {:nowarn_function, sign_request: 2}
  def sign_request(%__MODULE__{}, _request) do
    raise ArgumentError,
          "DefaultAzureCredential is not implemented in v0.1.0. See plans/identity-architecture.md"
  end
end
