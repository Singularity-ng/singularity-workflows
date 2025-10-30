defmodule QuantumFlow.Repo.Migrations.AddTypeViolationDetection do
  @moduledoc """
  Adds type violation detection to complete_task() for map step validation.

  Validates that single steps feeding map steps return arrays. If a type violation
  is detected:
  1. Mark run as failed immediately
  2. Archive all active pgmq messages
  3. Store violation details in error messages
  4. Prevent further execution

  Matches QuantumFlow's type safety for map steps.
  """
  use Ecto.Migration

  def up do
    # Drop current version
    execute("DROP FUNCTION IF EXISTS complete_task(UUID, TEXT, INTEGER, JSONB)")

    # Create version with type violation detection
    execute("""
    CREATE OR REPLACE FUNCTION complete_task(
      p_run_id UUID,
      p_step_slug TEXT,
      p_task_index INTEGER,
      p_output JSONB DEFAULT NULL
    )
    RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_run_status TEXT;
      v_workflow_slug TEXT;
      v_message_id BIGINT;
      v_remaining_tasks INTEGER;
      v_step_completed BOOLEAN := FALSE;
      v_type_violation_step TEXT;
    BEGIN
      -- Lock the run and get status + workflow_slug
      SELECT status, workflow_slug
      INTO v_run_status, v_workflow_slug
      FROM workflow_runs
      WHERE id = p_run_id
      FOR UPDATE;

      -- Guard: No mutations on failed runs
      IF v_run_status = 'failed' THEN
        RETURN;
      END IF;

      -- TYPE VIOLATION CHECK
      -- Check if this completion would violate map step type requirements
      -- Map steps expect array inputs, so single steps feeding them must return arrays
      SELECT dep.step_slug INTO v_type_violation_step
      FROM workflow_step_dependencies dep
      JOIN workflow_step_states dep_state
        ON dep_state.run_id = dep.run_id
        AND dep_state.step_slug = dep.step_slug
      WHERE dep.run_id = p_run_id
        AND dep.depends_on_step = p_step_slug
        AND dep_state.initial_tasks IS NULL  -- Map step (variable task count)
        AND (p_output IS NULL OR jsonb_typeof(p_output) != 'array')
      LIMIT 1;

      -- Handle type violation
      IF v_type_violation_step IS NOT NULL THEN
        -- Mark run as failed
        UPDATE workflow_runs
        SET
          status = 'failed',
          failed_at = NOW(),
          error_message = '[TYPE_VIOLATION] Map step ' || v_type_violation_step ||
                         ' expects array input but dependency ' || p_step_slug ||
                         ' produced ' || CASE WHEN p_output IS NULL THEN 'null'
                                             ELSE jsonb_typeof(p_output) END
        WHERE id = p_run_id;

        -- Archive all active messages
        PERFORM pgmq.archive(
          v_workflow_slug,
          array_agg(st.message_id)
        )
        FROM workflow_step_tasks st
        WHERE st.run_id = p_run_id
          AND st.status IN ('queued', 'started')
          AND st.message_id IS NOT NULL
        HAVING count(*) > 0;

        -- Mark current task as failed with violation message
        UPDATE workflow_step_tasks
        SET
          status = 'failed',
          failed_at = NOW(),
          output = p_output,
          error_message = '[TYPE_VIOLATION] Produced ' ||
                         CASE WHEN p_output IS NULL THEN 'null'
                              ELSE jsonb_typeof(p_output) END ||
                         ' instead of array for map step ' || v_type_violation_step
        WHERE run_id = p_run_id
          AND step_slug = p_step_slug
          AND task_index = p_task_index;

        -- Mark step state as failed
        UPDATE workflow_step_states
        SET
          status = 'failed',
          failed_at = NOW(),
          error_message = '[TYPE_VIOLATION] Produced ' ||
                         CASE WHEN p_output IS NULL THEN 'null'
                              ELSE jsonb_typeof(p_output) END ||
                         ' instead of array for map step ' || v_type_violation_step
        WHERE run_id = p_run_id
          AND step_slug = p_step_slug;

        RETURN;
      END IF;

      -- NORMAL COMPLETION PATH (no type violation)

      -- Get message_id for archiving
      SELECT message_id INTO v_message_id
      FROM workflow_step_tasks
      WHERE run_id = p_run_id
        AND step_slug = p_step_slug
        AND task_index = p_task_index;

      -- Mark task as completed
      UPDATE workflow_step_tasks
      SET
        status = 'completed',
        output = p_output,
        completed_at = NOW()
      WHERE
        run_id = p_run_id
        AND step_slug = p_step_slug
        AND task_index = p_task_index
        AND status = 'started';

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Task not found or not in started state: run_id=%, step_slug=%, task_index=%',
          p_run_id, p_step_slug, p_task_index;
      END IF;

      -- Archive pgmq message
      IF v_message_id IS NOT NULL THEN
        PERFORM pgmq.archive(v_workflow_slug, ARRAY[v_message_id]);
      END IF;

      -- Decrement step's remaining_tasks counter
      UPDATE workflow_step_states
      SET remaining_tasks = remaining_tasks - 1
      WHERE run_id = p_run_id
        AND step_slug = p_step_slug
      RETURNING remaining_tasks INTO v_remaining_tasks;

      -- Check if step completed (remaining_tasks = 0)
      IF v_remaining_tasks = 0 THEN
        -- Mark step as completed
        UPDATE workflow_step_states
        SET
          status = 'completed',
          completed_at = NOW()
        WHERE
          run_id = p_run_id
          AND step_slug = p_step_slug;

        v_step_completed := TRUE;

        -- Find dependent children in deterministic order, lock them, update remaining_deps
        WITH child_steps AS (
          SELECT dep.step_slug AS child_step_slug
          FROM workflow_step_dependencies dep
          WHERE dep.run_id = p_run_id
            AND dep.depends_on_step = p_step_slug
          ORDER BY dep.step_slug
        ),
        child_steps_lock AS (
          SELECT *
          FROM workflow_step_states
          WHERE run_id = p_run_id
            AND step_slug IN (SELECT child_step_slug FROM child_steps)
          FOR UPDATE
        ),
        child_steps_update AS (
          -- Decrement remaining_deps and resolve initial_tasks for map children
          UPDATE workflow_step_states child_state
          SET
            remaining_deps = child_state.remaining_deps - 1,
            initial_tasks = CASE
              WHEN ws.step_type = 'map' AND child_state.initial_tasks IS NULL THEN
                CASE
                  WHEN parent_ws.step_type = 'map' THEN (
                    -- Count completed parent tasks and add 1 for the current completing task
                    SELECT COUNT(*)::int + 1
                    FROM workflow_step_tasks parent_tasks
                    WHERE parent_tasks.run_id = p_run_id
                      AND parent_tasks.step_slug = p_step_slug
                      AND parent_tasks.status = 'completed'
                      AND parent_tasks.task_index != p_task_index
                  )
                  WHEN parent_ws.step_type = 'single' THEN
                    CASE
                      WHEN p_output IS NOT NULL AND jsonb_typeof(p_output) = 'array' THEN jsonb_array_length(p_output)
                      ELSE NULL
                    END
                  ELSE child_state.initial_tasks
                END
              ELSE child_state.initial_tasks
            END
          FROM child_steps children
          JOIN workflow_steps ws ON ws.workflow_slug = v_workflow_slug AND ws.step_slug = children.child_step_slug
          JOIN workflow_steps parent_ws ON parent_ws.workflow_slug = v_workflow_slug AND parent_ws.step_slug = p_step_slug
          WHERE child_state.run_id = p_run_id
            AND child_state.step_slug = children.child_step_slug
          RETURNING child_state.*
        )
        SELECT 1;

        -- Decrement run's remaining_steps counter
        UPDATE workflow_runs
        SET remaining_steps = remaining_steps - 1
        WHERE id = p_run_id;

        -- After step completion, cascade any taskless steps (empty-array propagation)
        PERFORM QuantumFlow.cascade_complete_taskless_steps(p_run_id);

        -- Trigger start_ready_steps to awaken newly ready steps
        PERFORM start_ready_steps(p_run_id);

        -- Then check if run is complete and aggregate leaf outputs
        PERFORM QuantumFlow.maybe_complete_run(p_run_id);
      END IF;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION complete_task(UUID, TEXT, INTEGER, JSONB) IS
    'Completes task with type violation detection for map steps. Archives pgmq message, cascades to dependencies. Matches QuantumFlow implementation.'
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS complete_task(UUID, TEXT, INTEGER, JSONB)")

    # Restore version without type checking
    execute("""
    CREATE OR REPLACE FUNCTION complete_task(
      p_run_id UUID,
      p_step_slug TEXT,
      p_task_index INTEGER,
      p_output JSONB DEFAULT NULL
    )
    RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_run_status TEXT;
      v_workflow_slug TEXT;
      v_message_id BIGINT;
      v_remaining_tasks INTEGER;
    BEGIN
      SELECT status, workflow_slug
      INTO v_run_status, v_workflow_slug
      FROM workflow_runs
      WHERE id = p_run_id
      FOR UPDATE;

      IF v_run_status = 'failed' THEN
        RETURN;
      END IF;

      SELECT message_id INTO v_message_id
      FROM workflow_step_tasks
      WHERE run_id = p_run_id
        AND step_slug = p_step_slug
        AND task_index = p_task_index;

      UPDATE workflow_step_tasks
      SET
        status = 'completed',
        output = p_output,
        completed_at = NOW()
      WHERE
        run_id = p_run_id
        AND step_slug = p_step_slug
        AND task_index = p_task_index
        AND status = 'started';

      IF v_message_id IS NOT NULL THEN
        PERFORM pgmq.archive(v_workflow_slug, ARRAY[v_message_id]);
      END IF;

      UPDATE workflow_step_states
      SET remaining_tasks = remaining_tasks - 1
      WHERE run_id = p_run_id
        AND step_slug = p_step_slug
      RETURNING remaining_tasks INTO v_remaining_tasks;

      IF v_remaining_tasks = 0 THEN
        UPDATE workflow_step_states
        SET
          status = 'completed',
          completed_at = NOW()
        WHERE
          run_id = p_run_id
          AND step_slug = p_step_slug;

        UPDATE workflow_step_states
        SET remaining_deps = remaining_deps - 1
        WHERE
          run_id = p_run_id
          AND step_slug IN (
            SELECT dep.step_slug
            FROM workflow_step_dependencies dep
            WHERE dep.run_id = p_run_id
              AND dep.depends_on_step = p_step_slug
          );

        UPDATE workflow_runs
        SET remaining_steps = remaining_steps - 1
        WHERE id = p_run_id;

        PERFORM QuantumFlow.maybe_complete_run(p_run_id);
        PERFORM start_ready_steps(p_run_id);
      END IF;
    END;
    $$;
    """)
  end
end
