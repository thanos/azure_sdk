defmodule AzureSDK.Core.Client do
  @moduledoc """
  Shared client configuration used across AzureSDK service clients.
  """

  @type t :: %__MODULE__{
          credential: AzureSDK.Identity.Credential.t() | nil,
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
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      credential: Keyword.get(opts, :credential),
      api_version: Keyword.get(opts, :api_version),
      retry: Keyword.get(opts, :retry, AzureSDK.Core.Retry.default_policy()),
      req_options: Keyword.get(opts, :req_options, []),
      endpoint: Keyword.get(opts, :endpoint)
    }
  end
end
