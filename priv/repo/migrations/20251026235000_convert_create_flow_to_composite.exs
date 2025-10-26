defmodule Pgflow.Repo.Migrations.ConvertCreateFlowToComposite do
  @moduledoc """
  Convert create_flow from RETURNS TABLE to composite type return.

  The persistent ambiguity error in create_flow appears related to the
  interaction between RETURNS TABLE and parameter resolution. This migration
  attempts to bypass that by:

  1. Creating a workflow_result composite type
  2. Rewriting create_flow to return workflow_result instead of TABLE
  3. Handling the return value expansion in the caller

  This avoids the RETURNS TABLE column reference resolution that seems
  to trigger PostgreSQL's ambiguity detection.
  """
  use Ecto.Migration

  def up do
    # Create composite type for workflow result
    execute("""
    DROP TYPE IF EXISTS workflow_result CASCADE
    """)

    execute("""
    CREATE TYPE workflow_result AS (
      workflow_slug TEXT,
      max_attempts INTEGER,
      timeout INTEGER,
      created_at TIMESTAMPTZ
    )
    """)

    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER)")

    execute("""
    CREATE FUNCTION pgflow.create_flow(
      TEXT,
      INTEGER DEFAULT 3,
      INTEGER DEFAULT 60
    )
    RETURNS SETOF workflow_result
    LANGUAGE SQL
    STABLE
    AS $$
      WITH inserted_wf AS (
        INSERT INTO workflows (workflow_slug, max_attempts, timeout)
        VALUES ($1::text, $2::integer, $3::integer)
        ON CONFLICT (workflow_slug) DO UPDATE
        SET max_attempts = EXCLUDED.max_attempts
        RETURNING *
      )
      SELECT (w.workflow_slug, w.max_attempts, w.timeout, w.created_at)::workflow_result
      FROM inserted_wf w
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER)")
    execute("DROP TYPE IF EXISTS workflow_result CASCADE")

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
    $$
    """)
  end
end
