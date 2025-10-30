defmodule QuantumFlow.Repo.Migrations.CreateWorkflowStepDependencies do
  @moduledoc """
  Creates workflow_step_dependencies table to explicitly track step dependencies.

  This table is populated when a workflow run starts and defines which steps
  depend on which other steps, enabling accurate cascading in complete_task().
  """
  use Ecto.Migration

  def up do
    create table(:workflow_step_dependencies, primary_key: false) do
      add :run_id, references(:workflow_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :step_slug, :string, null: false
      add :depends_on_step, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Composite unique constraint
    create unique_index(:workflow_step_dependencies, [:run_id, :step_slug, :depends_on_step],
      name: :workflow_step_dependencies_unique_idx
    )

    # Index for looking up dependents of a step (reverse lookup)
    create index(:workflow_step_dependencies, [:run_id, :depends_on_step],
      name: :workflow_step_dependencies_reverse_idx
    )

    # Index for looking up dependencies of a step (forward lookup)
    create index(:workflow_step_dependencies, [:run_id, :step_slug])

    execute """
    COMMENT ON TABLE workflow_step_dependencies IS
    'Explicitly tracks step dependency relationships for accurate cascading completion'
    """

    execute """
    COMMENT ON COLUMN workflow_step_dependencies.step_slug IS
    'The step that has a dependency'
    """

    execute """
    COMMENT ON COLUMN workflow_step_dependencies.depends_on_step IS
    'The step that must complete before step_slug can start'
    """

    # Update the complete_task function to use this table
    # execute ~S"""
    # CREATE OR REPLACE FUNCTION complete_task(
    #   p_run_id UUID,
    #   p_step_slug TEXT,
    #   p_task_index INTEGER,
    #   p_output JSONB DEFAULT NULL
    # )
    # RETURNS JSONB
    # LANGUAGE plpgsql
    # AS $$
    # DECLARE
    #   v_run_status TEXT;
    #   v_step_status TEXT;
    #   v_remaining_tasks INTEGER;
    #   v_step_completed BOOLEAN := FALSE;
    #   v_result JSONB;
    # BEGIN
    #   -- Lock the run to prevent concurrent modifications
    #   SELECT status INTO v_run_status
    #   FROM workflow_runs
    #   WHERE id = p_run_id
    #   FOR UPDATE;
    #
    #   -- Check if run is in failed state
    #   IF v_run_status = 'failed' THEN
    #         RAISE EXCEPTION 'Cannot complete task for failed run: %', p_run_id;
    #   END IF;
    #
    #   -- Mark the task as completed
    #   UPDATE workflow_step_tasks
    #   SET
    #     status = 'completed',
    #     output = p_output,
    #     completed_at = NOW()
    #   WHERE
    #     run_id = p_run_id
    #     AND step_slug = p_step_slug
    #     AND task_index = p_task_index
    #     AND status = 'started';
    #
    #   IF NOT FOUND THEN
    #         RAISE EXCEPTION 'Task not found or not in started state: run_id=%, step_slug=%, task_index=%',
    #       p_run_id, p_step_slug, p_task_index;
    #   END IF;
    #
    #   -- Lock the step state and decrement remaining_tasks
    #   UPDATE workflow_step_states
    #   SET remaining_tasks = remaining_tasks - 1
    #   WHERE run_id = p_run_id AND step_slug = p_step_slug
    #   RETURNING status, remaining_tasks INTO v_step_status, v_remaining_tasks;
    #
    #   -- Check if this was the last task in the step
    #   IF v_remaining_tasks = 0 THEN
    #     -- Mark step as completed
    #     UPDATE workflow_step_states
    #     SET
    #       status = 'completed',
    #       completed_at = NOW()
    #     WHERE
    #       run_id = p_run_id
    #       AND step_slug = p_step_slug;
    #
    #     v_step_completed := TRUE;
    #
    #     -- Decrement remaining_deps for all dependent steps (using explicit dependency table)
    #     UPDATE workflow_step_states wss
    #     SET remaining_deps = wss.remaining_deps - 1
    #     WHERE
    #       wss.run_id = p_run_id
    #       AND wss.step_slug IN (
    #         SELECT wsd.step_slug
    #         FROM workflow_step_dependencies wsd
    #         WHERE wsd.run_id = p_run_id
    #           AND wsd.depends_on_step = p_step_slug
    #       );
    #
    #     -- Decrement remaining_steps counter on the run
    #     UPDATE workflow_runs
    #     SET remaining_steps = remaining_steps - 1
    #     WHERE id = p_run_id;
    #
    #     -- Check if run is complete (all steps done)
    #     IF NOT EXISTS (
    #       SELECT 1 FROM workflow_step_states
    #       WHERE run_id = p_run_id AND status != 'completed'
    #     ) THEN
    #       UPDATE workflow_runs
    #       SET
    #         status = 'completed',
    #         completed_at = NOW()
    #       WHERE id = p_run_id;
    #     END IF;
    #
    #     -- Trigger start_ready_steps to awaken newly ready steps
    #     PERFORM start_ready_steps(p_run_id);
    #   END IF;
    #
    #   -- Build result
    #   v_result := jsonb_build_object(
    #     'run_id', p_run_id,
    #     'step_slug', p_step_slug,
    #     'task_index', p_task_index,
    #     'step_completed', v_step_completed,
    #     'remaining_tasks', v_remaining_tasks
    #   );
    #
    #   RETURN v_result;
    # END;
    # $$;
    # """
  end

  def down do
    # Restore original complete_task function without dependency table
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
      v_remaining_tasks INTEGER;
      v_step_completed BOOLEAN := FALSE;
      v_result JSONB;
    BEGIN
      SELECT status INTO v_run_status
      FROM workflow_runs WHERE id = p_run_id FOR UPDATE;

      IF v_run_status = 'failed' THEN
        RAISE EXCEPTION 'Cannot complete task for failed run: %', p_run_id;
      END IF;

      UPDATE workflow_step_tasks
      SET status = 'completed', output = p_output, completed_at = NOW()
      WHERE run_id = p_run_id AND step_slug = p_step_slug AND task_index = p_task_index;

      UPDATE workflow_step_states
      SET remaining_tasks = remaining_tasks - 1
      WHERE run_id = p_run_id AND step_slug = p_step_slug
      RETURNING remaining_tasks INTO v_remaining_tasks;

      IF v_remaining_tasks = 0 THEN
        UPDATE workflow_step_states
        SET status = 'completed', completed_at = NOW()
        WHERE run_id = p_run_id AND step_slug = p_step_slug;
        v_step_completed := TRUE;
      END IF;

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

    drop table(:workflow_step_dependencies)
  end
end
