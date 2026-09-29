defmodule AzureSDK.Identity.SharedKeyCredential do
  @moduledoc """
  Shared Key credential for Azure Storage services.

  Signs requests with HMAC-SHA256 per the Azure Storage Shared Key specification.
  Path-style endpoints (Azurite) require `request.metadata.path_style: true`,
  which `AzureSDK.Storage.Client` sets automatically when appropriate.

  ## Fields

  * `:account` - storage account name
  * `:key` - Base64-encoded account access key (hidden from `inspect/2`)

  ## Examples

      iex> cred = AzureSDK.Identity.SharedKeyCredential.new(
      ...>   "devstoreaccount1",
      ...>   "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="
      ...> )
      iex> cred.account
      "devstoreaccount1"
  """

  @behaviour AzureSDK.Identity.Credential

  @typedoc "Shared Key credential. See the module documentation for field meanings."
  @type t :: %__MODULE__{
          account: String.t(),
          key: String.t()
        }

  @derive {Inspect, except: [:key]}
  defstruct [:account, :key]

  @doc """
  Creates a Shared Key credential.

  ## Parameters

  * `account` - storage account name
  * `key` - Base64-encoded access key (not the raw secret bytes)

  ## Returns

  `%AzureSDK.Identity.SharedKeyCredential{}`.

  ## Examples

      iex> AzureSDK.Identity.SharedKeyCredential.new("acct", Base.encode64("sixteen-byte-key!"))
      %AzureSDK.Identity.SharedKeyCredential{account: "acct", key: "c2l4dGVlbi1ieXRlLWtleSE="}
  """
  @spec new(String.t(), String.t()) :: t()
  def new(account, key) when is_binary(account) and is_binary(key) do
    %__MODULE__{account: account, key: key}
  end

  @doc """
  Signs the request with a Shared Key `Authorization` header.

  ## Returns

  * `{:ok, request}` - signed request
  * `{:error, %AzureSDK.Error{code: "InvalidCredential"}}` - the key is not
    valid Base64

  Does not raise.

  ## Examples

      iex> cred = AzureSDK.Identity.SharedKeyCredential.new("acct", Base.encode64("sixteen-byte-key!"))
      iex> req = AzureSDK.Core.Request.new(
      ...>   method: :get,
      ...>   path: "/c",
      ...>   headers: %{"x-ms-date" => "Wed, 01 Jan 2025 00:00:00 GMT", "x-ms-version" => "2021-08-06"},
      ...>   metadata: %{path_style: false}
      ...> )
      iex> {:ok, signed} = AzureSDK.Identity.SharedKeyCredential.authorize_request(cred, req)
      iex> String.starts_with?(signed.headers["Authorization"], "SharedKey acct:")
      true
  """
  @impl AzureSDK.Identity.Credential
  def authorize_request(%__MODULE__{} = credential, request) do
    case Base.decode64(credential.key) do
      {:ok, _} ->
        {:ok, AzureSDK.Pipeline.SharedKey.apply(request, credential)}

      :error ->
        {:error,
         AzureSDK.Error.new(
           code: "InvalidCredential",
           message: "Shared Key for account #{inspect(credential.account)} is not valid Base64",
           service: request.service
         )}
    end
  end
end
