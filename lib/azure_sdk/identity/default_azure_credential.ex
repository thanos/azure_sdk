defmodule AzureSDK.Identity.DefaultAzureCredential do
  @moduledoc """
  Credential chain that tries multiple authentication methods in order.

  Default order:

  1. `EnvironmentCredential`
  2. `WorkloadIdentityCredential` when federated-token env vars are present
  3. `ManagedIdentityCredential`

  Short-circuits on the first successful token. Continues after
  `CredentialUnavailable` and other acquisition errors, returning the last
  error when the chain is exhausted.

  ## Fields

  * `:credentials` — ordered list of `TokenCredential` structs

  ## Examples

      iex> cred = AzureSDK.Identity.DefaultAzureCredential.new(env: %{})
      iex> length(cred.credentials) >= 2
      true
  """

  @behaviour AzureSDK.Identity.TokenCredential

  alias AzureSDK.Error

  alias AzureSDK.Identity.{
    EnvironmentCredential,
    ManagedIdentityCredential,
    TokenCredential,
    WorkloadIdentityCredential
  }

  @typedoc "Default Azure credential. See the module documentation for field meanings."
  @type t :: %__MODULE__{credentials: [TokenCredential.t()]}

  defstruct [:credentials]

  @doc """
  Creates a default Azure credential chain.

  ## Options

  * `:credentials` — explicit list of credentials (skips default discovery)
  * `:env` — passed to environment / workload discovery
  * `:managed_identity` — options for `ManagedIdentityCredential.new/1`

  ## Examples

      iex> cred = AzureSDK.Identity.DefaultAzureCredential.new(
      ...>   credentials: [AzureSDK.Identity.ManagedIdentityCredential.new()]
      ...> )
      iex> length(cred.credentials)
      1
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    credentials =
      Keyword.get_lazy(opts, :credentials, fn ->
        build_chain(opts)
      end)

    %__MODULE__{credentials: credentials}
  end

  @doc """
  Cache key `:default_azure_credential`.

  ## Examples

      iex> AzureSDK.Identity.DefaultAzureCredential.cache_key(
      ...>   AzureSDK.Identity.DefaultAzureCredential.new(env: %{})
      ...> )
      :default_azure_credential
  """
  @impl AzureSDK.Identity.TokenCredential
  def cache_key(%__MODULE__{}), do: :default_azure_credential

  @doc """
  Tries each credential in order until one returns `{:ok, token}`.

  ## Returns

  * `{:ok, %AzureSDK.Identity.AccessToken{}}`
  * `{:error, %AzureSDK.Error{}}` — last error from the chain (often
    `CredentialUnavailable` when nothing is configured)

  ## Examples

      iex> cred = AzureSDK.Identity.DefaultAzureCredential.new(
      ...>   credentials: [AzureSDK.Identity.EnvironmentCredential.new(env: %{})]
      ...> )
      iex> {:error, %{code: "CredentialUnavailable"}} =
      ...>   AzureSDK.Identity.DefaultAzureCredential.get_token(cred, ["https://storage.azure.com/.default"])
      iex> true
      true
  """
  @impl AzureSDK.Identity.TokenCredential
  def get_token(%__MODULE__{credentials: credentials}, scopes, opts \\ []) when is_list(scopes) do
    credentials
    |> Enum.reduce_while({:error, unavailable()}, fn cred, _acc ->
      case TokenCredential.get_token(cred, scopes, opts) do
        {:ok, _} = ok ->
          {:halt, ok}

        {:error, %Error{code: "CredentialUnavailable"} = error} ->
          {:cont, {:error, error}}

        {:error, error} ->
          {:cont, {:error, error}}
      end
    end)
  end

  defp build_chain(opts) do
    env = Keyword.get(opts, :env)
    mi_opts = Keyword.get(opts, :managed_identity, [])

    env_cred =
      if is_nil(env) do
        EnvironmentCredential.new()
      else
        EnvironmentCredential.new(env: env)
      end

    env_fun = env_reader(env)

    workload =
      case workload_from_env(env_fun) do
        nil -> []
        cred -> [cred]
      end

    [env_cred] ++ workload ++ [ManagedIdentityCredential.new(mi_opts)]
  end

  defp workload_from_env(env) do
    tenant = env.("AZURE_TENANT_ID")
    client_id = env.("AZURE_CLIENT_ID")
    token_file = env.("AZURE_FEDERATED_TOKEN_FILE")
    authority = env.("AZURE_AUTHORITY_HOST")

    if present?(tenant) and present?(client_id) and present?(token_file) do
      opts = [tenant_id: tenant, client_id: client_id, federated_token_file: token_file]
      opts = if present?(authority), do: Keyword.put(opts, :authority_host, authority), else: opts
      WorkloadIdentityCredential.new(opts)
    else
      nil
    end
  end

  defp env_reader(nil), do: &System.get_env/1
  defp env_reader(fun) when is_function(fun, 1), do: fun
  defp env_reader(map) when is_map(map), do: fn key -> Map.get(map, key) end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp unavailable do
    Error.new(
      code: "CredentialUnavailable",
      message: "DefaultAzureCredential found no working credential in the chain",
      service: :identity
    )
  end
end
