defmodule AzureSDK.Pipeline.Bearer do
  @moduledoc """
  Pipeline helper that sets `Authorization: Bearer …` from an access token.

  Used by `AzureSDK.Core.Pipeline` after `AzureSDK.Identity.TokenCache.fetch/3`
  succeeds for a `AzureSDK.Identity.TokenCredential`. Application code rarely
  calls this module directly.

  ## Examples

      iex> token =
      ...>   AzureSDK.Identity.AccessToken.new("tok", ~U[2030-01-01 00:00:00Z])
      iex> req = AzureSDK.Core.Request.new(service: :blob, operation: :get)
      iex> authorized = AzureSDK.Pipeline.Bearer.apply(req, token)
      iex> authorized.headers["Authorization"]
      "Bearer tok"
  """

  alias AzureSDK.Core.Request
  alias AzureSDK.Identity.AccessToken

  @doc """
  Applies a Bearer access token to the request Authorization header.

  Uses `token.token_type` (usually `"Bearer"`) and `token.token`. Emits
  `[:azure_sdk, :auth, :sign]` telemetry with `scheme: :bearer`.

  ## Parameters

  * `request` — `AzureSDK.Core.Request`
  * `token` — `AzureSDK.Identity.AccessToken`

  ## Returns

  Updated request with the Authorization header set. Does not raise.

  ## Examples

      iex> token = AzureSDK.Identity.AccessToken.new("abc", ~U[2030-01-01 00:00:00Z], token_type: "Bearer")
      iex> req = AzureSDK.Core.Request.new([])
      iex> AzureSDK.Pipeline.Bearer.apply(req, token).headers["Authorization"]
      "Bearer abc"
  """
  @spec apply(Request.t(), AccessToken.t()) :: Request.t()
  def apply(%Request{} = request, %AccessToken{token: token, token_type: type}) do
    request
    |> Request.put_header("Authorization", "#{type} #{token}")
    |> tap(fn _ ->
      AzureSDK.Core.Telemetry.emit_sign(%{
        scheme: :bearer,
        service: request.service,
        operation: request.operation
      })
    end)
  end
end
