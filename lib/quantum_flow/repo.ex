defmodule QuantumFlow.Repo do
  use Ecto.Repo,
    otp_app: :quantum_flow,
    adapter: Ecto.Adapters.Postgres
end
