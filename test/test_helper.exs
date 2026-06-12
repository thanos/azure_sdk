Code.require_file("support/azurite_case.ex", __DIR__)
Code.require_file("support/azure_mock.ex", __DIR__)
Code.require_file("support/azure_mock_case.ex", __DIR__)

exclude =
  []
  |> then(fn tags ->
    if System.get_env("AZURITE") != "true", do: [:azurite | tags], else: tags
  end)
  |> then(fn tags ->
    if System.get_env("PROPERTY") != "true", do: [:property | tags], else: tags
  end)

ExUnit.start(exclude: exclude)
