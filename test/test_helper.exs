ExUnit.start()

# Manually load test config since Mix is not loading it automatically
test_config = Config.Reader.read!("config/test.exs", env: :test)
Application.put_all_env(test_config)

# Skip Mox setup for now to get tests running
# try do
#   require Mox
#   Mox.defmock(QuantumFlow.Notifications.Mock, for: QuantumFlow.Notifications.Behaviour)
# rescue
#   _ -> :ok
# end

# Start Ecto Repo for integration tests unless explicitly skipped
if System.get_env("PGFLOW_SKIP_DB") != "1" do
  {:ok, _} = Application.ensure_all_started(:mox)

  {:ok, _} = QuantumFlow.Repo.start_link()
  Ecto.Adapters.SQL.Sandbox.mode(QuantumFlow.Repo, :manual)
else
  Application.put_env(:quantum_flow, QuantumFlow.Repo, [])
end

# Load support helpers
Code.require_file("support/sql_case.ex", __DIR__)
