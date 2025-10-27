defmodule Pgflow.Repo.Migrations.AddPgmqExtension do
  use Ecto.Migration

  def up do
    # Create pgmq extension (PostgreSQL Message Queue)
    # Matches pgflow's architecture: https://github.com/tembo-io/pgmq
    # Note: Gracefully handles systems where pgmq is not installed
    # (e.g., postgres:15-alpine in CI). The extension is optional for tests
    # since Elixir code can fall back to schema-based message queueing.
    #
    # Use raw SQL with BEGIN/EXCEPTION to handle missing extension at DB level
    execute("""
    DO $$
    BEGIN
      CREATE EXTENSION IF NOT EXISTS pgmq;
    EXCEPTION WHEN OTHERS THEN
      -- Extension not available on this PostgreSQL installation
      -- This is expected and OK - pgmq is optional
      NULL;
    END $$;
    """)
  end

  def down do
    execute("""
    DO $$
    BEGIN
      DROP EXTENSION IF EXISTS pgmq CASCADE;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END $$;
    """)
  end
end
