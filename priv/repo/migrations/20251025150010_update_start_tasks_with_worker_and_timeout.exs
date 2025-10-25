defmodule Pgflow.Repo.Migrations.UpdateStartTasksWithWorkerAndTimeout do
  @moduledoc """
  Updates start_tasks() to:
  1. Set last_worker_id when claiming tasks
  2. Use set_vt_batch() to set visibility timeouts for all messages
  3. Calculate timeout based on step/workflow configuration

  Matches pgflow's complete start_tasks implementation.
  """
  use Ecto.Migration

  def up do
    # Drop old version
    execute("DROP FUNCTION IF EXISTS start_tasks(TEXT, BIGINT[], TEXT)")

    # Create updated version with worker tracking and timeout management
    execute("""
    CREATE OR REPLACE FUNCTION start_tasks(
      p_workflow_slug TEXT,
      p_msg_ids BIGINT[],
      p_worker_id TEXT
    )
    RETURNS TABLE (
      run_id UUID,
      step_slug TEXT,
      task_index INTEGER,
      input JSONB,
      message_id BIGINT
    )
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_worker_uuid UUID;
    BEGIN
      -- Convert worker_id string to UUID (or generate new one)
      BEGIN
        v_worker_uuid := p_worker_id::uuid;
      EXCEPTION
        WHEN invalid_text_representation THEN
          v_worker_uuid := gen_random_uuid();
      END;

      -- Update tasks to 'started' status with worker tracking
      UPDATE workflow_step_tasks
      SET
        status = 'started',
        started_at = NOW(),
        attempts_count = attempts_count + 1,
        claimed_by = p_worker_id,
        last_worker_id = v_worker_uuid
      WHERE
        workflow_slug = p_workflow_slug
        AND message_id = ANY(p_msg_ids)
        AND status = 'queued';

      -- Set visibility timeouts using set_vt_batch with dynamic timeout from DB
      -- Calculate timeout per task: COALESCE(step.timeout, workflow.timeout) + 2
      -- Matches pgflow's dynamic timeout logic (line 85-86 of schemas/0120_function_start_tasks.sql)
      WITH timeouts AS (
        SELECT
          t.message_id,
          COALESCE(step.timeout, flow.timeout) + 2 AS vt_delay
        FROM workflow_step_tasks t
        JOIN workflows flow ON flow.workflow_slug = t.workflow_slug
        JOIN workflow_steps step ON step.workflow_slug = t.workflow_slug
                                  AND step.step_slug = t.step_slug
        WHERE t.workflow_slug = p_workflow_slug
          AND t.message_id = ANY(p_msg_ids)
          AND t.status = 'started'
      )
      SELECT pgflow.set_vt_batch(
        p_workflow_slug,
        array_agg(timeouts.message_id ORDER BY timeouts.message_id),
        array_agg(timeouts.vt_delay ORDER BY timeouts.message_id)
      )
      FROM timeouts
      WHERE EXISTS (SELECT 1 FROM timeouts);

      -- Return task records with built input
      RETURN QUERY
      WITH tasks AS (
        SELECT
          task.run_id,
          task.step_slug,
          task.task_index,
          task.message_id
        FROM workflow_step_tasks AS task
        WHERE task.workflow_slug = p_workflow_slug
          AND task.message_id = ANY(p_msg_ids)
          AND task.status = 'started'
      ),
      runs AS (
        SELECT
          r.id AS run_id,
          r.input AS run_input
        FROM workflow_runs r
        WHERE r.id IN (SELECT run_id FROM tasks)
      ),
      -- Get dependency outputs
      dependency_outputs AS (
        SELECT
          t.run_id,
          t.step_slug,
          dep_task.step_slug AS dep_step_slug,
          dep_task.output AS dep_output
        FROM tasks t
        JOIN workflow_step_dependencies dep
          ON dep.run_id = t.run_id
          AND dep.step_slug = t.step_slug
        LEFT JOIN workflow_step_tasks dep_task
          ON dep_task.run_id = t.run_id
          AND dep_task.step_slug = dep.depends_on_step
          AND dep_task.status = 'completed'
      ),
      -- Aggregate dependency outputs per task
      aggregated_deps AS (
        SELECT
          do.run_id,
          do.step_slug,
          jsonb_object_agg(do.dep_step_slug, do.dep_output) AS deps_output
        FROM dependency_outputs do
        WHERE do.dep_output IS NOT NULL
        GROUP BY do.run_id, do.step_slug
      )
      SELECT
        t.run_id,
        t.step_slug,
        t.task_index,
        -- Build input: merge run input + dependency outputs
        COALESCE(r.run_input, '{}'::jsonb) || COALESCE(ad.deps_output, '{}'::jsonb) AS input,
        t.message_id
      FROM tasks t
      JOIN runs r ON r.run_id = t.run_id
      LEFT JOIN aggregated_deps ad
        ON ad.run_id = t.run_id
        AND ad.step_slug = t.step_slug;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION start_tasks(TEXT, BIGINT[], TEXT) IS
    'Claims tasks from pgmq messages, sets worker tracking, configures timeouts via set_vt_batch, builds input. Matches pgflow implementation.'
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS start_tasks(TEXT, BIGINT[], TEXT)")

    # Restore simpler version
    execute("""
    CREATE OR REPLACE FUNCTION start_tasks(
      p_workflow_slug TEXT,
      p_msg_ids BIGINT[],
      p_worker_id TEXT
    )
    RETURNS TABLE (
      run_id UUID,
      step_slug TEXT,
      task_index INTEGER,
      input JSONB,
      message_id BIGINT
    )
    LANGUAGE plpgsql
    AS $$
    BEGIN
      UPDATE workflow_step_tasks
      SET
        status = 'started',
        started_at = NOW(),
        attempts_count = attempts_count + 1,
        claimed_by = p_worker_id
      WHERE
        workflow_slug = p_workflow_slug
        AND message_id = ANY(p_msg_ids)
        AND status = 'queued';

      RETURN QUERY
      SELECT
        t.run_id,
        t.step_slug,
        t.task_index,
        '{}'::jsonb AS input,
        t.message_id
      FROM workflow_step_tasks t
      WHERE t.workflow_slug = p_workflow_slug
        AND t.message_id = ANY(p_msg_ids)
        AND t.status = 'started';
    END;
    $$;
    """)
  end
end
