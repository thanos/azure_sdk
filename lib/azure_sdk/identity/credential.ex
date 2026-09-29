defmodule AzureSDK.Identity.Credential do
  @moduledoc """
  Behaviour for request-authorization credentials (Shared Key, SAS).

  Token-based Entra credentials implement `AzureSDK.Identity.TokenCredential`
  instead. The pipeline acquires a token and applies `AzureSDK.Pipeline.Bearer`.

  ## Callback example

      defmodule PassThroughCredential do
        @behaviour AzureSDK.Identity.Credential

        defstruct []

        @impl true
        def authorize_request(%__MODULE__{}, request) do
          {:ok, request}
        end
      end
  """

  @typedoc "Any credential struct implementing this behaviour."
  @type t :: struct()

  @doc """
  Authorizes a request by mutating headers or query parameters.

  ## Parameters

  * `credential` - behaviour implementer
  * `request` - `AzureSDK.Core.Request`

  ## Returns

  * `{:ok, request}` - authorized request
  * `{:error, %AzureSDK.Error{}}` - authorization failed

  Implementations should not raise for expected failures.
  """
  @callback authorize_request(t(), AzureSDK.Core.Request.t()) ::
              {:ok, AzureSDK.Core.Request.t()} | {:error, AzureSDK.Error.t()}

  @doc """
  Dispatches `authorize_request/2` to the credential's implementation module.

  ## Examples

      iex> cred = AzureSDK.Identity.SASCredential.new(%{"sig" => "abc"})
      iex> req = AzureSDK.Core.Request.new(method: :get, path: "/")
      iex> {:ok, authorized} = AzureSDK.Identity.Credential.authorize_request(cred, req)
      iex> {"sig", "abc"} in authorized.query
      true
  """
  @spec authorize_request(t(), AzureSDK.Core.Request.t()) ::
          {:ok, AzureSDK.Core.Request.t()} | {:error, AzureSDK.Error.t()}
  def authorize_request(credential, request) do
    impl(credential).authorize_request(credential, request)
  end

  defp impl(%module{}), do: module
end
