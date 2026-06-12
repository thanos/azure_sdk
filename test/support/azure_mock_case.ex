defmodule ExAzure.AzureMockCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import ExAzure.AzureMockCase
      alias ExAzure.AzureMock
    end
  end

  setup do
    bypass = Bypass.open()
    client = ExAzure.AzureMock.client(bypass)

    {:ok, bypass: bypass, client: client, account: ExAzure.AzureMock.account()}
  end
end
