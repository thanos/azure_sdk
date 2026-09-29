defmodule AzureSDK.Identity.SASCredential do
  @moduledoc """
  Shared Access Signature (SAS) credential.

  Accepts a full SAS query string (`sv=...&sig=...`) or a parameter map.
  A leading `?` is stripped from token strings.

  ## Fields

  * `:params` — string-keyed SAS query parameters

  ## Examples

      iex> cred = AzureSDK.Identity.SASCredential.new("?sv=2021-06-08&sig=abc")
      iex> cred.params["sv"]
      "2021-06-08"
  """

  @behaviour AzureSDK.Identity.Credential

  @typedoc "SAS credential. See the module documentation for field meanings."
  @type t :: %__MODULE__{params: %{String.t() => String.t()}}

  defstruct [:params]

  @doc """
  Creates a SAS credential from a token string or parameter map.

  ## Parameters

  * `token_or_params` — SAS query string (optional leading `?`) or map of params

  ## Returns

  `%AzureSDK.Identity.SASCredential{}`.

  ## Examples

      iex> AzureSDK.Identity.SASCredential.new(%{sp: "r", sig: "x"}).params
      %{"sp" => "r", "sig" => "x"}
  """
  @spec new(String.t() | map()) :: t()
  def new("?" <> token), do: new(token)

  def new(token) when is_binary(token) do
    params =
      token
      |> URI.decode_query()
      |> Map.new()

    %__MODULE__{params: params}
  end

  def new(params) when is_map(params) do
    %__MODULE__{params: Map.new(params, fn {k, v} -> {to_string(k), to_string(v)} end)}
  end

  @doc """
  Merges SAS parameters into the request query string.

  Existing query keys take precedence over SAS params with the same name
  (`Enum.uniq_by/2` keeps the first occurrence).

  ## Returns

  Always `{:ok, request}`. Does not raise.

  ## Examples

      iex> cred = AzureSDK.Identity.SASCredential.new(%{"sig" => "abc"})
      iex> req = AzureSDK.Core.Request.new(query: [{"restype", "container"}])
      iex> {:ok, signed} = AzureSDK.Identity.SASCredential.authorize_request(cred, req)
      iex> {"sig", "abc"} in signed.query
      true
  """
  @impl AzureSDK.Identity.Credential
  def authorize_request(%__MODULE__{} = credential, request) do
    {:ok, AzureSDK.Pipeline.SAS.apply(request, credential)}
  end
end
