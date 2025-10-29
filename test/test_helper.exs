ExUnit.start()

# Manually load test config since Mix is not loading it automatically
test_config = Config.Reader.read!("config/test.exs", env: :test)
Application.put_all_env(test_config)

require Mox
Mox.defmock(Pgflow.Notifications.Mock, for: Pgflow.Notifications.Behaviour)

# Start Ecto Repo for integration tests unless explicitly skipped
if System.get_env("PGFLOW_SKIP_DB") != "1" do
{:ok, _} = Application.ensure_all_started(:mox)

{:ok, _} = Pgflow.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Pgflow.Repo, :manual)
else
  Application.put_env(:ex_pgflow, Pgflow.Repo, [])
end

# Load support helpers
Code.require_file("support/sql_case.ex", __DIR__)
