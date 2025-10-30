DROP FUNCTION IF EXISTS quantum_flow.cascade_complete_taskless_steps(UUID);

CREATE OR REPLACE FUNCTION quantum_flow.cascade_complete_taskless_steps(p_run_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_completed_count INTEGER := 0;
  v_step_record RECORD;
BEGIN
  -- Find steps that:
  -- 1. Have no tasks (remaining_tasks = 0 AND initial_tasks IS NULL OR 0)
  -- 2. Are not already completed
  -- 3. Have all dependencies satisfied (remaining_deps = 0)
  FOR v_step_record IN
    SELECT ss.run_id, ss.step_slug, ss.workflow_slug
    FROM workflow_step_states ss
    WHERE ss.run_id = p_run_id
      AND ss.status != 'completed'
      AND (ss.remaining_tasks = 0 OR ss.remaining_tasks IS NULL)
      AND (ss.initial_tasks = 0 OR ss.initial_tasks IS NULL)
      AND ss.remaining_deps = 0
  LOOP
    -- Mark the step as completed
    UPDATE workflow_step_states
    SET status = 'completed',
        completed_at = now(),
        updated_at = now()
    WHERE run_id = v_step_record.run_id AND step_slug = v_step_record.step_slug;

    -- Decrement the run's remaining_steps counter
    UPDATE workflow_runs
    SET remaining_steps = remaining_steps - 1
    WHERE id = p_run_id;

    -- Log the completion
    RAISE NOTICE 'Cascaded completion of taskless step: % in run %', v_step_record.step_slug, p_run_id;

    v_completed_count := v_completed_count + 1;

    -- After completing this step, trigger start_ready_steps to awaken dependent steps
    PERFORM start_ready_steps(p_run_id);

    -- Check if the run is now complete
    PERFORM quantum_flow.maybe_complete_run(p_run_id);
  END LOOP;

  RETURN v_completed_count;
END;
$$;
