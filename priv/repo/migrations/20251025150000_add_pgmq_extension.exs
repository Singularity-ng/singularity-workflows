defmodule Pgflow.Repo.Migrations.AddPgmqExtension do
  use Ecto.Migration

  def up do
    # Create pgmq extension (PostgreSQL Message Queue)
    # Matches pgflow's architecture: https://github.com/tembo-io/pgmq
    # Note: Gracefully handles systems where pgmq is not installed
    # (e.g., postgres:15-alpine in CI). The extension is optional for tests
    # since Elixir code can fall back to schema-based message queueing.
    try do
      execute("CREATE EXTENSION IF NOT EXISTS pgmq")
    rescue
      # Extension not available on this PostgreSQL installation
      # This is OK for testing - pgmq is not required for functionality
      _ -> :ok
    end
  end

  def down do
    try do
      execute("DROP EXTENSION IF EXISTS pgmq CASCADE")
    rescue
      _ -> :ok
    end
  end
end
