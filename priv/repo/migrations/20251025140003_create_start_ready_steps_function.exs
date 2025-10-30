defmodule QuantumFlow.Repo.Migrations.CreateStartReadyStepsFunction do
  @moduledoc """
  Creates start_ready_steps() PostgreSQL function for DAG coordination.

  This function finds steps with all dependencies completed (remaining_deps = 0)
  and marks them as 'started', making their tasks available for execution.

  Matches QuantumFlow's dependency awakening mechanism.
  """
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION start_ready_steps(p_run_id UUID)
    RETURNS TABLE (
      step_slug TEXT,
      initial_tasks INTEGER
    )
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_step_count INTEGER := 0;
    BEGIN
      -- Find all steps that are ready to start:
      -- 1. Status is 'created' (not yet started)
      -- 2. remaining_deps = 0 (all dependencies completed)
      -- 3. initial_tasks IS NOT NULL (task count is known)

      UPDATE workflow_step_states
      SET
        status = 'started',
        remaining_tasks = initial_tasks,
        started_at = NOW()
      WHERE
        run_id = p_run_id
        AND status = 'created'
        AND remaining_deps = 0
        AND initial_tasks IS NOT NULL
      RETURNING workflow_step_states.step_slug, workflow_step_states.initial_tasks
      INTO step_slug, initial_tasks;

      GET DIAGNOSTICS v_step_count = ROW_COUNT;

      -- Handle steps with initial_tasks = 0 (empty map steps)
      -- These complete immediately with no tasks to execute
      IF v_step_count > 0 THEN
        UPDATE workflow_step_states
        SET
          status = 'completed',
          remaining_tasks = 0,
          completed_at = NOW()
        WHERE
          run_id = p_run_id
          AND status = 'started'
          AND initial_tasks = 0;

        -- Cascade completion to dependent steps
        -- (This will be handled by complete_task function)
      END IF;

      RETURN QUERY
      SELECT
        wss.step_slug,
        wss.initial_tasks
      FROM workflow_step_states wss
      WHERE
        wss.run_id = p_run_id
        AND wss.status = 'started'
        AND wss.remaining_tasks > 0;
    END;
    $$;
    """

    execute """
    COMMENT ON FUNCTION start_ready_steps(UUID) IS
    'Finds steps with all dependencies completed (remaining_deps=0) and marks them as started. Returns steps ready for task execution.'
    """
  end

  def down do
    execute "DROP FUNCTION IF EXISTS start_ready_steps(UUID);"
  end
end
