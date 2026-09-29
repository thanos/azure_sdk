defmodule AzureSDK.Core.Client do
  @moduledoc """
  Shared pipeline client configuration used by service clients.

  Built by adapters such as `AzureSDK.Storage.Client.to_core_client/1`.

  ## Fields

  * `:credential` — request or token credential, or `nil`
  * `:api_version` — optional API version string
  * `:retry` — `AzureSDK.Core.Retry` policy map
  * `:req_options` — extra options merged into Req
  * `:endpoint` — absolute service endpoint URL

  ## Examples

      iex> client = AzureSDK.Core.Client.new(endpoint: "https://example.blob.core.windows.net")
      iex> client.endpoint
      "https://example.blob.core.windows.net"
  """

  @typedoc "Core pipeline client. See the module documentation for field meanings."
  @type t :: %__MODULE__{
          credential:
            AzureSDK.Identity.Credential.t() | AzureSDK.Identity.TokenCredential.t() | nil,
          api_version: String.t() | nil,
          retry: AzureSDK.Core.Retry.policy(),
          req_options: keyword(),
          endpoint: String.t() | nil
        }

  defstruct credential: nil,
            api_version: nil,
            retry: nil,
            req_options: [],
            endpoint: nil

  @doc """
  Creates a base client struct from common options.

  ## Options

  * `:credential` — credential struct
  * `:api_version` — API version string
  * `:retry` — retry policy; defaults to `AzureSDK.Core.Retry.default_policy/0`
  * `:req_options` — keyword list for Req
  * `:endpoint` — absolute base URL

  ## Examples

      iex> client = AzureSDK.Core.Client.new(retry: %{max_attempts: 1, base_delay_ms: 1, max_delay_ms: 1, jitter: false})
      iex> client.retry.max_attempts
      1
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    %__MODULE__{
      credential: Keyword.get(opts, :credential),
      api_version: Keyword.get(opts, :api_version),
      retry: Keyword.get(opts, :retry, AzureSDK.Core.Retry.default_policy()),
      req_options: Keyword.get(opts, :req_options, []),
      endpoint: Keyword.get(opts, :endpoint)
    }
  end
end
