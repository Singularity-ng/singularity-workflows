defmodule Pgflow.Repo.Migrations.RenameCreateFlowParameters do
  @moduledoc """
  Resolves PostgreSQL 17 column ambiguity by renaming parameters to non-conflicting names.

  Changes:
  - p_workflow_slug → in_slug
  - p_max_attempts → in_max_attempts
  - p_timeout → in_timeout

  This avoids the parser confusion where parameter names conflict with column references.
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
      IF NOT pgflow.is_valid_slug(p_workflow_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', p_workflow_slug;
      END IF;

      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES (p_workflow_slug, p_max_attempts, p_timeout)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET max_attempts = EXCLUDED.max_attempts;

      PERFORM pgflow.ensure_workflow_queue(p_workflow_slug);

      RETURN QUERY
      SELECT w.workflow_slug,
             w.max_attempts,
             w.timeout,
             w.created_at
      FROM workflows w
      WHERE w.workflow_slug = p_workflow_slug;
    END;
    $$;
    """)
  end
end
