defmodule ExAzure.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ex-azure/ex_azure"

  def project do
    [
      app: :ex_azure,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "ExAzure",
      description: "The canonical Azure platform SDK for Elixir and Erlang",
      package: package(),
      docs: docs(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        flags: [:error_handling, :underspecs]
      ],
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 80],
        ignore_modules: [
          ExAzure.Integrations.Broadway,
          ExAzure.Integrations.Explorer,
          ExAzure.Integrations.Flow,
          ExAzure.Integrations.Livebook,
          ExAzure.Integrations.Nx,
          ExAzure.Management.Network,
          ExAzure.Management.Policy,
          ExAzure.Management.Replication,
          ExAzure.Management.StorageAccount,
          ExAzure.Storage.DataLake,
          ExAzure.Storage.FileShare,
          ExAzure.Storage.Queue,
          ExAzure.Storage.Table,
          ExAzure.Identity.ClientSecretCredential,
          ExAzure.Identity.DefaultAzureCredential,
          ExAzure.Identity.ManagedIdentityCredential,
          ExAzure.Identity.TokenCache,
          ExAzure.Management.Client,
          ExAzure.Pipeline.Retry,
          ExAzure.Core.Client
        ]
      ],
      test_paths: ["test"],
      test_ignore_filters: [~r/support\//]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:sweet_xml, "~> 0.7"},
      {:telemetry, "~> 1.3"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: :dev, runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp package do
    [
      maintainers: ["ExAzure Contributors"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end
end
