ExUnit.start()

# Manually load test config since Mix is not loading it automatically
test_config = Config.Reader.read!("config/test.exs", env: :test)
Application.put_all_env(test_config)

# Start Ecto Repo for integration tests first
{:ok, _} = Pgflow.Repo.start_link()

# Set up Ecto.Sandbox for test isolation
Ecto.Adapters.SQL.Sandbox.mode(Pgflow.Repo, :manual)

# Load support helpers
Code.require_file("support/sql_case.ex", __DIR__)
