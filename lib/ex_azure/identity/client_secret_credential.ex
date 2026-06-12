defmodule ExAzure.Identity.ClientSecretCredential do
  @moduledoc """
  Client secret credential for Azure Active Directory.

  Planned for v0.2.0. This module documents the interface and will acquire
  OAuth2 tokens via the Microsoft identity platform.
  """

  @behaviour ExAzure.Identity.Credential

  defstruct [:tenant_id, :client_id, :client_secret]

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          client_id: String.t(),
          client_secret: String.t()
        }

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    struct!(__MODULE__, opts)
  end

  @impl ExAzure.Identity.Credential
  @dialyzer {:nowarn_function, sign_request: 2}
  def sign_request(%__MODULE__{}, _request) do
    raise ArgumentError,
          "ClientSecretCredential is not implemented in v0.1.0. See plans/identity-architecture.md"
  end
end
