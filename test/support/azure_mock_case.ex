defmodule AzureSDK.AzureMockCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import AzureSDK.AzureMockCase
      alias AzureSDK.AzureMock
    end
  end

  setup do
    bypass = Bypass.open()
    client = AzureSDK.AzureMock.client(bypass)

    {:ok, bypass: bypass, client: client, account: AzureSDK.AzureMock.account()}
  end
end
