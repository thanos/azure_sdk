defmodule AzureSDK.Identity.AccessToken do
  @moduledoc """
  OAuth access token returned by `AzureSDK.Identity.TokenCredential`.

  ## Fields

  * `:token` - opaque access token string (required; hidden from `inspect/2`)
  * `:expires_at` - absolute UTC expiry (`DateTime`) (required)
  * `:token_type` - token type for the Authorization header; default `"Bearer"`

  ## Examples

      iex> expires = ~U[2030-01-01 00:00:00Z]
      iex> token = AzureSDK.Identity.AccessToken.new("abc", expires)
      iex> token.token_type
      "Bearer"
  """

  @typedoc "Access token struct. See the module documentation for field meanings."
  @type t :: %__MODULE__{
          token: String.t(),
          expires_at: DateTime.t(),
          token_type: String.t()
        }

  @derive {Inspect, except: [:token]}
  @enforce_keys [:token, :expires_at]
  defstruct token: nil, expires_at: nil, token_type: "Bearer"

  @doc """
  Builds an access token from a token string and absolute expiry.

  ## Parameters

  * `token` - access token string
  * `expires_at` - absolute expiry as `DateTime`
  * `opts` - optional keyword list:
    * `:token_type` - defaults to `"Bearer"`

  ## Returns

  `%AzureSDK.Identity.AccessToken{}`.

  ## Examples

      iex> t = AzureSDK.Identity.AccessToken.new("tok", ~U[2030-01-01 00:00:00Z], token_type: "Bearer")
      iex> t.token
      "tok"
  """
  @spec new(String.t(), DateTime.t(), keyword()) :: t()
  def new(token, %DateTime{} = expires_at, opts \\ []) when is_binary(token) do
    %__MODULE__{
      token: token,
      expires_at: expires_at,
      token_type: Keyword.get(opts, :token_type, "Bearer")
    }
  end

  @doc """
  Builds an access token from a token endpoint JSON body.

  ## Parameters

  * `body` - decoded JSON map. Must include `"access_token"` and either:
    * `"expires_on"` - unix seconds as integer or string, or
    * `"expires_in"` - lifetime in seconds from now (integer or string)

  Optional `"token_type"` defaults to `"Bearer"`.

  ## Returns

  * `{:ok, t()}` on success
  * `{:error, %AzureSDK.Error{code: "InvalidTokenResponse"}}` when the token or
    expiry is missing/invalid

  Does not raise.

  ## Examples

      iex> {:ok, token} = AzureSDK.Identity.AccessToken.from_response(%{
      ...>   "access_token" => "abc",
      ...>   "expires_on" => "1893456000",
      ...>   "token_type" => "Bearer"
      ...> })
      iex> token.token
      "abc"
      iex> AzureSDK.Identity.AccessToken.from_response(%{})
      {:error, %AzureSDK.Error{code: "InvalidTokenResponse", message: "Token response missing access_token", service: :identity, status: nil, request_id: nil, details: nil, cause: nil}}
  """
  @spec from_response(map()) :: {:ok, t()} | {:error, AzureSDK.Error.t()}
  def from_response(%{"access_token" => token} = body) when is_binary(token) do
    case expires_at(body) do
      {:ok, expires_at} ->
        {:ok,
         new(token, expires_at, token_type: Map.get(body, "token_type", "Bearer") || "Bearer")}

      {:error, _} = error ->
        error
    end
  end

  def from_response(_body) do
    {:error,
     AzureSDK.Error.new(
       code: "InvalidTokenResponse",
       message: "Token response missing access_token",
       service: :identity
     )}
  end

  @doc """
  Returns `true` when the token should be refreshed.

  A token is stale when `expires_at` is not strictly after
  `now + buffer_seconds`.

  ## Parameters

  * `token` - access token
  * `buffer_seconds` - refresh lead time; default `300`

  ## Examples

      iex> token = AzureSDK.Identity.AccessToken.new("x", DateTime.add(DateTime.utc_now(), 60, :second))
      iex> AzureSDK.Identity.AccessToken.stale?(token, 300)
      true
      iex> AzureSDK.Identity.AccessToken.stale?(token, 30)
      false
  """
  @spec stale?(t(), non_neg_integer()) :: boolean()
  def stale?(%__MODULE__{expires_at: expires_at}, buffer_seconds \\ 300) do
    DateTime.compare(expires_at, DateTime.add(DateTime.utc_now(), buffer_seconds, :second)) != :gt
  end

  defp expires_at(%{"expires_on" => expires_on}) do
    case parse_unix(expires_on) do
      {:ok, seconds} -> DateTime.from_unix(seconds)
      :error -> {:error, invalid_expiry()}
    end
  end

  defp expires_at(%{"expires_in" => expires_in}) do
    case parse_int(expires_in) do
      {:ok, seconds} ->
        {:ok, DateTime.add(DateTime.utc_now(), seconds, :second)}

      :error ->
        {:error, invalid_expiry()}
    end
  end

  defp expires_at(_), do: {:error, invalid_expiry()}

  defp parse_unix(value) when is_integer(value), do: {:ok, value}

  defp parse_unix(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_unix(_), do: :error

  defp parse_int(value) when is_integer(value), do: {:ok, value}

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_int(_), do: :error

  defp invalid_expiry do
    AzureSDK.Error.new(
      code: "InvalidTokenResponse",
      message: "Token response missing or invalid expiry",
      service: :identity
    )
  end
end
