defmodule AzureSDK.Application do
  @moduledoc """
  OTP application for AzureSDK.

  Starts the supervised `AzureSDK.Identity.TokenCache` used by Entra / OAuth
  credentials. Booted automatically when the `:azure_sdk` application starts
  (`mod: {AzureSDK.Application, []}` in `mix.exs`).

  ## Children

  * `AzureSDK.Identity.TokenCache` — named GenServer token cache
  """

  use Application

  @doc """
  Starts the AzureSDK supervision tree.

  ## Parameters

  * `_type` — OTP start type (unused)
  * `_args` — application start args (unused)

  ## Returns

  * `{:ok, pid}` — supervisor pid
  * `{:error, reason}` — supervisor failed to start

  ## Examples

  The application is started by the BEAM. In IEx after `mix` loads the app:

      {:ok, _} = Application.ensure_all_started(:azure_sdk)
      true = is_pid(Process.whereis(AzureSDK.Identity.TokenCache))
  """
  @impl true
  def start(_type, _args) do
    children = [
      AzureSDK.Identity.TokenCache
    ]

    opts = [strategy: :one_for_one, name: AzureSDK.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
