defmodule Pgflow.Repo.Migrations.CreateCompleteTaskFunction do
  @moduledoc """
  Creates complete_task() PostgreSQL function for DAG coordination.

  This is the most critical function in the DAG system. It:
  1. Marks a task as completed
  2. Decrements the step's remaining_tasks counter
  3. When remaining_tasks reaches 0, marks step as completed
  4. Cascades to dependent steps by decrementing their remaining_deps
  5. Triggers start_ready_steps to awaken newly ready steps

  Matches pgflow's cascading completion mechanism.
  """
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION complete_task(
      p_run_id UUID,
      p_step_slug TEXT,
      p_task_index INTEGER,
      p_output JSONB DEFAULT NULL
    )
    RETURNS JSONB
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_run_status TEXT;
      v_step_status TEXT;
      v_remaining_tasks INTEGER;
      v_step_completed BOOLEAN := FALSE;
      v_dependent_steps TEXT[];
      v_result JSONB;
    BEGIN
      -- PHASE 1: Acquire locks and validate run state
      -- Use FOR UPDATE to prevent concurrent modifications to the same run
      -- This ensures our task completion is atomic with respect to other tasks
      SELECT status INTO v_run_status
      FROM workflow_runs
      WHERE id = p_run_id
      FOR UPDATE;

      -- Early exit if run has already failed (cascade prevents further mutations)
      IF v_run_status = 'failed' THEN
        RAISE EXCEPTION 'Cannot complete task for failed run: %', p_run_id;
      END IF;

      -- PHASE 2: Mark the individual task as completed
      -- Only update if task is in 'started' state (prevents double-completion)
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

      -- PHASE 3: Lock the step state and decrement task counter
      SELECT status, remaining_tasks
      INTO v_step_status, v_remaining_tasks
      FROM workflow_step_states
      WHERE run_id = p_run_id AND step_slug = p_step_slug
      FOR UPDATE;

      -- Decrement the remaining_tasks counter for this step
      -- Key insight: When counter reaches 0, the step is complete and can be marked done
      -- This is faster than counting remaining tasks (O(1) vs O(n))
      UPDATE workflow_step_states
      SET remaining_tasks = remaining_tasks - 1
      WHERE run_id = p_run_id AND step_slug = p_step_slug
      RETURNING remaining_tasks INTO v_remaining_tasks;

      -- PHASE 4: If step is now complete, cascade to dependent steps
      IF v_remaining_tasks = 0 THEN
        -- Mark step as completed since all its tasks are done
        UPDATE workflow_step_states
        SET
          status = 'completed',
          completed_at = NOW()
        WHERE
          run_id = p_run_id
          AND step_slug = p_step_slug;

        v_step_completed := TRUE;

        -- Decrement remaining_deps for all dependent steps
        -- remaining_deps is the counter of unfulfilled dependencies for each step
        -- When a dependency completes, decrement remaining_deps for all waiting steps
        UPDATE workflow_step_states
        SET remaining_deps = remaining_deps - 1
        WHERE
          run_id = p_run_id
          AND remaining_deps > 0
          AND status = 'created';

        -- PHASE 5: Check if entire workflow is complete
        -- If no steps remain in non-completed states, workflow is done
        IF NOT EXISTS (
          SELECT 1 FROM workflow_step_states
          WHERE run_id = p_run_id AND status != 'completed'
        ) THEN
          UPDATE workflow_runs
          SET
            status = 'completed',
            completed_at = NOW()
          WHERE id = p_run_id;
        END IF;

        -- PHASE 6: Trigger readiness check for dependent steps
        -- start_ready_steps will enqueue any steps that now have no remaining dependencies
        PERFORM start_ready_steps(p_run_id);
      END IF;

      -- Build result JSON with completion info
      v_result := jsonb_build_object(
        'run_id', p_run_id,
        'step_slug', p_step_slug,
        'task_index', p_task_index,
        'step_completed', v_step_completed,
        'remaining_tasks', v_remaining_tasks
      );

      RETURN v_result;
    END;
    $$;
    """

    execute """
    COMMENT ON FUNCTION complete_task(UUID, TEXT, INTEGER, JSONB) IS
    'Marks a task as completed, decrements step counter, and cascades completion to dependent steps when step finishes.'
    """
  end

  def down do
    execute "DROP FUNCTION IF EXISTS complete_task(UUID, TEXT, INTEGER, JSONB);"
  end
end
