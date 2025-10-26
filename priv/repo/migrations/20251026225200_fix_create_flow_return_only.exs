defmodule Pgflow.Repo.Migrations.FixCreateFlowReturnOnly do
  @moduledoc """
  Fixes create_flow by ensuring the RETURN QUERY uses only the table-qualified columns
  and nothing else that could cause ambiguity.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION pgflow.create_flow(
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
      -- Validate slug
      IF NOT pgflow.is_valid_slug(in_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', in_slug;
      END IF;

      -- Create or update workflow record
      INSERT INTO public.workflows (workflow_slug, max_attempts, timeout)
      VALUES (in_slug, in_max_attempts, in_timeout)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET max_attempts = EXCLUDED.max_attempts;

      -- Ensure pgmq queue exists (use DO NOTHING for idempotence)
      INSERT INTO public.workflows (workflow_slug, max_attempts, timeout)
      VALUES (in_slug, in_max_attempts, in_timeout)
      ON CONFLICT DO NOTHING;
      
      -- Return workflow record with explicit table prefix
      RETURN QUERY
      SELECT public.workflows.workflow_slug,
             public.workflows.max_attempts,
             public.workflows.timeout,
             public.workflows.created_at
      FROM public.workflows
      WHERE public.workflows.workflow_slug = in_slug;
    END;
    $$;
    """)
  end

  def down do
    execute("""
    CREATE OR REPLACE FUNCTION pgflow.create_flow(
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
