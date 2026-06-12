defmodule AzureSDK.Storage.Client do
  @moduledoc """
  Storage service client for Azure Blob, Queue, Table, and File services.

      client =
        AzureSDK.Storage.Client.new(
          account: "myaccount",
          credential: credential
        )

  ## Path-style endpoints

  Azurite and some proxies use path-style URLs where the account name appears in the
  path (`http://127.0.0.1:10000/myaccount`). Set `:path_style` to `true` for those
  endpoints. When omitted, path-style is auto-detected when the endpoint path ends with
  the account name.
  """

  alias AzureSDK.Core.Client

  @default_api_version "2024-11-04"

  defstruct [
    :account,
    :credential,
    :endpoint,
    :api_version,
    :path_style,
    :retry,
    :req_options
  ]

  @type t :: %__MODULE__{
          account: String.t(),
          credential: AzureSDK.Identity.Credential.t(),
          endpoint: String.t(),
          api_version: String.t(),
          path_style: boolean(),
          retry: AzureSDK.Core.Retry.policy(),
          req_options: keyword()
        }

  @doc """
  Creates a storage client.

  ## Options

  * `:account` — storage account name (required)
  * `:credential` — an `AzureSDK.Identity` credential (required)
  * `:endpoint` — custom endpoint (defaults to Azure public cloud or Azurite)
  * `:api_version` — storage API version
  * `:path_style` — use path-style signing (auto-detected when endpoint ends with account)
  * `:retry` — retry policy map
  * `:req_options` — additional Req options
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    account = Keyword.fetch!(opts, :account)
    credential = Keyword.fetch!(opts, :credential)
    endpoint = Keyword.get(opts, :endpoint, default_endpoint(account, opts))

    %__MODULE__{
      account: account,
      credential: credential,
      endpoint: endpoint,
      api_version: Keyword.get(opts, :api_version, @default_api_version),
      path_style: Keyword.get(opts, :path_style, path_style_endpoint?(account, endpoint)),
      retry: Keyword.get(opts, :retry, AzureSDK.Core.Retry.default_policy()),
      req_options: Keyword.get(opts, :req_options, [])
    }
  end

  @doc """
  Returns true when the client uses path-style signing (e.g. Azurite).
  """
  @spec path_style?(t()) :: boolean()
  def path_style?(%__MODULE__{path_style: value}), do: value

  @doc """
  Metadata passed to the signing pipeline for storage requests.
  """
  @spec signing_metadata(t()) :: %{api_version: String.t(), path_style: boolean()}
  def signing_metadata(%__MODULE__{} = client) do
    %{api_version: client.api_version, path_style: client.path_style}
  end

  @doc """
  Converts a storage client into a core pipeline client.
  """
  @spec to_core_client(t()) :: Client.t()
  def to_core_client(%__MODULE__{} = client) do
    %Client{
      credential: client.credential,
      api_version: client.api_version,
      retry: client.retry,
      req_options: client.req_options,
      endpoint: client.endpoint
    }
  end

  defp default_endpoint(account, opts) do
    case Keyword.get(opts, :service, :blob) do
      :blob -> "https://#{account}.blob.core.windows.net"
      :queue -> "https://#{account}.queue.core.windows.net"
      :table -> "https://#{account}.table.core.windows.net"
      :file -> "https://#{account}.file.core.windows.net"
    end
  end

  defp path_style_endpoint?(account, endpoint) when is_binary(endpoint) do
    endpoint
    |> String.trim_trailing("/")
    |> String.ends_with?("/#{account}")
  end

  defp path_style_endpoint?(_, _), do: false
end
