defmodule AzureSDK.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/thanos/azure_sdk"

  def project do
    [
      app: :azure_sdk,
      aliases: [verify: &verify/1],
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Azure SDK",
      description: "Azure platform SDK for Elixir and Erlang",
      package: package(),
      docs: docs(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        flags: [:error_handling, :underspecs]
      ],
      test_coverage: [tool: ExCoveralls],
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
      extra_applications: [:logger, :crypto, :ssl],
      mod: {AzureSDK.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:sweet_xml, "~> 0.7"},
      {:telemetry, "~> 1.3"},
      {:jason, "~> 1.4"},
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
      maintainers: ["Thanos Vassilakis"],
      licenses: ["MIT"],
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md SECURITY.md guides livebooks),
      links: %{
        "GitHub" => @source_url,
        "Security" => "#{@source_url}/blob/main/SECURITY.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/azure_for_elixir_developers.md",
        "guides/identity_vs_data_plane.md",
        "guides/azure_identity.md",
        "guides/migrating_from_azurex.md",
        "guides/telemetry_driven_sdk_design.md",
        "guides/building_sdk_pipelines_with_req.md",
        "guides/designing_cloud_sdks_on_the_beam.md",
        "guides/studying_the_azure_sdk_architecture.md",
        "guides/management_plane_design.md",
        "livebooks/getting_started.livemd",
        "livebooks/blob_storage.livemd",
        "livebooks/authentication.livemd",
        "livebooks/streaming.livemd",
        "livebooks/telemetry.livemd",
        "livebooks/queue_storage.livemd"
      ],
      groups_for_extras: [
        "Using Azure SDK": [
          "guides/azure_for_elixir_developers.md",
          "guides/identity_vs_data_plane.md",
          "guides/azure_identity.md",
          "guides/migrating_from_azurex.md",
          "guides/telemetry_driven_sdk_design.md"
        ],
        "Design & Internals": [
          "guides/building_sdk_pipelines_with_req.md",
          "guides/designing_cloud_sdks_on_the_beam.md",
          "guides/studying_the_azure_sdk_architecture.md",
          "guides/management_plane_design.md"
        ],
        Livebooks: [
          "livebooks/getting_started.livemd",
          "livebooks/blob_storage.livemd",
          "livebooks/authentication.livemd",
          "livebooks/streaming.livemd",
          "livebooks/telemetry.livemd",
          "livebooks/queue_storage.livemd"
        ]
      ],
      groups_for_modules: [
        Identity: [~r/^AzureSDK\.Identity\./],
        Storage: [~r/^AzureSDK\.Storage\./],
        Core: [~r/^AzureSDK\.Core\./, AzureSDK.Error],
        Pipeline: [~r/^AzureSDK\.Pipeline\./]
      ],
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end

  defp verify(_) do
    steps = [
      {"compile --warnings-as-errors", :dev},
      {"format --check-formatted", :dev},
      {"credo --strict", :dev},
      {"doctor --full", :dev},
      {"sobelow --config", :dev},
      {"dialyzer", :dev},
      {"test --cover", :test},
      {"docs --warnings-as-errors", :dev}
    ]

    Enum.each(steps, fn {task, env} ->
      Mix.shell().info([:bright, "==> mix #{task}", :reset])

      {_, exit_code} =
        System.cmd("mix", String.split(task),
          env: [{"MIX_ENV", to_string(env)}],
          into: IO.stream()
        )

      if exit_code != 0 do
        Mix.raise("mix #{task} failed (exit code #{exit_code})")
      end
    end)

    Mix.shell().info([:green, :bright, "\nAll verification checks passed!", :reset])
  end
end
