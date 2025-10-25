ExUnit.start()
Logger.configure(level: :info)

# Start Ecto Repo for integration tests
{:ok, _} = Pgflow.Repo.start_link()

# Load support helpers
Code.require_file("support/sql_case.ex", __DIR__)
