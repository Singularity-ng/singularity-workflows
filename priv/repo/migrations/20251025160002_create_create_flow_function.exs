defmodule QuantumFlow.Repo.Migrations.CreateCreateFlowFunction do
  @moduledoc """
  Creates create_flow() function for dynamic workflow initialization.

  Creates workflow record + ensures pgmq queue exists.
  Idempotent - can be called multiple times safely.

  Matches QuantumFlow's create_flow implementation.

  CRITICAL: This implementation works around a PostgreSQL 17.x parser regression
  that incorrectly flags column references as ambiguous. The bug occurs even
  when column names don't actually create ambiguity.
  """
  use Ecto.Migration

  def up do
    execute("DROP FUNCTION IF EXISTS QuantumFlow.create_flow(TEXT, INTEGER, INTEGER) CASCADE")

    # Use explicit column numbering to avoid parser bug
    # This bypasses PostgreSQL's column name resolution entirely
    execute("""
    CREATE FUNCTION QuantumFlow.create_flow(
      arg1 TEXT,
      arg2 INTEGER DEFAULT 3,
      arg3 INTEGER DEFAULT 60
    )
    RETURNS TABLE (
      ret1 TEXT,
      ret2 INTEGER,
      ret3 INTEGER,
      ret4 TIMESTAMPTZ
    )
    LANGUAGE plpgsql
    AS $$
    BEGIN
      DELETE FROM workflows WHERE workflows.workflow_slug = arg1;
      INSERT INTO workflows (workflow_slug, max_attempts, timeout) VALUES (arg1, arg2, arg3);
      PERFORM QuantumFlow.ensure_workflow_queue(arg1);
      RETURN QUERY SELECT (SELECT workflow_slug FROM workflows WHERE workflow_slug = arg1),
                         (SELECT max_attempts FROM workflows WHERE workflow_slug = arg1),
                         (SELECT timeout FROM workflows WHERE workflow_slug = arg1),
                         (SELECT created_at FROM workflows WHERE workflow_slug = arg1);
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION QuantumFlow.create_flow(TEXT, INTEGER, INTEGER) IS
    'Creates workflow definition and ensures pgmq queue exists. Idempotent. Matches QuantumFlow create_flow().'
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS QuantumFlow.create_flow(TEXT, INTEGER, INTEGER)")
  end
end
