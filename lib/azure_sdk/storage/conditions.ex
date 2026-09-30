defmodule AzureSDK.Storage.Conditions do
  @moduledoc """
  Builds Azure Storage conditional and lease request headers from options.

  ## Supported options

  * `:if_match` - `If-Match` (ETag or `"*"`)
  * `:if_none_match` - `If-None-Match`
  * `:if_modified_since` - `If-Modified-Since` (`DateTime` or HTTP-date string)
  * `:if_unmodified_since` - `If-Unmodified-Since` (`DateTime` or HTTP-date string)
  * `:lease_id` - `x-ms-lease-id`

  Unknown keys are ignored. Pass the same keyword list into Blob / Lease
  operations that accept condition opts.

  ## Examples

      iex> AzureSDK.Storage.Conditions.headers(if_match: "\\"0x1\\"", lease_id: "abc")
      %{"If-Match" => "\\"0x1\\"", "x-ms-lease-id" => "abc"}
  """

  alias AzureSDK.Storage.Operation

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

      iex> AzureSDK.Storage.Conditions.headers(if_modified_since: ~U[2020-01-01 00:00:00Z])
      %{"If-Modified-Since" => "Wed, 01 Jan 2020 00:00:00 GMT"}

      iex> AzureSDK.Storage.Conditions.headers(if_match: "\\"etag\\"", unknown: :ignored)
      %{"If-Match" => "\\"etag\\""}
  """
  @spec headers(keyword()) :: %{String.t() => String.t()}
  def headers(opts) when is_list(opts) do
    %{}
    |> Operation.put_present("If-Match", Keyword.get(opts, :if_match))
    |> Operation.put_present("If-None-Match", Keyword.get(opts, :if_none_match))
    |> Operation.put_present("If-Modified-Since", date(Keyword.get(opts, :if_modified_since)))
    |> Operation.put_present("If-Unmodified-Since", date(Keyword.get(opts, :if_unmodified_since)))
    |> Operation.put_present("x-ms-lease-id", Keyword.get(opts, :lease_id))
  end

  defp date(%DateTime{} = dt), do: Operation.http_date(dt)
  defp date(value), do: value
end
