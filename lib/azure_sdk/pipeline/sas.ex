defmodule AzureSDK.Pipeline.SAS do
  @moduledoc false

  alias AzureSDK.Core.Request

  @doc """
  Applies SAS query parameters to a request.
  """
  @spec apply(Request.t(), AzureSDK.Identity.SASCredential.t()) :: Request.t()
  def apply(%Request{} = request, %AzureSDK.Identity.SASCredential{params: params}) do
    query =
      (request.query ++ Enum.to_list(params))
      |> Enum.uniq_by(fn {k, _} -> k end)

    %{request | query: query}
  end
end
