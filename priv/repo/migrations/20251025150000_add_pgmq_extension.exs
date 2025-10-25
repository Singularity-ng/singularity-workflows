defmodule Pgflow.Repo.Migrations.AddPgmqExtension do
  use Ecto.Migration

  def up do
    # Create pgmq extension (PostgreSQL Message Queue)
    # Matches pgflow's architecture: https://github.com/tembo-io/pgmq
    execute("CREATE EXTENSION IF NOT EXISTS pgmq VERSION '1.4.4'")
  end

  def down do
    execute("DROP EXTENSION IF EXISTS pgmq CASCADE")
  end
end
