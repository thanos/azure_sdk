defmodule AzureSDK.AzuriteCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  @azurite_account "devstoreaccount1"

  @azurite_key "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="

  @azurite_endpoint "http://127.0.0.1:10000/#{@azurite_account}"

  using do
    quote do
      import AzureSDK.AzuriteCase

      @moduletag :azurite
    end
  end

  def azurite_client(opts \\ []) do
    credential =
      AzureSDK.Identity.SharedKeyCredential.new(@azurite_account, @azurite_key)

    AzureSDK.Storage.Client.new(
      account: @azurite_account,
      credential: credential,
      endpoint: Keyword.get(opts, :endpoint, @azurite_endpoint)
    )
  end

  def azurite_available? do
    case :gen_tcp.connect(~c"127.0.0.1", 10_000, [:binary, active: false], 500) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  def unique_name(prefix \\ "test") do
    prefix <> "-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end
end
