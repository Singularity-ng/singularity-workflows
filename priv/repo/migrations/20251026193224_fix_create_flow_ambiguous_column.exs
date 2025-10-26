defmodule Pgflow.Repo.Migrations.FixCreateFlowAmbiguousColumn do
  @moduledoc """
  Fixes ambiguous column reference in create_flow function by using explicit
  column aliases in the RETURN QUERY SELECT statement.
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

      -- Return workflow record with explicit aliases to avoid ambiguity
      RETURN QUERY
      SELECT w.workflow_slug, w.max_attempts, w.timeout, w.created_at
      FROM workflows w
      WHERE w.workflow_slug = p_workflow_slug;
    END;
    $$;
    """)
  end

  def down do
    # Revert to original function definition
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
