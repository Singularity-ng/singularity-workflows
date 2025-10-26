defmodule Pgflow.Repo.Migrations.RadicalColumnRename do
  @moduledoc """
  Radical fix: Use positional arguments and avoid any variable/column name conflicts.

  The ambiguity error persists because PostgreSQL 17 parser has issues when:
  - Parameter name: in_slug or p_workflow_slug
  - Column name: workflow_slug
  - Where clause: WHERE workflows.workflow_slug = variable_name

  Solution: Use $1, $2, $3 parameter substitution and cast explicitly.
  This bypasses the parser's variable/column reference confusion.
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

      -- Create or update workflow record
      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES ($1::text, $2::integer, $3::integer)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET max_attempts = EXCLUDED.max_attempts;

      -- Create queue (idempotent)
      PERFORM pgmq.create($1::text);

      -- Return workflow record using positional result type
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

      IF NOT pgflow.is_valid_slug(v_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', v_slug;
      END IF;

      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES (v_slug, v_max, v_timeout)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET max_attempts = EXCLUDED.max_attempts;

      PERFORM pgmq.create(v_slug);

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
end
