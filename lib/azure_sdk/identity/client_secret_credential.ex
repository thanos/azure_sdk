defmodule AzureSDK.Identity.ClientSecretCredential do
  @moduledoc """
  Client secret credential for Microsoft Entra ID.

  Acquires tokens with the OAuth2 client credentials grant against
  `{authority}/{tenant}/oauth2/v2.0/token`.

  ## Fields

  * `:tenant_id` — Microsoft Entra tenant (directory) ID
  * `:client_id` — application (client) ID
  * `:client_secret` — client secret value
  * `:authority_host` — login host; default `https://login.microsoftonline.com`

  ## Examples

      iex> cred = AzureSDK.Identity.ClientSecretCredential.new(
      ...>   tenant_id: "tenant",
      ...>   client_id: "client",
      ...>   client_secret: "secret"
      ...> )
      iex> cred.authority_host
      "https://login.microsoftonline.com"
  """

  @behaviour AzureSDK.Identity.TokenCredential

  alias AzureSDK.Identity.Http

  @default_authority "https://login.microsoftonline.com"

  @typedoc "Client secret credential. See the module documentation for field meanings."
  @type t :: %__MODULE__{
          tenant_id: String.t(),
          client_id: String.t(),
          client_secret: String.t(),
          authority_host: String.t()
        }

  defstruct [:tenant_id, :client_id, :client_secret, :authority_host]

  @doc """
  Creates a client secret credential.

  ## Options

  * `:tenant_id` (required) — Entra tenant ID
  * `:client_id` (required) — application client ID
  * `:client_secret` (required) — client secret
  * `:authority_host` — defaults to `https://login.microsoftonline.com`

  ## Returns

  `%AzureSDK.Identity.ClientSecretCredential{}`.

  ## Errors

  Raises `KeyError` when a required option is missing.

  ## Examples

      iex> AzureSDK.Identity.ClientSecretCredential.new(
      ...>   tenant_id: "t",
      ...>   client_id: "c",
      ...>   client_secret: "s",
      ...>   authority_host: "https://login.microsoftonline.us"
      ...> ).authority_host
      "https://login.microsoftonline.us"
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    %__MODULE__{
      tenant_id: Keyword.fetch!(opts, :tenant_id),
      client_id: Keyword.fetch!(opts, :client_id),
      client_secret: Keyword.fetch!(opts, :client_secret),
      authority_host: Keyword.get(opts, :authority_host, @default_authority)
    }
  end

  @doc """
  Cache key `{ :client_secret, tenant_id, client_id }` (secret excluded).

  ## Examples

      iex> cred = AzureSDK.Identity.ClientSecretCredential.new(
      ...>   tenant_id: "t", client_id: "c", client_secret: "s"
      ...> )
      iex> AzureSDK.Identity.ClientSecretCredential.cache_key(cred)
      {:client_secret, "t", "c"}
  """
  @impl AzureSDK.Identity.TokenCredential
  def cache_key(%__MODULE__{tenant_id: tenant, client_id: client_id}) do
    {:client_secret, tenant, client_id}
  end

  @doc """
  Requests an access token for `scopes` from Entra ID.

  ## Parameters

  * `credential` — client secret credential
  * `scopes` — OAuth scopes (joined with spaces in the token request)
  * `opts` — optional keyword list:
    * `:req_options` — extra Req options (for example `[plug: mock]` in tests)

  ## Returns

  * `{:ok, %AzureSDK.Identity.AccessToken{}}`
  * `{:error, %AzureSDK.Error{}}` — HTTP or parse failure (`service: :identity`)

  Does not raise for Entra HTTP errors.

  Prefer `AzureSDK.Identity.TokenCache.fetch/3` or a Storage client so tokens
  are cached. Direct `get_token/3` always hits the token endpoint.

      credential =
        AzureSDK.Identity.ClientSecretCredential.new(
          tenant_id: System.fetch_env!("AZURE_TENANT_ID"),
          client_id: System.fetch_env!("AZURE_CLIENT_ID"),
          client_secret: System.fetch_env!("AZURE_CLIENT_SECRET")
        )

      {:ok, token} =
        AzureSDK.Identity.TokenCredential.get_token(
          credential,
          ["https://storage.azure.com/.default"]
        )
  """
  @impl AzureSDK.Identity.TokenCredential
  def get_token(%__MODULE__{} = credential, scopes, opts \\ []) when is_list(scopes) do
    url =
      credential.authority_host
      |> String.trim_trailing("/")
      |> Kernel.<>("/#{credential.tenant_id}/oauth2/v2.0/token")

    form = %{
      "client_id" => credential.client_id,
      "client_secret" => credential.client_secret,
      "grant_type" => "client_credentials",
      "scope" => Enum.join(scopes, " ")
    }

    Http.post_form(url, form, req_options: Keyword.get(opts, :req_options, []))
  end
end
