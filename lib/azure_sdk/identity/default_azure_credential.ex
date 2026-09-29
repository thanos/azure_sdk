defmodule AzureSDK.Identity.DefaultAzureCredential do
  @moduledoc """
  Credential chain that tries multiple authentication methods in order.

  Default order:

  1. `EnvironmentCredential` (client secret, or workload identity when
     `AZURE_FEDERATED_TOKEN_FILE` is set)
  2. `ManagedIdentityCredential`

  Returns the first successful token. Moves to the next credential only on
  `CredentialUnavailable`; any other error (for example `invalid_client` from
  Entra) stops the chain and is returned as is, so a misconfigured credential
  is not hidden by a later one.

  ## Fields

  * `:credentials` - ordered list of `TokenCredential` structs

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
    TokenCredential
  }

  @typedoc "Default Azure credential. See the module documentation for field meanings."
  @type t :: %__MODULE__{credentials: [TokenCredential.t()]}

  defstruct [:credentials]

  @doc """
  Creates a default Azure credential chain.

  ## Options

  * `:credentials` - explicit list of credentials (skips default discovery)
  * `:env` - passed to `EnvironmentCredential.new/1`
  * `:managed_identity` - options for `ManagedIdentityCredential.new/1`

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
  Cache key built from the cache keys of every credential in the chain.

  Two chains share cached tokens only when they contain the same identities.

  ## Examples

      iex> AzureSDK.Identity.DefaultAzureCredential.cache_key(
      ...>   AzureSDK.Identity.DefaultAzureCredential.new(
      ...>     credentials: [AzureSDK.Identity.ManagedIdentityCredential.new(client_id: "mi")]
      ...>   )
      ...> )
      {:default_azure_credential, [{:managed_identity, "mi"}]}
  """
  @impl AzureSDK.Identity.TokenCredential
  def cache_key(%__MODULE__{credentials: credentials}) do
    {:default_azure_credential, Enum.map(credentials, &TokenCredential.cache_key/1)}
  end

  @doc """
  Tries each credential in order until one returns `{:ok, token}`.

  ## Returns

  * `{:ok, %AzureSDK.Identity.AccessToken{}}`
  * `{:error, %AzureSDK.Error{}}` - the first error that is not
    `CredentialUnavailable`, or the last `CredentialUnavailable` when no
    credential in the chain is usable

  ## Examples

      iex> cred = AzureSDK.Identity.DefaultAzureCredential.new(
      ...>   credentials: [AzureSDK.Identity.EnvironmentCredential.new(env: %{})]
      ...> )
      iex> match?(
      ...>   {:error, %{code: "CredentialUnavailable"}},
      ...>   AzureSDK.Identity.DefaultAzureCredential.get_token(cred, ["https://storage.azure.com/.default"])
      ...> )
      true
  """
  @impl AzureSDK.Identity.TokenCredential
  def get_token(%__MODULE__{credentials: credentials}, scopes, opts \\ []) when is_list(scopes) do
    credentials
    |> Enum.reduce_while({:error, unavailable()}, fn cred, _acc ->
      case TokenCredential.get_token(cred, scopes, opts) do
        {:ok, _} = ok ->
          {:halt, ok}

        {:error, %Error{code: "CredentialUnavailable"}} = error ->
          {:cont, error}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  defp build_chain(opts) do
    env_opts = if Keyword.has_key?(opts, :env), do: [env: opts[:env]], else: []
    mi_opts = Keyword.get(opts, :managed_identity, [])

    [EnvironmentCredential.new(env_opts), ManagedIdentityCredential.new(mi_opts)]
  end

  defp unavailable do
    Error.new(
      code: "CredentialUnavailable",
      message: "DefaultAzureCredential found no working credential in the chain",
      service: :identity
    )
  end
end
