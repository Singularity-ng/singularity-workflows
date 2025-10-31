defmodule Singularity.Workflow.MixProject do
  use Mix.Project

  def project do
    [
      app: :singularity_workflow,
      version: "1.0.2",
      elixir: ">= 1.19.0-rc.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Core database dependencies
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.21"},

      # JSON handling
      {:jason, "~> 1.4"},

      # Observability
      {:telemetry, "~> 1.0"},

      # Development and testing
      {:mox, "~> 1.2", only: :test},

      # pgmq client
      {:pgmq, "~> 0.4"},

      # Code quality and security (dev only)
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},

      # Documentation
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "Singularity.Workflow",
      source_url: "https://github.com/Singularity-ng/singularity-workflows",
      extras: ["README.md"]
    ]
  end

  defp package do
    [
      name: "singularity_workflow",
      description: "PostgreSQL-based workflow orchestration library for Elixir",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/Singularity-ng/singularity-workflows",
        "Documentation" => "https://hexdocs.pm/singularity_workflow"
      },
      maintainers: ["Mikko H"],
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit]
    ]
  end
end
