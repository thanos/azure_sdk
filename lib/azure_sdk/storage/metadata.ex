defmodule AzureSDK.Storage.Metadata do
  @moduledoc false

  @doc false
  @spec headers(map()) :: %{String.t() => String.t()}
  def headers(metadata) when is_map(metadata) do
    metadata
    |> Enum.map(fn {k, v} -> {"x-ms-meta-#{k}", to_string(v)} end)
    |> Map.new()
  end

  @doc false
  @spec from_headers(map()) :: map()
  def from_headers(headers) when is_map(headers) do
    headers
    |> Enum.filter(fn {k, _} -> String.starts_with?(String.downcase(k), "x-ms-meta-") end)
    |> Map.new(fn {k, v} ->
      key = k |> String.downcase() |> String.replace_prefix("x-ms-meta-", "")
      {key, v}
    end)
  end
end
