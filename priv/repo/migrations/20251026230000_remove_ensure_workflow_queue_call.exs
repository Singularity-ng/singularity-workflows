defmodule Pgflow.Repo.Migrations.RemoveEnsureWorkflowQueueCall do
  @moduledoc """
  Final solution: Remove the PERFORM pgflow.ensure_workflow_queue() call entirely.

  The ambiguity error persists in create_flow even after 6+ different migration
  approaches because it appears to originate from the nested function call to
  ensure_workflow_queue(). Rather than fight PostgreSQL's parser, we eliminate
  the problematic nested call.

  Queue creation can be handled:
  1. Lazily on first message (pgmq.create is idempotent)
  2. Explicitly in Elixir before calling create_flow
  3. As a separate procedure call

  This migration takes approach #1 - let pgmq.create() handle idempotence.
  """
  use Ecto.Migration

  def up do
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER)")

    execute("""
    CREATE FUNCTION pgflow.create_flow(
      TEXT,
      INTEGER DEFAULT 3,
      INTEGER DEFAULT 60
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
      -- Validate slug
      IF NOT pgflow.is_valid_slug($1::text) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', $1::text;
      END IF;

      -- Create or update workflow record ONLY
      -- Queue will be created lazily on first use (pgmq.create is idempotent)
      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES ($1::text, $2::integer, $3::integer)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET max_attempts = EXCLUDED.max_attempts;

      -- Return the created/updated workflow record
      RETURN QUERY
      SELECT
        workflows.workflow_slug,
        workflows.max_attempts,
        workflows.timeout,
        workflows.created_at
      FROM workflows
      WHERE workflows.workflow_slug = $1::text;
    END;
    $$;
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER)")

    execute("""
    CREATE FUNCTION pgflow.create_flow(
      TEXT,
      INTEGER DEFAULT 3,
      INTEGER DEFAULT 60
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
      -- Validate slug
      IF NOT pgflow.is_valid_slug($1::text) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', $1::text;
      END IF;

      -- Create or update workflow record
      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES ($1::text, $2::integer, $3::integer)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET max_attempts = EXCLUDED.max_attempts;

      -- Create queue (idempotent - pgmq.create returns existing if already exists)
      PERFORM pgmq.create($1::text);

      -- Return workflow record
      RETURN QUERY
      SELECT
        workflows.workflow_slug,
        workflows.max_attempts,
        workflows.timeout,
        workflows.created_at
      FROM workflows
      WHERE workflows.workflow_slug = $1::text;
    END;
    $$;
    """)
  end
end
