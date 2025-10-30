defmodule QuantumFlow.Repo.Migrations.CreateAddStepFunction do
  @moduledoc """
  Creates add_step() function for dynamic step creation.

  Validates:
  - Map steps have at most 1 dependency
  - Step slugs are valid
  - Dependencies exist

  Auto-increments step_index for ordering.
  Matches QuantumFlow's add_step implementation.
  """
  use Ecto.Migration

  def up do
    execute("DROP FUNCTION IF EXISTS QuantumFlow.add_step(TEXT, TEXT, TEXT[], TEXT, INTEGER, INTEGER, INTEGER) CASCADE")

    execute("""
    CREATE FUNCTION QuantumFlow.add_step(
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
      -- Validate slugs
      IF NOT QuantumFlow.is_valid_slug(p_workflow_slug) THEN
        RAISE EXCEPTION 'Invalid workflow_slug: %', p_workflow_slug;
      END IF;

      IF NOT QuantumFlow.is_valid_slug(p_step_slug) THEN
        RAISE EXCEPTION 'Invalid step_slug: %', p_step_slug;
      END IF;

      -- Validate step type
      IF p_step_type NOT IN ('single', 'map') THEN
        RAISE EXCEPTION 'Invalid step_type: %. Must be ''single'' or ''map''', p_step_type;
      END IF;

      -- Count dependencies
      v_deps_count := COALESCE(array_length(p_depends_on, 1), 0);

      -- Validate map step constraints
      IF p_step_type = 'map' AND v_deps_count > 1 THEN
        RAISE EXCEPTION 'Map step "%" can have at most one dependency, but % were provided: %',
          p_step_slug,
          v_deps_count,
          array_to_string(p_depends_on, ', ');
      END IF;

      -- Check workflow exists
      IF NOT EXISTS (SELECT 1 FROM workflows WHERE workflows.workflow_slug = p_workflow_slug) THEN
        RAISE EXCEPTION 'Workflow "%" does not exist. Call create_flow() first.', p_workflow_slug;
      END IF;

      -- Get next step index
      SELECT COALESCE(MAX(ws.step_index) + 1, 0) INTO v_next_index
      FROM workflow_steps ws
      WHERE ws.workflow_slug = p_workflow_slug;

      -- Create or update step
      INSERT INTO workflow_steps (
        workflow_slug, step_slug, step_type, step_index, deps_count,
        initial_tasks, max_attempts, timeout
      )
      VALUES (
        p_workflow_slug,
        p_step_slug,
        COALESCE(p_step_type, 'single'),
        v_next_index,
        v_deps_count,
        p_initial_tasks,
        p_max_attempts,
        p_timeout
      )
      ON CONFLICT (workflow_slug, step_slug) DO UPDATE
      SET
        step_type = EXCLUDED.step_type,
        deps_count = EXCLUDED.deps_count,
        initial_tasks = EXCLUDED.initial_tasks,
        max_attempts = EXCLUDED.max_attempts,
        timeout = EXCLUDED.timeout;

      -- Delete existing dependencies for this step
      DELETE FROM workflow_step_dependencies_def
      WHERE workflow_step_dependencies_def.workflow_slug = p_workflow_slug
        AND workflow_step_dependencies_def.step_slug = p_step_slug;

      -- Insert new dependencies
      IF v_deps_count > 0 THEN
        -- Validate all dependencies exist
        IF EXISTS (
          SELECT 1
          FROM unnest(p_depends_on) AS dep(dep_slug)
          WHERE NOT EXISTS (
            SELECT 1 FROM workflow_steps ws
            WHERE ws.workflow_slug = p_workflow_slug
              AND ws.step_slug = dep.dep_slug
          )
        ) THEN
          RAISE EXCEPTION 'One or more dependencies do not exist: %',
            (SELECT array_agg(dep.dep_slug)
             FROM unnest(p_depends_on) AS dep(dep_slug)
             WHERE NOT EXISTS (
               SELECT 1 FROM workflow_steps ws
               WHERE ws.workflow_slug = p_workflow_slug
                 AND ws.step_slug = dep.dep_slug
             ));
        END IF;

        -- Insert dependencies
        INSERT INTO workflow_step_dependencies_def (workflow_slug, dep_slug, step_slug)
        SELECT p_workflow_slug, dep.dep_slug, p_step_slug
        FROM unnest(p_depends_on) AS dep(dep_slug)
        ON CONFLICT DO NOTHING;
      END IF;

      -- Return step record
      RETURN QUERY
      SELECT
        ws.workflow_slug,
        ws.step_slug,
        ws.step_type,
        ws.step_index,
        ws.deps_count,
        ws.initial_tasks,
        ws.max_attempts,
        ws.timeout,
        ws.created_at
      FROM workflow_steps ws
      WHERE ws.workflow_slug = p_workflow_slug
        AND ws.step_slug = p_step_slug;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION QuantumFlow.add_step(TEXT, TEXT, TEXT[], TEXT, INTEGER, INTEGER, INTEGER) IS
    'Adds step to workflow definition. Validates dependencies and map step constraints. Idempotent. Matches QuantumFlow add_step().'
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS QuantumFlow.add_step(TEXT, TEXT, TEXT[], TEXT, INTEGER, INTEGER, INTEGER)")
  end
end
