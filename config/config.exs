import Config

config :ex_pgflow,
  ecto_repos: [Pgflow.Repo]

# Use DATABASE_URL if provided (for CI/testing), otherwise use defaults
config :ex_pgflow, Pgflow.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ex_pgflow",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432

# Override with DATABASE_URL if present
if url = System.get_env("DATABASE_URL") do
  config :ex_pgflow, Pgflow.Repo, url: url
end
