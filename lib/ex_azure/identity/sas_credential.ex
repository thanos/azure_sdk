defmodule ExAzure.Identity.SASCredential do
  @moduledoc """
  Shared Access Signature (SAS) credential.

  Accepts either a full SAS token (`sv=...&sig=...`) or a map of query parameters.
  """

  @behaviour ExAzure.Identity.Credential

  defstruct [:params]

  @type t :: %__MODULE__{params: %{String.t() => String.t()}}

  @doc """
  Creates a SAS credential from a token string or parameter map.
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

  @impl ExAzure.Identity.Credential
  def sign_request(%__MODULE__{} = credential, request) do
    ExAzure.Pipeline.SAS.apply(request, credential)
  end
end
