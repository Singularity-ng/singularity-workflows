defmodule Pgflow.Repo.Migrations.FinalCreateFlowFix do
  @moduledoc """
  Final fix for create_flow ambiguity: inline the queue creation logic directly
  instead of calling ensure_workflow_queue(), avoiding nested function call issues.

  This migration:
  1. Removes the PERFORM pgflow.ensure_workflow_queue() call
  2. Inlines the queue creation directly in create_flow
  3. Uses simplified logic without pgmq.list_queues() checking (pgmq.create is idempotent)
  """
  use Ecto.Migration

  def up do
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER)")

    execute("""
    CREATE FUNCTION pgflow.create_flow(
      in_slug TEXT,
      in_max_attempts INTEGER DEFAULT 3,
      in_timeout INTEGER DEFAULT 60
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
      v_slug TEXT;
      v_max INTEGER;
      v_timeout INTEGER;
    BEGIN
      v_slug := in_slug;
      v_max := in_max_attempts;
      v_timeout := in_timeout;

      -- Validate slug
      IF NOT pgflow.is_valid_slug(v_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', v_slug;
      END IF;

      -- Create or update workflow record
      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES (v_slug, v_max, v_timeout)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET max_attempts = EXCLUDED.max_attempts;

      -- Create queue (idempotent - pgmq.create returns existing if already exists)
      PERFORM pgmq.create(v_slug);

      -- Return workflow record
      RETURN QUERY
      SELECT workflows.workflow_slug,
             workflows.max_attempts,
             workflows.timeout,
             workflows.created_at
      FROM workflows
      WHERE workflows.workflow_slug = v_slug;
    END;
    $$;
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER)")

    execute("""
    CREATE FUNCTION pgflow.create_flow(
      in_slug TEXT,
      in_max_attempts INTEGER DEFAULT 3,
      in_timeout INTEGER DEFAULT 60
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
      IF NOT pgflow.is_valid_slug(in_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', in_slug;
      END IF;

      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES (in_slug, in_max_attempts, in_timeout)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET max_attempts = EXCLUDED.max_attempts;

      PERFORM pgflow.ensure_workflow_queue(in_slug);

      RETURN QUERY
      SELECT w.workflow_slug,
             w.max_attempts,
             w.timeout,
             w.created_at
      FROM workflows w
      WHERE w.workflow_slug = in_slug;
    END;
    $$;
    """)
  end
end
