defmodule Cara.MixProject do
  use Mix.Project

  def project do
    [
      app: :cara,
      version: "0.4.4",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: test_coverage(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        ignore_warnings: "test/support/conn_case.ex",
        ignore_warnings: "test/support/data_case.ex"
      ],
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Cara.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14.1", only: [:dev, :test], runtime: false},
      {:branched_llm, github: "dvadell/branched_llm"},
      {:req_llm, "~> 1.0.0"},
      {:mox, "~> 1.0", only: :test},
      {:mdex, "~> 0.11"},
      {:mdex_gfm, "~> 0.1"},
      {:mdex_mermaid, "~> 0.1"},
      {:mdex_katex, "~> 0.1"},
      {:bypass, "~> 2.1", only: :test},
      {:retry, "~> 0.18"},
      {:abacus, "~> 0.3.0"},
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_exporter, "~> 1.8"},
      {:opentelemetry_phoenix, "~> 1.2"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_req, "~> 0.2"},
      {:opentelemetry_logger_metadata, "~> 0.2"},
      {:opentelemetry_api_experimental, "~> 0.5"},
      {:opentelemetry_experimental, "~> 0.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind cara", "esbuild cara"],
      "assets.deploy": [
        "tailwind cara --minify",
        "esbuild cara --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        ~s(cmd sh -c "MIX_ENV=test mix dialyzer"),
        ~s(cmd sh -c "MIX_ENV=test mix test --cover")
      ]
    ]
  end

  # Cara.AI.CLI is a test module to quickly test Cara.AI.Chat from iex.
  def test_coverage do
    [
      summary: [threshold: 90],
      output: "cover",
      ignore_modules: [
        Cara.AI.CLI,
        Cara.DataCase,
        Cara.Release,
        Cara.Repo,
        CaraWeb.CoreComponents,
        CaraWeb.ErrorHTML,
        CaraWeb.ErrorJSON,
        CaraWeb.Gettext,
        CaraWeb.Layouts,
        CaraWeb.PageController,
        CaraWeb.PageHTML,
        CaraWeb.StudentHTML,
        CaraWeb.Telemetry
      ]
    ]
  end
end
