defmodule AzureSDK.Identity.EnvironmentCredential do
  @moduledoc """
  Credential built from process environment variables.

  Supported combinations (first match wins):

  1. Client secret — `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`
  2. Workload identity — `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_FEDERATED_TOKEN_FILE`

  Optional: `AZURE_AUTHORITY_HOST` overrides the login host.

  ## Fields

  * `:inner` — resolved `TokenCredential`, or `nil` when env is incomplete

  ## Examples

      iex> cred = AzureSDK.Identity.EnvironmentCredential.new(env: %{})
      iex> cred.inner
      nil
  """

  @behaviour AzureSDK.Identity.TokenCredential

  alias AzureSDK.Error

  alias AzureSDK.Identity.{
    ClientSecretCredential,
    TokenCredential,
    WorkloadIdentityCredential
  }

  @typedoc "Environment credential. See the module documentation for field meanings."
  @type t :: %__MODULE__{inner: TokenCredential.t() | nil}

  defstruct [:inner]

  @doc """
  Builds a credential from the process environment.

  ## Options

  * `:env` — map or `String.t() -> String.t() | nil` function (defaults to `System.get_env/1`)

  ## Examples

      iex> cred = AzureSDK.Identity.EnvironmentCredential.new(
      ...>   env: %{
      ...>     "AZURE_TENANT_ID" => "t",
      ...>     "AZURE_CLIENT_ID" => "c",
      ...>     "AZURE_CLIENT_SECRET" => "s"
      ...>   }
      ...> )
      iex> match?(%AzureSDK.Identity.ClientSecretCredential{}, cred.inner)
      true
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    env = env_fun(Keyword.get(opts, :env))

    %__MODULE__{inner: resolve(env)}
  end

  @doc """
  Cache key wrapping the inner credential key, or `{:environment, :unconfigured}`.

  ## Examples

      iex> AzureSDK.Identity.EnvironmentCredential.cache_key(
      ...>   AzureSDK.Identity.EnvironmentCredential.new(env: %{})
      ...> )
      {:environment, :unconfigured}
  """
  @impl AzureSDK.Identity.TokenCredential
  def cache_key(%__MODULE__{inner: nil}), do: {:environment, :unconfigured}

  def cache_key(%__MODULE__{inner: inner}) do
    {:environment, TokenCredential.cache_key(inner)}
  end

  @doc """
  Delegates to the inner credential, or returns `CredentialUnavailable`.

  ## Returns

  * `{:ok, token}` when an inner credential is configured and succeeds
  * `{:error, %AzureSDK.Error{code: "CredentialUnavailable"}}` when env is incomplete
  * `{:error, %AzureSDK.Error{}}` from the inner credential otherwise

  ## Examples

      iex> cred = AzureSDK.Identity.EnvironmentCredential.new(env: %{})
      iex> {:error, %{code: "CredentialUnavailable"}} =
      ...>   AzureSDK.Identity.EnvironmentCredential.get_token(cred, ["https://storage.azure.com/.default"], [])
      iex> true
      true
  """
  @impl AzureSDK.Identity.TokenCredential
  def get_token(%__MODULE__{inner: nil}, _scopes, _opts) do
    {:error,
     Error.new(
       code: "CredentialUnavailable",
       message:
         "EnvironmentCredential requires AZURE_TENANT_ID, AZURE_CLIENT_ID, and either AZURE_CLIENT_SECRET or AZURE_FEDERATED_TOKEN_FILE",
       service: :identity
     )}
  end

  def get_token(%__MODULE__{inner: inner}, scopes, opts) do
    TokenCredential.get_token(inner, scopes, opts)
  end

  defp resolve(env) do
    tenant = env.("AZURE_TENANT_ID")
    client_id = env.("AZURE_CLIENT_ID")
    secret = env.("AZURE_CLIENT_SECRET")
    token_file = env.("AZURE_FEDERATED_TOKEN_FILE")
    authority = env.("AZURE_AUTHORITY_HOST")

    cond do
      configured?(tenant, client_id, secret) ->
        build_client_secret(tenant, client_id, secret, authority)

      configured?(tenant, client_id, token_file) ->
        build_workload(tenant, client_id, token_file, authority)

      true ->
        nil
    end
  end

  defp configured?(a, b, c), do: present?(a) and present?(b) and present?(c)

  defp build_client_secret(tenant, client_id, secret, authority) do
    [tenant_id: tenant, client_id: client_id, client_secret: secret]
    |> maybe_authority(authority)
    |> ClientSecretCredential.new()
  end

  defp build_workload(tenant, client_id, token_file, authority) do
    [tenant_id: tenant, client_id: client_id, federated_token_file: token_file]
    |> maybe_authority(authority)
    |> WorkloadIdentityCredential.new()
  end

  defp maybe_authority(opts, authority) do
    if present?(authority), do: Keyword.put(opts, :authority_host, authority), else: opts
  end

  defp env_fun(nil), do: &System.get_env/1
  defp env_fun(fun) when is_function(fun, 1), do: fun

  defp env_fun(map) when is_map(map) do
    fn key -> Map.get(map, key) end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
