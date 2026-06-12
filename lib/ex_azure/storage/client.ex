defmodule ExAzure.Storage.Client do
  @moduledoc """
  Storage service client for Azure Blob, Queue, Table, and File services.

      client =
        ExAzure.Storage.Client.new(
          account: "myaccount",
          credential: credential
        )
  """

  alias ExAzure.Core.Client

  @default_api_version "2024-11-04"

  defstruct [
    :account,
    :credential,
    :endpoint,
    :api_version,
    :retry,
    :req_options
  ]

  @type t :: %__MODULE__{
          account: String.t(),
          credential: ExAzure.Identity.Credential.t(),
          endpoint: String.t(),
          api_version: String.t(),
          retry: ExAzure.Core.Retry.policy(),
          req_options: keyword()
        }

  @doc """
  Creates a storage client.

  ## Options

  * `:account` — storage account name (required)
  * `:credential` — an `ExAzure.Identity` credential (required)
  * `:endpoint` — custom endpoint (defaults to Azure public cloud or Azurite)
  * `:api_version` — storage API version
  * `:retry` — retry policy map
  * `:req_options` — additional Req options
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    account = Keyword.fetch!(opts, :account)
    credential = Keyword.fetch!(opts, :credential)

    %__MODULE__{
      account: account,
      credential: credential,
      endpoint: Keyword.get(opts, :endpoint, default_endpoint(account, opts)),
      api_version: Keyword.get(opts, :api_version, @default_api_version),
      retry: Keyword.get(opts, :retry, ExAzure.Core.Retry.default_policy()),
      req_options: Keyword.get(opts, :req_options, [])
    }
  end

  @doc """
  Returns true when the client targets Azurite or another path-style emulator.
  """
  @spec emulator?(t()) :: boolean()
  def emulator?(%__MODULE__{endpoint: endpoint}) when is_binary(endpoint) do
    not String.contains?(endpoint, ".blob.core.windows.net")
  end

  def emulator?(_), do: false

  @doc """
  Metadata passed to the signing pipeline for storage requests.
  """
  @spec signing_metadata(t()) :: %{api_version: String.t(), emulator: boolean()}
  def signing_metadata(%__MODULE__{} = client) do
    %{api_version: client.api_version, emulator: emulator?(client)}
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
end
