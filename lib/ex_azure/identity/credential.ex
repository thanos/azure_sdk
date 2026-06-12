defmodule ExAzure.Identity.Credential do
  @moduledoc """
  Behaviour for Azure credentials.

  All credentials must implement `sign_request/2` so they can plug into
  the shared ExAzure pipeline.
  """

  @type t :: struct()

  @callback sign_request(t(), ExAzure.Core.Request.t()) :: ExAzure.Core.Request.t()

  @doc """
  Dispatches request signing to the credential implementation module.
  """
  @spec sign_request(t(), ExAzure.Core.Request.t()) :: ExAzure.Core.Request.t()
  def sign_request(credential, request) do
    impl(credential).sign_request(credential, request)
  end

  defp impl(%module{}), do: module
end
