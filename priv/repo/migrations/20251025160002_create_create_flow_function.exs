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
    SET search_path = 'public'
    AS $$
    BEGIN
      -- Validate slug
      IF NOT pgflow.is_valid_slug(p_workflow_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', p_workflow_slug;
      END IF;

      -- Delete existing if present to avoid conflicts
      DELETE FROM workflows WHERE workflow_slug = p_workflow_slug;

      -- Create workflow record
      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES (p_workflow_slug, p_max_attempts, p_timeout);

      -- Ensure pgmq queue exists
      PERFORM pgflow.ensure_workflow_queue(p_workflow_slug);

      -- Return workflow record
      RETURN QUERY
      SELECT w.workflow_slug, w.max_attempts, w.timeout, w.created_at
      FROM workflows w
      WHERE w.workflow_slug = p_workflow_slug;
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
  end
end
