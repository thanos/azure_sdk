defmodule AzureSDK.Identity.ManagedIdentityCredential do
  @moduledoc """
  Managed Identity credential for Azure-hosted workloads.

  Acquires tokens from the Instance Metadata Service (IMDS) at
  `http://169.254.169.254/metadata/identity/oauth2/token` by default.

  ## Fields

  * `:client_id` - optional user-assigned managed identity client ID
  * `:endpoint` - IMDS token URL (override in tests)

  ## Examples

      iex> cred = AzureSDK.Identity.ManagedIdentityCredential.new(client_id: "mi-id")
      iex> cred.client_id
      "mi-id"
  """

  @behaviour AzureSDK.Identity.TokenCredential

  alias AzureSDK.Identity.Http

  @default_endpoint "http://169.254.169.254/metadata/identity/oauth2/token"
  @api_version "2018-02-01"

  @typedoc "Managed identity credential. See the module documentation for field meanings."
  @type t :: %__MODULE__{
          client_id: String.t() | nil,
          endpoint: String.t()
        }

  defstruct [:client_id, :endpoint]

  @doc """
  Creates a managed identity credential.

  ## Options

  * `:client_id` - user-assigned identity client ID (`nil` for system-assigned)
  * `:endpoint` - IMDS endpoint; defaults to the Azure IMDS URL

  ## Examples

      iex> cred = AzureSDK.Identity.ManagedIdentityCredential.new()
      iex> String.contains?(cred.endpoint, "169.254.169.254")
      true
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    %__MODULE__{
      client_id: Keyword.get(opts, :client_id),
      endpoint: Keyword.get(opts, :endpoint, @default_endpoint)
    }
  end

  @doc """
  Cache key `{ :managed_identity, client_id }`.

  ## Examples

      iex> AzureSDK.Identity.ManagedIdentityCredential.cache_key(
      ...>   AzureSDK.Identity.ManagedIdentityCredential.new()
      ...> )
      {:managed_identity, nil}
  """
  @impl AzureSDK.Identity.TokenCredential
  def cache_key(%__MODULE__{client_id: client_id}) do
    {:managed_identity, client_id}
  end

  @doc """
  Requests an access token from IMDS.

  IMDS accepts a single resource, so exactly one scope is required. Scopes such
  as `https://storage.azure.com/.default` are converted to an IMDS `resource`
  by stripping a trailing `/.default`.

  ## Options

  * `:req_options` - extra Req options (defaults include `receive_timeout: 1_000`
    and `connect_options: [timeout: 1_000]` so an unreachable IMDS fails fast)

  ## Returns

  * `{:ok, %AzureSDK.Identity.AccessToken{}}`
  * `{:error, %AzureSDK.Error{code: "CredentialUnavailable"}}` when IMDS is unreachable
  * `{:error, %AzureSDK.Error{code: "InvalidScope"}}` when `scopes` does not hold exactly one scope
  * `{:error, %AzureSDK.Error{}}` for other IMDS HTTP failures

  Only succeeds on hosts that expose IMDS at `169.254.169.254` (Azure VMs,
  VM scale sets, AKS nodes). App Service and Functions use a different
  endpoint (`IDENTITY_ENDPOINT`) that this credential does not support yet.
  Does not raise for expected acquisition failures.

  ## Examples

      # On a non-Azure host, IMDS is unreachable:
      cred = AzureSDK.Identity.ManagedIdentityCredential.new()
      {:error, %{code: "CredentialUnavailable"}} =
        AzureSDK.Identity.ManagedIdentityCredential.get_token(
          cred,
          ["https://storage.azure.com/.default"]
        )
  """
  @impl AzureSDK.Identity.TokenCredential
  def get_token(credential, scopes, opts \\ [])

  def get_token(%__MODULE__{} = credential, [scope], opts) when is_binary(scope) do
    query =
      [{"api-version", @api_version}, {"resource", resource_from_scope(scope)}]
      |> maybe_put_client_id(credential.client_id)

    url = credential.endpoint <> "?" <> URI.encode_query(query)

    req_options =
      opts
      |> Keyword.get(:req_options, [])
      |> Keyword.put_new(:receive_timeout, 1_000)
      |> Keyword.put_new(:connect_options, timeout: 1_000)

    case Http.get_json(url,
           headers: [{"Metadata", "true"}],
           req_options: req_options
         ) do
      {:ok, _} = ok ->
        ok

      {:error, %AzureSDK.Error{cause: %Req.TransportError{}} = error} ->
        {:error,
         AzureSDK.Error.new(
           code: "CredentialUnavailable",
           message: "Managed identity endpoint is unreachable",
           service: :identity,
           cause: error.cause
         )}

      {:error, _} = error ->
        error
    end
  end

  def get_token(%__MODULE__{}, scopes, _opts) when is_list(scopes) do
    {:error,
     AzureSDK.Error.new(
       code: "InvalidScope",
       message: "ManagedIdentityCredential requires exactly one scope, got #{length(scopes)}",
       service: :identity
     )}
  end

  defp resource_from_scope(scope) do
    String.replace_suffix(scope, "/.default", "")
  end

  defp maybe_put_client_id(query, nil), do: query
  defp maybe_put_client_id(query, client_id), do: query ++ [{"client_id", client_id}]
end
