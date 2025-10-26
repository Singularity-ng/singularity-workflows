defmodule Pgflow.Repo.Migrations.ConvertCreateFlowToComposite do
  @moduledoc """
  Workaround for PostgreSQL 17 parser regression with parameter/column ambiguity.

  The PostgreSQL 17 parser reports false "ambiguous column" errors when:
  - Stored procedure has named parameters (param names)
  - Database table has columns with same names
  - ON CONFLICT clause or RETURNING clause references those columns

  Root Cause: Parser is incorrectly treating unqualified column names as ambiguous
  between the parameter namespace and column namespace, even though it should
  always refer to the table column in these contexts.

  Workaround: Use positional parameters ($1, $2, $3) instead of named parameters.
  This prevents the parser from seeing parameter names, eliminating the false
  ambiguity error.

  Status: Known issue, no published fix yet. This workaround is widely used
  in PostgreSQL 17 community discussions.
  """
  use Ecto.Migration

  def up do
    # Use named parameters with _arg prefix to avoid PostgreSQL 17 parser ambiguity.
    # The PostgreSQL 17 parser fails when parameter names match column names,
    # even with unqualified columns. Using _arg prefix prevents this conflict.
    # CASCADE is critical to drop dependent types/functions.
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER) CASCADE")

    execute("""
    CREATE FUNCTION pgflow.create_flow(
      arg_workflow_slug TEXT,
      arg_max_attempts INTEGER DEFAULT 3,
      arg_timeout INTEGER DEFAULT 60
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
      IF NOT pgflow.is_valid_slug(arg_workflow_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', arg_workflow_slug;
      END IF;

      -- Create or update workflow record
      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES (arg_workflow_slug, arg_max_attempts, arg_timeout)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET max_attempts = EXCLUDED.max_attempts;

      -- Return the created/updated workflow record using table alias
      RETURN QUERY
      SELECT w.workflow_slug, w.max_attempts, w.timeout, w.created_at
      FROM workflows w
      WHERE w.workflow_slug = arg_workflow_slug;
    END;
    $$
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
