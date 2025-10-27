defmodule ExPgflow.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_pgflow,
      version: "1.0.2",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end
end
