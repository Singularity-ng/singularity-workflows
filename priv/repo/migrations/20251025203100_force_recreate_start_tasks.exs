defmodule QuantumFlow.Repo.Migrations.ForceRecreateStartTasks do
  @moduledoc """
  Force recreation of start_tasks function by dropping all versions first.

  This ensures we have the correct implementation regardless of what was previously in the database.
  """
  use Ecto.Migration

  def up do
    # Drop ALL possible versions of this function
    execute("DROP FUNCTION IF EXISTS start_tasks(TEXT, BIGINT[], TEXT) CASCADE")
    execute("DROP FUNCTION IF EXISTS start_tasks(TEXT, BIGINT[]) CASCADE")
    execute("DROP FUNCTION IF EXISTS start_tasks(TEXT) CASCADE")

    # Recreate with correct implementation matching 20251025160724
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
      -- NOTE: Set last_worker_id to NULL to avoid foreign key violations
      UPDATE workflow_step_tasks AS wst
      SET
        status = 'started',
        started_at = NOW(),
        attempts_count = attempts_count + 1,
        claimed_by = p_worker_id,
        last_worker_id = NULL
      WHERE
        wst.workflow_slug = p_workflow_slug
        AND wst.message_id = ANY(p_msg_ids)
        AND wst.status = 'queued';

      -- Return task records with built input
      -- Use unique CTE column names to avoid ambiguity with RETURNS TABLE columns
      RETURN QUERY
      WITH task_records AS (
        SELECT
          st.run_id AS t_run_id,
          st.step_slug AS t_step_slug,
          st.task_index AS t_task_index,
          st.message_id AS t_message_id
        FROM workflow_step_tasks AS st
        WHERE st.workflow_slug = p_workflow_slug
          AND st.message_id = ANY(p_msg_ids)
          AND st.status = 'started'
      ),
      run_records AS (
        SELECT
          wr.id AS r_run_id,
          wr.input AS r_input
        FROM workflow_runs wr
        WHERE wr.id IN (SELECT t_run_id FROM task_records)
      ),
      dependency_outputs AS (
        SELECT
          tr.t_run_id AS d_run_id,
          tr.t_step_slug AS d_step_slug,
          wst_dep.step_slug AS d_dep_step_slug,
          wst_dep.output AS d_output
        FROM task_records tr
        JOIN workflow_step_dependencies wsd
          ON wsd.run_id = tr.t_run_id
          AND wsd.step_slug = tr.t_step_slug
        LEFT JOIN workflow_step_tasks wst_dep
          ON wst_dep.run_id = tr.t_run_id
          AND wst_dep.step_slug = wsd.depends_on_step
          AND wst_dep.status = 'completed'
      ),
      aggregated_deps AS (
        SELECT
          dep_out.d_run_id AS a_run_id,
          dep_out.d_step_slug AS a_step_slug,
          jsonb_object_agg(dep_out.d_dep_step_slug, dep_out.d_output) AS a_deps_output
        FROM dependency_outputs dep_out
        WHERE dep_out.d_output IS NOT NULL
        GROUP BY dep_out.d_run_id, dep_out.d_step_slug
      )
      SELECT
        tr.t_run_id AS run_id,
        tr.t_step_slug::TEXT AS step_slug,  -- Cast VARCHAR to TEXT to match RETURNS TABLE
        tr.t_task_index AS task_index,
        COALESCE(wr.r_input, '{}'::jsonb) || COALESCE(agg_deps.a_deps_output, '{}'::jsonb) AS input,
        tr.t_message_id AS message_id
      FROM task_records tr
      JOIN run_records wr ON wr.r_run_id = tr.t_run_id
      LEFT JOIN aggregated_deps agg_deps
        ON agg_deps.a_run_id = tr.t_run_id
        AND agg_deps.a_step_slug = tr.t_step_slug;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION start_tasks(TEXT, BIGINT[], TEXT) IS
    'Claims tasks from pgmq messages, sets worker tracking, builds input. Forcefully recreated to ensure correct implementation.'
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS start_tasks(TEXT, BIGINT[], TEXT)")
  end
end
