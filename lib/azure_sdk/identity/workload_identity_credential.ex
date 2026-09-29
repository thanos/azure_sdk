defmodule AzureSDK.Identity.WorkloadIdentityCredential do
  @moduledoc """
  Kubernetes workload identity (federated) credential.

  Reads a projected service-account token file and exchanges it for an Entra
  access token using the OAuth2 client assertion grant.

  ## Fields

  * `:tenant_id` - Entra tenant ID
  * `:client_id` - application client ID
  * `:federated_token_file` - path to the projected JWT file
  * `:authority_host` - login host; default `https://login.microsoftonline.com`

  ## Examples

      iex> cred = AzureSDK.Identity.WorkloadIdentityCredential.new(
      ...>   tenant_id: "t",
      ...>   client_id: "c",
      ...>   federated_token_file: "/var/run/secrets/token"
      ...> )
      iex> cred.federated_token_file
      "/var/run/secrets/token"
  """

  @behaviour AzureSDK.Identity.TokenCredential

  alias AzureSDK.Error
  alias AzureSDK.Identity.Http

  @default_authority "https://login.microsoftonline.com"

  @typedoc "Workload identity credential. See the module documentation for field meanings."
  @type t :: %__MODULE__{
          tenant_id: String.t(),
          client_id: String.t(),
          federated_token_file: String.t(),
          authority_host: String.t()
        }

  defstruct [:tenant_id, :client_id, :federated_token_file, :authority_host]

  @doc """
  Creates a workload identity credential.

  ## Options

  * `:tenant_id` (required)
  * `:client_id` (required)
  * `:federated_token_file` (required) - path to the federated token
  * `:authority_host` - defaults to the public cloud login host

  ## Errors

  Raises `KeyError` when a required option is missing.
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    %__MODULE__{
      tenant_id: Keyword.fetch!(opts, :tenant_id),
      client_id: Keyword.fetch!(opts, :client_id),
      federated_token_file: Keyword.fetch!(opts, :federated_token_file),
      authority_host: Keyword.get(opts, :authority_host, @default_authority)
    }
  end

  @doc """
  Cache key `{ :workload_identity, tenant_id, client_id }`.

  ## Examples

      iex> cred = AzureSDK.Identity.WorkloadIdentityCredential.new(
      ...>   tenant_id: "t", client_id: "c", federated_token_file: "/tmp/t"
      ...> )
      iex> AzureSDK.Identity.WorkloadIdentityCredential.cache_key(cred)
      {:workload_identity, "t", "c"}
  """
  @impl AzureSDK.Identity.TokenCredential
  def cache_key(%__MODULE__{tenant_id: tenant, client_id: client_id}) do
    {:workload_identity, tenant, client_id}
  end

  @doc """
  Reads the federated token file and exchanges it for an access token.

  ## Options

  * `:req_options` - extra Req options

  ## Returns

  * `{:ok, %AzureSDK.Identity.AccessToken{}}`
  * `{:error, %AzureSDK.Error{code: "FederatedTokenEmpty"}}` - empty file
  * `{:error, %AzureSDK.Error{code: "FederatedTokenUnavailable"}}` - unreadable file
  * `{:error, %AzureSDK.Error{}}` - token endpoint failure

  ## Examples

      iex> cred = AzureSDK.Identity.WorkloadIdentityCredential.new(
      ...>   tenant_id: "t",
      ...>   client_id: "c",
      ...>   federated_token_file: "/tmp/does-not-exist-azure-sdk-wi"
      ...> )
      iex> match?(
      ...>   {:error, %{code: "FederatedTokenUnavailable"}},
      ...>   AzureSDK.Identity.WorkloadIdentityCredential.get_token(cred, ["https://storage.azure.com/.default"])
      ...> )
      true
  """
  @impl AzureSDK.Identity.TokenCredential
  def get_token(%__MODULE__{} = credential, scopes, opts \\ []) when is_list(scopes) do
    with {:ok, assertion} <- read_token_file(credential.federated_token_file) do
      url = Http.token_url(credential.authority_host, credential.tenant_id)

      form = %{
        "client_id" => credential.client_id,
        "client_assertion" => assertion,
        "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        "grant_type" => "client_credentials",
        "scope" => Enum.join(scopes, " ")
      }

      Http.post_form(url, form, req_options: Keyword.get(opts, :req_options, []))
    end
  end

  defp read_token_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        token = String.trim(contents)

        if token == "" do
          {:error,
           Error.new(
             code: "FederatedTokenEmpty",
             message: "Federated token file is empty: #{path}",
             service: :identity
           )}
        else
          {:ok, token}
        end

      {:error, reason} ->
        {:error,
         Error.new(
           code: "FederatedTokenUnavailable",
           message: "Unable to read federated token file #{path}: #{inspect(reason)}",
           service: :identity,
           cause: reason
         )}
    end
  end
end
