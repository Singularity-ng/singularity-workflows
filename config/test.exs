import Config

config :ex_pgflow,
  ecto_repos: [Pgflow.Repo]

# Configure test database to use Ecto.Sandbox for isolation
config :ex_pgflow, Pgflow.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ex_pgflow",
  username: System.get_env("USER") || "mhugo",
  password: "",
  hostname: "localhost",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox

# Override with DATABASE_URL if present
if url = System.get_env("DATABASE_URL") do
  config :ex_pgflow, Pgflow.Repo, url: url
end