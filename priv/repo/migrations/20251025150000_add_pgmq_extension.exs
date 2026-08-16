defmodule Singularity.Workflow.Repo.Migrations.AddPgmqExtension do
  use Ecto.Migration

  def up do
    # TEMP(disposable-test): pgmq functions are pre-loaded directly from the
    # Nix-store pure-SQL script (no .so), so CREATE EXTENSION is unavailable on
    # the disposable instance. Guard it so migration proceeds when pgmq is
    # already present. Production instances install the real extension.
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                     WHERE n.nspname='pgmq' AND p.proname='create') THEN
        CREATE EXTENSION IF NOT EXISTS pgmq;
      END IF;
    END$$;
    """)
  end

  def down do
    execute("DROP EXTENSION IF EXISTS pgmq CASCADE")
  end
end
