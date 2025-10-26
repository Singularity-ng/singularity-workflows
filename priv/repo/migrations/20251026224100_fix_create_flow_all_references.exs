defmodule Pgflow.Repo.Migrations.FixCreateFlowAllReferences do
  @moduledoc """
  Fixes ALL ambiguous references in create_flow by ensuring every reference 
  is fully qualified.
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
    DECLARE
      v_workflow_slug TEXT := p_workflow_slug;
      v_max_attempts INTEGER := p_max_attempts;
      v_timeout INTEGER := p_timeout;
    BEGIN
      -- Validate slug
      IF NOT pgflow.is_valid_slug(v_workflow_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', v_workflow_slug;
      END IF;

      -- Create or update workflow record
      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES (v_workflow_slug, v_max_attempts, v_timeout)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET max_attempts = EXCLUDED.max_attempts;

      -- Ensure pgmq queue exists
      PERFORM pgflow.ensure_workflow_queue(v_workflow_slug);

      -- Return workflow record
      RETURN QUERY
      SELECT workflows.workflow_slug,
             workflows.max_attempts,
             workflows.timeout,
             workflows.created_at
      FROM workflows
      WHERE workflows.workflow_slug = v_workflow_slug;
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
end
