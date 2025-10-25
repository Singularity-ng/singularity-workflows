defmodule ExPgflow.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_pgflow,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description(),
      source_url: "https://github.com/mikkihugo/ex_pgflow",
      homepage_url: "https://github.com/mikkihugo/ex_pgflow",
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_local_path: "priv/plts"
      ],
      test_coverage: [tool: ExCoveralls],
      # Aliases for TDD workflow
      aliases: aliases()
    ]
  end

  def cli do
    [
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.10"},
  {:postgrex, ">= 0.19.0 and < 2.0.0"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_test_watch, "~> 1.1", only: :dev},
      # For London-style TDD mocks
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp description do
    """
    Elixir implementation of pgflow's database-driven DAG execution.

    Uses PostgreSQL + pgmq extension for workflow coordination, matching
    pgflow's proven architecture with 100% feature parity: parallel DAG
    execution, map steps, dependency merging, and multi-instance scaling.
    """
  end

  defp package do
    [
      # Only include necessary files for Hex package
      # Excludes: .github/, .claude/, test/, docs/, scripts/, .formatter.exs, etc.
      files: ~w(lib priv/repo/migrations mix.exs README.md LICENSE.md CHANGELOG.md
                GETTING_STARTED.md ARCHITECTURE.md CONTRIBUTING.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/mikkihugo/ex_pgflow",
        "Original pgflow (TypeScript)" => "https://pgflow.dev",
        "pgmq Extension" => "https://github.com/tembo-io/pgmq"
      },
      maintainers: ["Mikael Hugo"]
    ]
  end

  defp docs do
    [
      extras: [
        "README.md",
        "GETTING_STARTED.md",
        "ARCHITECTURE.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md"
      ],
      main: "readme",
      source_ref: "main",
      formatters: ["html"],
      nest_modules_by_prefix: [Pgflow]
    ]
  end

  defp aliases do
    [
      test: ["test"],
      "test.watch": ["test.watch"],
      "test.coverage": ["coveralls"],
      "test.coverage.html": ["coveralls.html"],
      quality: [
        "format --check-formatted",
        "credo --strict",
        "dialyzer",
        "sobelow --exit-on-warning",
        "deps.audit"
      ]
    ]
  end
end
