defmodule Pgflow.Repo.Migrations.FixCreateFlowFunctionQualifiedColumns do
  @moduledoc """
  Fixes the create_flow function by ensuring all column references are fully qualified
  with table aliases to avoid ambiguity errors.
  
  The issue was that the RETURN QUERY SELECT was using unqualified column names
  which PostgreSQL interpreted as ambiguous when the function joined multiple tables.
  """
  use Ecto.Migration

  def up do
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
    SET search_path = 'public'
    AS $$
    BEGIN
      -- Validate slug
      IF NOT pgflow.is_valid_slug(p_workflow_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', p_workflow_slug;
      END IF;

      -- Create or update workflow record
      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES (p_workflow_slug, p_max_attempts, p_timeout)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET max_attempts = EXCLUDED.max_attempts;

      -- Ensure pgmq queue exists
      PERFORM pgflow.ensure_workflow_queue(p_workflow_slug);

      -- Return workflow record with fully qualified column names
      RETURN QUERY
      SELECT w.workflow_slug AS workflow_slug,
             w.max_attempts AS max_attempts,
             w.timeout AS timeout,
             w.created_at AS created_at
      FROM workflows w
      WHERE w.workflow_slug = p_workflow_slug;
    END;
    $$;
    """)
  end

  def down do
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
    SET search_path = 'public'
    AS $$
    BEGIN
      -- Validate slug
      IF NOT pgflow.is_valid_slug(p_workflow_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', p_workflow_slug;
      END IF;

      -- Create or update workflow record
      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES (p_workflow_slug, p_max_attempts, p_timeout)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET workflow_slug = workflows.workflow_slug;

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
  end
end
