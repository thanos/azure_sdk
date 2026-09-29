defmodule AzureSDK.Storage.Metadata do
  @moduledoc """
  Helpers for Azure Storage user-defined metadata headers (`x-ms-meta-*`).

  ## Examples

      iex> AzureSDK.Storage.Metadata.headers(%{"owner" => "team"})
      %{"x-ms-meta-owner" => "team"}
  """

  @doc """
  Converts a metadata map into `x-ms-meta-*` request headers.

  Values are stringified with `to_string/1`.

  ## Parameters

  * `metadata` - map of metadata key to value

  ## Examples

      iex> AzureSDK.Storage.Metadata.headers(%{env: :prod})
      %{"x-ms-meta-env" => "prod"}
  """
  @spec headers(map()) :: %{String.t() => String.t()}
  def headers(metadata) when is_map(metadata) do
    metadata
    |> Enum.map(fn {k, v} -> {"x-ms-meta-#{k}", to_string(v)} end)
    |> Map.new()
  end

  @doc """
  Extracts user metadata from response headers into a string-keyed map.

  Header names are matched case-insensitively. The `x-ms-meta-` prefix is
  stripped from keys.

  ## Parameters

  * `headers` - response header map

  ## Examples

      iex> AzureSDK.Storage.Metadata.from_headers(%{"x-ms-meta-Owner" => "team", "etag" => "1"})
      %{"owner" => "team"}
  """
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
