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
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],
      # Aliases for TDD workflow
      aliases: aliases()
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
      {:postgrex, "~> 0.17"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_test_watch, "~> 1.1", only: :dev},
      {:mox, "~> 1.1", only: :test}  # For London-style TDD mocks
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
      files: ~w(lib priv mix.exs README.md LICENSE.md CHANGELOG.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/mikkihugo/ex_pgflow",
        "Compared to pgflow" => "https://github.com/pgflow-dev/pgflow"
      }
    ]
  end

  defp docs do
    [
      extras: [
        "README.md",
        "GETTING_STARTED.md",
        "ARCHITECTURE.md",
        "CHANGELOG.md",
        "DYNAMIC_WORKFLOWS_GUIDE.md",
        "PGFLOW_REFERENCE.md",
        "SECURITY_AUDIT.md"
      ],
      main: "readme",
      source_ref: "main",
      formatters: ["html"]
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
