defmodule QuantumFlow.MixProject do
  use Mix.Project

  def project do
    [
      app: :quantum_flow,
      version: "1.0.2",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},
      {:jason, "~> 1.4"},
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
