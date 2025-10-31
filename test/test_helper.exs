ExUnit.start()

# Manually load test config since Mix is not loading it automatically
test_config = Config.Reader.read!("config/test.exs", env: :test)
Application.put_all_env(test_config)

# Load support helpers
Code.require_file("support/mox_helper.ex", __DIR__)
Code.require_file("support/sql_case.ex", __DIR__)
Code.require_file("support/snapshot.ex", __DIR__)

# Start Ecto Repo for integration tests unless explicitly skipped
if System.get_env("QUANTUM_FLOW_SKIP_DB") != "1" do
  {:ok, _} = Singularity.Workflow.Repo.start_link()
  Ecto.Adapters.SQL.Sandbox.mode(Singularity.Workflow.Repo, :manual)
else
  Application.put_env(:singularity_workflow, Singularity.Workflow.Repo, [])
end
