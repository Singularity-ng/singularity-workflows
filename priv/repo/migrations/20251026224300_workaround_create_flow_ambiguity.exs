defmodule Pgflow.Repo.Migrations.WorkaroundCreateFlowAmbiguity do
  @moduledoc """
  Works around the ambiguous column issue by using a wrapper function that
  calls a SQL function directly instead of using plpgsql.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION pgflow.create_flow_sql(
      p_workflow_slug TEXT,
      p_max_attempts INTEGER,
      p_timeout INTEGER
    )
    RETURNS TABLE (
      workflow_slug TEXT,
      max_attempts INTEGER,
      timeout INTEGER,
      created_at TIMESTAMPTZ
    )
    LANGUAGE SQL
    STABLE
    AS $$
      SELECT w.workflow_slug, w.max_attempts, w.timeout, w.created_at
      FROM workflows w
      WHERE w.workflow_slug = $1
    $$;
    """)
    
    execute("""
    CREATE OR REPLACE FUNCTION pgflow.create_flow(
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
      IF NOT pgflow.is_valid_slug(p_workflow_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', p_workflow_slug;
      END IF;

      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES (p_workflow_slug, p_max_attempts, p_timeout)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET max_attempts = EXCLUDED.max_attempts;

      RETURN QUERY SELECT * FROM pgflow.create_flow_sql(p_workflow_slug, p_max_attempts, p_timeout);
    END;
    $$;
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER)")
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow_sql(TEXT, INTEGER, INTEGER)")
  end
end
