import Config

config :ex_pgflow,
  ecto_repos: [Pgflow.Repo]

config :ex_pgflow, Pgflow.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ex_pgflow",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432