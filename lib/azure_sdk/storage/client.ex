defmodule AzureSDK.Storage.Client do
  @moduledoc """
  Storage service client for Azure Blob, Queue, Table, and File endpoints.

  ## Fields

  * `:account` - storage account name
  * `:credential` - Shared Key, SAS, or token credential
  * `:endpoint` - absolute service URL
  * `:api_version` - Storage REST API version (`AzureSDK.Storage.ServiceVersion`)
  * `:path_style` - when `true`, Shared Key uses double-account canonicalization
  * `:retry` - retry policy
  * `:req_options` - extra Req options

  ## Path-style endpoints

  Azurite and some proxies use URLs where the account name appears in the path
  (`http://127.0.0.1:10000/myaccount`). Set `:path_style` to `true` for those
  endpoints. When omitted, path-style is detected when the endpoint path ends
  with the account name.

  ## Examples

      iex> cred = AzureSDK.Identity.SharedKeyCredential.new("acct", Base.encode64("sixteen-byte-key!"))
      iex> client = AzureSDK.Storage.Client.new(account: "acct", credential: cred)
      iex> client.endpoint
      "https://acct.blob.core.windows.net"
      iex> client.path_style
      false
  """

  alias AzureSDK.Core.Client
  alias AzureSDK.Storage.ServiceVersion

  @typedoc "Storage client. See the module documentation for field meanings."
  @type t :: %__MODULE__{
          account: String.t(),
          credential: AzureSDK.Identity.Credential.t() | AzureSDK.Identity.TokenCredential.t(),
          endpoint: String.t(),
          api_version: String.t(),
          path_style: boolean(),
          retry: AzureSDK.Core.Retry.policy(),
          req_options: keyword()
        }

  defstruct [
    :account,
    :credential,
    :endpoint,
    :api_version,
    :path_style,
    :retry,
    :req_options
  ]

  @doc """
  Creates a storage client.

  ## Options

  * `:account` (required) - storage account name
  * `:credential` (required) - identity credential
  * `:endpoint` - custom endpoint (defaults by `:service`)
  * `:service` - `:blob` (default), `:queue`, `:table`, or `:file` when building the default endpoint
  * `:api_version` - defaults to `ServiceVersion.default/0`. Not validated;
    call `ServiceVersion.validate/1` first to reject unknown versions
  * `:path_style` - path-style signing flag
  * `:retry` - retry policy map
  * `:req_options` - additional Req options

  ## Errors

  Raises `KeyError` when `:account` or `:credential` is missing.

  ## Examples

      iex> cred = AzureSDK.Identity.SharedKeyCredential.new("acct", Base.encode64("sixteen-byte-key!"))
      iex> client = AzureSDK.Storage.Client.new(
      ...>   account: "acct",
      ...>   credential: cred,
      ...>   endpoint: "http://127.0.0.1:10000/acct"
      ...> )
      iex> AzureSDK.Storage.Client.path_style?(client)
      true
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    account = Keyword.fetch!(opts, :account)
    credential = Keyword.fetch!(opts, :credential)
    endpoint = Keyword.get(opts, :endpoint, default_endpoint(account, opts))

    %__MODULE__{
      account: account,
      credential: credential,
      endpoint: endpoint,
      api_version: Keyword.get(opts, :api_version, ServiceVersion.default()),
      path_style: Keyword.get(opts, :path_style, path_style_endpoint?(account, endpoint)),
      retry: Keyword.get(opts, :retry, AzureSDK.Core.Retry.default_policy()),
      req_options: Keyword.get(opts, :req_options, [])
    }
  end

  @doc """
  Returns `true` when the client uses path-style Shared Key signing.

  ## Examples

      iex> cred = AzureSDK.Identity.SharedKeyCredential.new("acct", Base.encode64("sixteen-byte-key!"))
      iex> client = AzureSDK.Storage.Client.new(account: "acct", credential: cred, path_style: true)
      iex> AzureSDK.Storage.Client.path_style?(client)
      true
  """
  @spec path_style?(t()) :: boolean()
  def path_style?(%__MODULE__{path_style: value}), do: value

  @doc """
  Metadata passed to the signing pipeline for storage requests.

  ## Examples

      iex> cred = AzureSDK.Identity.SharedKeyCredential.new("acct", Base.encode64("sixteen-byte-key!"))
      iex> client = AzureSDK.Storage.Client.new(account: "acct", credential: cred, api_version: "2021-08-06")
      iex> AzureSDK.Storage.Client.signing_metadata(client)
      %{api_version: "2021-08-06", path_style: false}
  """
  @spec signing_metadata(t()) :: %{api_version: String.t(), path_style: boolean()}
  def signing_metadata(%__MODULE__{} = client) do
    %{api_version: client.api_version, path_style: client.path_style}
  end

  @doc """
  Converts a storage client into a core pipeline client.

  ## Examples

      iex> cred = AzureSDK.Identity.SharedKeyCredential.new("acct", Base.encode64("sixteen-byte-key!"))
      iex> storage = AzureSDK.Storage.Client.new(account: "acct", credential: cred)
      iex> core = AzureSDK.Storage.Client.to_core_client(storage)
      iex> core.endpoint == storage.endpoint
      true
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
