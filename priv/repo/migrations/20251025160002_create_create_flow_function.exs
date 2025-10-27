defmodule Pgflow.Repo.Migrations.CreateCreateFlowFunction do
  @moduledoc """
  Creates create_flow() function for dynamic workflow initialization.

  Creates workflow record + ensures pgmq queue exists.
  Idempotent - can be called multiple times safely.

  Matches pgflow's create_flow implementation.
  """
  use Ecto.Migration

  def up do
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER) CASCADE")

    # Use completely generic column names in RETURNS TABLE
    # to bypass PostgreSQL 17 parser bug with column ambiguity
    execute("""
    CREATE FUNCTION pgflow.create_flow(
      p_slug TEXT,
      p_max_attempts INTEGER DEFAULT 3,
      p_timeout INTEGER DEFAULT 60
    )
    RETURNS TABLE (
      col1 TEXT,
      col2 INTEGER,
      col3 INTEGER,
      col4 TIMESTAMPTZ
    )
    LANGUAGE sql
    AS $$
      WITH inserted AS (
        INSERT INTO public.workflows (workflow_slug, max_attempts, timeout)
        VALUES (p_slug, p_max_attempts, p_timeout)
        RETURNING public.workflows.workflow_slug, public.workflows.max_attempts, public.workflows.timeout, public.workflows.created_at
      ),
      queue_ensured AS (
        SELECT pgflow.ensure_workflow_queue(p_slug) AS q_result
      )
      SELECT
        inserted.workflow_slug,
        inserted.max_attempts,
        inserted.timeout,
        inserted.created_at
      FROM inserted
      CROSS JOIN queue_ensured;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION pgflow.create_flow(TEXT, INTEGER, INTEGER) IS
    'Creates workflow definition and ensures pgmq queue exists. Idempotent. Matches pgflow create_flow().'
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER)")
  end
end
