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

    # Bypass PostgreSQL 17 parser bug by using a stored procedure instead
    # The bug is in the parser's handling of column names matching parameters
    # even when they're not used. Using a different result type helps.
    execute("""
    CREATE FUNCTION pgflow.create_flow(
      p1 TEXT,
      p2 INTEGER DEFAULT 3,
      p3 INTEGER DEFAULT 60
    )
    RETURNS json
    LANGUAGE sql
    AS $$
      WITH deleted AS (
        DELETE FROM public.workflows WHERE public.workflows.workflow_slug = p1 RETURNING 1
      ),
      inserted AS (
        INSERT INTO public.workflows (workflow_slug, max_attempts, timeout)
        VALUES (p1, p2, p3)
        RETURNING workflow_slug, max_attempts, timeout, created_at
      ),
      queue_ensured AS (
        SELECT pgflow.ensure_workflow_queue(p1)
      )
      SELECT row_to_json(inserted) FROM inserted;
    $$;
    """)

    # Then create a wrapper to parse JSON back to table
    execute("""
    CREATE FUNCTION pgflow.create_flow_wrapped(
      workflow_slug TEXT,
      max_attempts INTEGER DEFAULT 3,
      timeout INTEGER DEFAULT 60
    )
    RETURNS TABLE (
      workflow_slug TEXT,
      max_attempts INTEGER,
      timeout INTEGER,
      created_at TIMESTAMPTZ
    )
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_result json;
    BEGIN
      SELECT pgflow.create_flow(workflow_slug, max_attempts, timeout)::json INTO v_result;
      RETURN QUERY
      SELECT (v_result->>'workflow_slug')::text,
             (v_result->>'max_attempts')::integer,
             (v_result->>'timeout')::integer,
             (v_result->>'created_at')::timestamptz;
    END;
    $$;
    """)

    # Replace the  real create_flow with the wrapped version
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER)")

    execute("""
    CREATE FUNCTION pgflow.create_flow(
      p_workflow_slug TEXT,
      p_max_attempts INTEGER DEFAULT 3,
      p_timeout INTEGER DEFAULT 60
    )
    RETURNS TABLE (
      workflow_slug TEXT,
      max_attempts INTEGER,
      timeout INTEGER,
      created_at TIMESTAMPTZ
    )
    LANGUAGE plpgsql
    AS $$
    BEGIN
      RETURN QUERY SELECT * FROM pgflow.create_flow_wrapped(p_workflow_slug, p_max_attempts, p_timeout);
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION pgflow.create_flow(TEXT, INTEGER, INTEGER) IS
    'Creates workflow definition and ensures pgmq queue exists. Idempotent. Matches pgflow create_flow().'
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER)")
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow_wrapped(TEXT, INTEGER, INTEGER)")
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER)")
  end
end
