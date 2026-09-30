defmodule AzureSDK.Storage.Conditions do
  @moduledoc """
  Builds Azure Storage conditional and lease request headers from options.

  ## Supported options

  * `:if_match` - `If-Match` (ETag or `"*"`)
  * `:if_none_match` - `If-None-Match`
  * `:if_modified_since` - `If-Modified-Since` (HTTP-date string)
  * `:if_unmodified_since` - `If-Unmodified-Since`
  * `:lease_id` - `x-ms-lease-id`

  Unknown keys are ignored. Pass the same keyword list into Blob / Lease
  operations that accept condition opts.

  ## Examples

      iex> AzureSDK.Storage.Conditions.headers(if_match: "\\"0x1\\"", lease_id: "abc")
      %{"If-Match" => "\\"0x1\\"", "x-ms-lease-id" => "abc"}
  """

  @doc """
  Returns a header map for the given options. Unknown keys are ignored.

  ## Examples

      iex> AzureSDK.Storage.Conditions.headers([])
      %{}

      iex> AzureSDK.Storage.Conditions.headers(if_none_match: "*")
      %{"If-None-Match" => "*"}

      iex> AzureSDK.Storage.Conditions.headers(
      ...>   if_modified_since: "Wed, 01 Jan 2020 00:00:00 GMT",
      ...>   if_unmodified_since: "Thu, 01 Jan 2030 00:00:00 GMT"
      ...> )
      %{
        "If-Modified-Since" => "Wed, 01 Jan 2020 00:00:00 GMT",
        "If-Unmodified-Since" => "Thu, 01 Jan 2030 00:00:00 GMT"
      }

      iex> AzureSDK.Storage.Conditions.headers(if_match: "\\"etag\\"", unknown: :ignored)
      %{"If-Match" => "\\"etag\\""}
  """
  @spec headers(keyword()) :: %{String.t() => String.t()}
  def headers(opts) when is_list(opts) do
    %{}
    |> maybe_put("If-Match", Keyword.get(opts, :if_match))
    |> maybe_put("If-None-Match", Keyword.get(opts, :if_none_match))
    |> maybe_put("If-Modified-Since", Keyword.get(opts, :if_modified_since))
    |> maybe_put("If-Unmodified-Since", Keyword.get(opts, :if_unmodified_since))
    |> maybe_put("x-ms-lease-id", Keyword.get(opts, :lease_id))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, to_string(value))
end
