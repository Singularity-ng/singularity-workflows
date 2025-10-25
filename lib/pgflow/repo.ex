defmodule Pgflow.Repo do
  use Ecto.Repo,
    otp_app: :ex_pgflow,
    adapter: Ecto.Adapters.Postgres
end
