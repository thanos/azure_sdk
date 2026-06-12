defmodule AzureSDK.Identity.SharedKeyCredential do
  @moduledoc """
  Shared Key credential for Azure Storage services.

      credential =
        AzureSDK.Identity.SharedKeyCredential.new(
          "myaccount",
          storage_access_key
        )
  """

  @behaviour AzureSDK.Identity.Credential

  defstruct [:account, :key]

  @type t :: %__MODULE__{
          account: String.t(),
          key: String.t()
        }

  @doc """
  Creates a Shared Key credential.
  """
  @spec new(String.t(), String.t()) :: t()
  def new(account, key) when is_binary(account) and is_binary(key) do
    %__MODULE__{account: account, key: key}
  end

  @impl AzureSDK.Identity.Credential
  def sign_request(%__MODULE__{} = credential, request) do
    AzureSDK.Pipeline.SharedKey.apply(request, credential)
  end
end
