defmodule AzureSDK.Identity.TokenCredential do
  @moduledoc """
  Behaviour for Entra ID / OAuth credentials that acquire access tokens.

  The pipeline calls `AzureSDK.Identity.TokenCache.fetch/3`, which invokes
  `get_token/3` on cache miss, then applies `AzureSDK.Pipeline.Bearer`.

  ## Callback example

      defmodule StaticTokenCredential do
        @behaviour AzureSDK.Identity.TokenCredential

        defstruct [:name, :token]

        # Identify the credential by a non-secret name, never by the token.
        @impl true
        def cache_key(%__MODULE__{name: name}), do: {:static, name}

        @impl true
        def get_token(%__MODULE__{token: token}, _scopes, _opts) do
          expires = DateTime.add(DateTime.utc_now(), 3600, :second)
          {:ok, AzureSDK.Identity.AccessToken.new(token, expires)}
        end
      end
  """

  alias AzureSDK.Identity.AccessToken

  @typedoc "Any credential struct implementing this behaviour."
  @type t :: struct()

  @typedoc "OAuth scope string, for example `\\\"https://storage.azure.com/.default\\\"`."
  @type scope :: String.t()

  @typedoc "Stable cache key returned by `c:cache_key/1` (scopes are applied by TokenCache)."
  @type cache_key :: term()

  @doc """
  Acquires an access token for the given scopes.

  ## Parameters

  * `credential` - behaviour implementer
  * `scopes` - non-empty list of scope strings
  * `opts` - implementation-specific options (often `:req_options` for Req)

  ## Returns

  * `{:ok, %AzureSDK.Identity.AccessToken{}}`
  * `{:error, %AzureSDK.Error{}}`

  Implementations should not raise for expected acquisition failures.
  """
  @callback get_token(t(), [scope()], keyword()) ::
              {:ok, AccessToken.t()} | {:error, AzureSDK.Error.t()}

  @doc """
  Returns a stable cache key for the credential (without scopes).

  TokenCache combines this key with sorted scopes. Keys must not contain
  secrets such as client secrets or tokens.
  """
  @callback cache_key(t()) :: cache_key()

  @doc """
  Acquires an access token for the given scopes (empty options).

  See `get_token/3`.

  ## Examples

      iex> cred = AzureSDK.Identity.EnvironmentCredential.new(env: %{})
      iex> match?(
      ...>   {:error, %{code: "CredentialUnavailable"}},
      ...>   AzureSDK.Identity.TokenCredential.get_token(cred, ["https://storage.azure.com/.default"])
      ...> )
      true
  """
  @spec get_token(t(), [scope()]) :: {:ok, AccessToken.t()} | {:error, AzureSDK.Error.t()}
  def get_token(credential, scopes), do: get_token(credential, scopes, [])

  @doc """
  Acquires an access token for the given scopes with options.

  Dispatches to `c:get_token/3` on the credential module.
  """
  @spec get_token(t(), [scope()], keyword()) ::
          {:ok, AccessToken.t()} | {:error, AzureSDK.Error.t()}
  def get_token(credential, scopes, opts) when is_list(opts) do
    impl(credential).get_token(credential, scopes, opts)
  end

  @doc """
  Stable cache key for the credential (without scopes).

  ## Examples

      iex> cred = AzureSDK.Identity.ClientSecretCredential.new(
      ...>   tenant_id: "t",
      ...>   client_id: "c",
      ...>   client_secret: "s"
      ...> )
      iex> AzureSDK.Identity.TokenCredential.cache_key(cred)
      {:client_secret, "t", "c"}
  """
  @spec cache_key(t()) :: cache_key()
  def cache_key(credential) do
    impl(credential).cache_key(credential)
  end

  @doc """
  Returns `true` when the module exports `get_token/3` and `cache_key/1`.

  Used by the pipeline to distinguish token credentials from request credentials.

  ## Examples

      iex> AzureSDK.Identity.TokenCredential.token_credential?(AzureSDK.Identity.ClientSecretCredential)
      true
      iex> AzureSDK.Identity.TokenCredential.token_credential?(AzureSDK.Identity.SharedKeyCredential)
      false
  """
  @spec token_credential?(module()) :: boolean()
  def token_credential?(module) when is_atom(module) do
    function_exported?(module, :get_token, 3) and function_exported?(module, :cache_key, 1)
  end

  defp impl(%module{}), do: module
end
