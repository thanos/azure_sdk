defmodule ExAzure.Pipeline.SAS do
  @moduledoc false

  alias ExAzure.Core.Request

  @doc """
  Applies SAS query parameters to a request.
  """
  @spec apply(Request.t(), ExAzure.Identity.SASCredential.t()) :: Request.t()
  def apply(%Request{} = request, %ExAzure.Identity.SASCredential{params: params}) do
    query =
      (request.query ++ Enum.to_list(params))
      |> Enum.uniq_by(fn {k, _} -> k end)

    %{request | query: query}
  end
end
