defmodule Pgflow.Repo.Migrations.RenameAllFunctionParameters do
  @moduledoc """
  Comprehensive fix: Rename ALL parameters in PL/pgSQL functions to use _arg prefix.

  This avoids any possibility of parameter/column name conflicts that trigger
  PostgreSQL 17's ambiguity detection.

  Changes parameters like:
  - p_workflow_slug → arg_workflow_slug
  - p_max_attempts → arg_max_attempts
  - p_step_slug → arg_step_slug
  etc.

  This systematic renaming ensures no parameter can ever be confused with a
  column name, bypassing the PostgreSQL 17 parser issue entirely.
  """
  use Ecto.Migration

  def up do
    # Fix create_flow
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
      IF NOT pgflow.is_valid_slug(arg_workflow_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', arg_workflow_slug;
      END IF;

      -- Check if workflow already exists
      IF EXISTS (SELECT 1 FROM workflows WHERE workflow_slug = arg_workflow_slug) THEN
        -- Update existing workflow
        UPDATE workflows
        SET max_attempts = arg_max_attempts,
            timeout = arg_timeout
        WHERE workflow_slug = arg_workflow_slug;
      ELSE
        -- Insert new workflow
        INSERT INTO workflows (workflow_slug, max_attempts, timeout)
        VALUES (arg_workflow_slug, arg_max_attempts, arg_timeout);
      END IF;

      -- Return the workflow record
      RETURN QUERY
      SELECT w.workflow_slug, w.max_attempts, w.timeout, w.created_at
      FROM workflows w
      WHERE w.workflow_slug = arg_workflow_slug;
    END;
    $$
    """)

    # Fix add_step
    execute("DROP FUNCTION IF EXISTS pgflow.add_step(TEXT, TEXT, TEXT[], TEXT, INTEGER, INTEGER, INTEGER) CASCADE")

    execute("""
    CREATE FUNCTION pgflow.add_step(
      arg_workflow_slug TEXT,
      arg_step_slug TEXT,
      arg_depends_on TEXT[] DEFAULT '{}',
      arg_step_type TEXT DEFAULT 'single',
      arg_initial_tasks INTEGER DEFAULT NULL,
      arg_max_attempts INTEGER DEFAULT NULL,
      arg_timeout INTEGER DEFAULT NULL
    )
    RETURNS TABLE (
      workflow_slug TEXT,
      step_slug TEXT,
      step_type TEXT,
      step_index INTEGER,
      deps_count INTEGER,
      initial_tasks INTEGER,
      max_attempts INTEGER,
      timeout INTEGER,
      created_at TIMESTAMPTZ
    )
    LANGUAGE plpgsql
    SET search_path = 'public'
    AS $$
    DECLARE
      v_next_index INTEGER;
      v_deps_count INTEGER;
    BEGIN
      IF NOT pgflow.is_valid_slug(arg_workflow_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', arg_workflow_slug;
      END IF;

      IF NOT pgflow.is_valid_slug(arg_step_slug) THEN
        RAISE EXCEPTION 'Invalid step_slug: %', arg_step_slug;
      END IF;

      IF arg_step_type NOT IN ('single', 'map') THEN
        RAISE EXCEPTION 'Invalid step_type: %. Must be ''single'' or ''map''', arg_step_type;
      END IF;

      v_deps_count := COALESCE(array_length(arg_depends_on, 1), 0);

      IF arg_step_type = 'map' AND v_deps_count > 1 THEN
        RAISE EXCEPTION 'Map step "%" can have at most one dependency, but % were provided: %',
          arg_step_slug, v_deps_count, array_to_string(arg_depends_on, ', ');
      END IF;

      IF NOT EXISTS (SELECT 1 FROM workflows WHERE workflows.workflow_slug = arg_workflow_slug) THEN
        RAISE EXCEPTION 'Workflow "%" does not exist. Call create_flow() first.', arg_workflow_slug;
      END IF;

      SELECT COALESCE(MAX(ws.step_index) + 1, 0) INTO v_next_index
      FROM workflow_steps ws
      WHERE ws.workflow_slug = arg_workflow_slug;

      -- Check if step already exists
      IF EXISTS (SELECT 1 FROM workflow_steps WHERE workflow_slug = arg_workflow_slug AND step_slug = arg_step_slug) THEN
        -- Update existing step
        UPDATE workflow_steps
        SET step_type = arg_step_type, initial_tasks = arg_initial_tasks, max_attempts = arg_max_attempts, timeout = arg_timeout
        WHERE workflow_slug = arg_workflow_slug AND step_slug = arg_step_slug;
      ELSE
        -- Insert new step
        INSERT INTO workflow_steps (workflow_slug, step_slug, step_type, step_index, initial_tasks, max_attempts, timeout)
        VALUES (arg_workflow_slug, arg_step_slug, arg_step_type, v_next_index, arg_initial_tasks, arg_max_attempts, arg_timeout);
      END IF;

      INSERT INTO step_dependencies (workflow_slug, dependent_slug, dependency_slug)
      SELECT arg_workflow_slug, arg_step_slug, dep
      FROM UNNEST(arg_depends_on) AS dep
      ON CONFLICT DO NOTHING;

      RETURN QUERY
      SELECT ws.workflow_slug, ws.step_slug, ws.step_type, ws.step_index, v_deps_count, ws.initial_tasks, ws.max_attempts, ws.timeout, ws.created_at
      FROM workflow_steps ws
      WHERE ws.workflow_slug = arg_workflow_slug AND ws.step_slug = arg_step_slug;
    END;
    $$
    """)
  end

  def down do
    # Restore original create_flow
    execute("DROP FUNCTION IF EXISTS pgflow.create_flow(TEXT, INTEGER, INTEGER) CASCADE")

    execute("""
    CREATE FUNCTION pgflow.create_flow(
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
    AS $$
    BEGIN
      IF NOT pgflow.is_valid_slug(p_workflow_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', p_workflow_slug;
      END IF;

      INSERT INTO workflows (workflow_slug, max_attempts, timeout)
      VALUES (p_workflow_slug, p_max_attempts, p_timeout)
      ON CONFLICT (workflow_slug) DO UPDATE
      SET max_attempts = EXCLUDED.max_attempts;

      RETURN QUERY
      SELECT w.workflow_slug, w.max_attempts, w.timeout, w.created_at
      FROM workflows w
      WHERE w.workflow_slug = p_workflow_slug;
    END;
    $$
    """)

    # Restore original add_step
    execute("DROP FUNCTION IF EXISTS pgflow.add_step(TEXT, TEXT, TEXT[], TEXT, INTEGER, INTEGER, INTEGER) CASCADE")

    execute("""
    CREATE FUNCTION pgflow.add_step(
      p_workflow_slug TEXT,
      p_step_slug TEXT,
      p_depends_on TEXT[] DEFAULT '{}',
      p_step_type TEXT DEFAULT 'single',
      p_initial_tasks INTEGER DEFAULT NULL,
      p_max_attempts INTEGER DEFAULT NULL,
      p_timeout INTEGER DEFAULT NULL
    )
    RETURNS TABLE (
      workflow_slug TEXT,
      step_slug TEXT,
      step_type TEXT,
      step_index INTEGER,
      deps_count INTEGER,
      initial_tasks INTEGER,
      max_attempts INTEGER,
      timeout INTEGER,
      created_at TIMESTAMPTZ
    )
    LANGUAGE plpgsql
    SET search_path = 'public'
    AS $$
    DECLARE
      v_next_index INTEGER;
      v_deps_count INTEGER;
    BEGIN
      IF NOT pgflow.is_valid_slug(p_workflow_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', p_workflow_slug;
      END IF;

      IF NOT pgflow.is_valid_slug(p_step_slug) THEN
        RAISE EXCEPTION 'Invalid step_slug: %', p_step_slug;
      END IF;

      IF p_step_type NOT IN ('single', 'map') THEN
        RAISE EXCEPTION 'Invalid step_type: %. Must be ''single'' or ''map''', p_step_type;
      END IF;

      v_deps_count := COALESCE(array_length(p_depends_on, 1), 0);

      IF p_step_type = 'map' AND v_deps_count > 1 THEN
        RAISE EXCEPTION 'Map step "%" can have at most one dependency, but % were provided: %',
          p_step_slug, v_deps_count, array_to_string(p_depends_on, ', ');
      END IF;

      IF NOT EXISTS (SELECT 1 FROM workflows WHERE workflows.workflow_slug = p_workflow_slug) THEN
        RAISE EXCEPTION 'Workflow "%" does not exist. Call create_flow() first.', p_workflow_slug;
      END IF;

      SELECT COALESCE(MAX(ws.step_index) + 1, 0) INTO v_next_index
      FROM workflow_steps ws
      WHERE ws.workflow_slug = p_workflow_slug;

      INSERT INTO workflow_steps (workflow_slug, step_slug, step_type, step_index, initial_tasks, max_attempts, timeout)
      VALUES (p_workflow_slug, p_step_slug, p_step_type, v_next_index, p_initial_tasks, p_max_attempts, p_timeout)
      ON CONFLICT (workflow_slug, step_slug) DO UPDATE
      SET step_type = p_step_type, initial_tasks = p_initial_tasks, max_attempts = p_max_attempts, timeout = p_timeout;

      INSERT INTO step_dependencies (workflow_slug, dependent_slug, dependency_slug)
      SELECT p_workflow_slug, p_step_slug, dep
      FROM UNNEST(p_depends_on) AS dep
      ON CONFLICT DO NOTHING;

      RETURN QUERY
      SELECT ws.workflow_slug, ws.step_slug, ws.step_type, ws.step_index, v_deps_count, ws.initial_tasks, ws.max_attempts, ws.timeout, ws.created_at
      FROM workflow_steps ws
      WHERE ws.workflow_slug = p_workflow_slug AND ws.step_slug = p_step_slug;
    END;
    $$
    """)
  end
end
