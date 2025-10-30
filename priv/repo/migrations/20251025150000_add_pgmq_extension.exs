defmodule QuantumFlow.Repo.Migrations.AddPgmqExtension do
  use Ecto.Migration

  def up do
    # Create pgmq extension (PostgreSQL Message Queue) - REQUIRED
    # Matches QuantumFlow's architecture: https://github.com/tembo-io/pgmq
    # pgmq is REQUIRED for task coordination and queue management
    # If this fails, ensure PostgreSQL instance has pgmq extension installed
    execute("CREATE EXTENSION IF NOT EXISTS pgmq")
  end

  def down do
    execute("DROP EXTENSION IF EXISTS pgmq CASCADE")
  end
end
