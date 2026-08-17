defmodule Singularity.Workflow.Repo.Migrations.FenceStartTasksAndLease do
  @moduledoc """
  Fences start_tasks RETURN to this-claim rows, writes claimed_at, renews VT.

  Purpose: close the past-vt double-execution window where RETURN selected all
  status='started' rows for msg_ids (including prior workers). Sets claimed_at
  for stuck reapers. Calls set_vt_batch so leases outlive default poll vt=30.

  Consumer: Elixir TaskExecutor + Engine HtdagPgmqClient (public.start_tasks).
  Does not change map fan-out or complete_task / fail_task.
  """
  use Ecto.Migration

  def up do
    execute("DROP FUNCTION IF EXISTS start_tasks(TEXT, BIGINT[], TEXT) CASCADE")
    execute("DROP FUNCTION IF EXISTS public.start_tasks(TEXT, BIGINT[], TEXT) CASCADE")

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
      v_claimed_msg_ids BIGINT[] := ARRAY[]::BIGINT[];
      v_vt_offsets INTEGER[] := ARRAY[]::INTEGER[];
      r RECORD;
    BEGIN
      BEGIN
        v_worker_uuid := p_worker_id::uuid;
      EXCEPTION
        WHEN invalid_text_representation THEN
          v_worker_uuid := gen_random_uuid();
      END;

      -- Claim only queued rows; collect this-claim ids for VT renew.
      FOR r IN
        UPDATE workflow_step_tasks AS wst
        SET
          status = 'started',
          started_at = NOW(),
          claimed_at = NOW(),
          attempts_count = attempts_count + 1,
          claimed_by = p_worker_id,
          last_worker_id = NULL
        WHERE
          wst.workflow_slug = p_workflow_slug
          AND wst.message_id = ANY(p_msg_ids)
          AND wst.status = 'queued'
        RETURNING
          wst.run_id,
          wst.step_slug,
          wst.task_index,
          wst.message_id
      LOOP
        v_claimed_msg_ids := array_append(v_claimed_msg_ids, r.message_id);
        v_vt_offsets := array_append(
          v_vt_offsets,
          GREATEST(
            COALESCE(
              (SELECT ws.timeout FROM workflow_steps ws
               WHERE ws.workflow_slug = p_workflow_slug
                 AND ws.step_slug = r.step_slug),
              1200
            ),
            120
          )
        );
      END LOOP;

      IF array_length(v_claimed_msg_ids, 1) IS NOT NULL THEN
        PERFORM * FROM singularity_workflow.set_vt_batch(
          p_workflow_slug,
          v_claimed_msg_ids,
          v_vt_offsets
        );
      END IF;

      -- Return ONLY this-claim rows (fence): claimed_by = worker, msg in claimed set.
      RETURN QUERY
      WITH claimed AS (
        SELECT
          st.run_id AS t_run_id,
          st.step_slug AS t_step_slug,
          st.task_index AS t_task_index,
          st.message_id AS t_message_id
        FROM workflow_step_tasks AS st
        WHERE st.workflow_slug = p_workflow_slug
          AND st.message_id = ANY(v_claimed_msg_ids)
          AND st.status = 'started'
          AND st.claimed_by = p_worker_id
      ),
      run_records AS (
        SELECT
          wr.id AS r_run_id,
          wr.input AS r_input
        FROM workflow_runs wr
        WHERE wr.id IN (SELECT t_run_id FROM claimed)
      ),
      dependency_outputs AS (
        SELECT
          c.t_run_id AS d_run_id,
          c.t_step_slug AS d_step_slug,
          wst_dep.step_slug AS d_dep_step_slug,
          wst_dep.output AS d_output
        FROM claimed c
        JOIN workflow_step_dependencies wsd
          ON wsd.run_id = c.t_run_id
          AND wsd.step_slug = c.t_step_slug
        LEFT JOIN workflow_step_tasks wst_dep
          ON wst_dep.run_id = c.t_run_id
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
        c.t_run_id AS run_id,
        c.t_step_slug::TEXT AS step_slug,
        c.t_task_index AS task_index,
        COALESCE(wr.r_input, '{}'::jsonb) || COALESCE(agg_deps.a_deps_output, '{}'::jsonb) AS input,
        c.t_message_id AS message_id
      FROM claimed c
      JOIN run_records wr ON wr.r_run_id = c.t_run_id
      LEFT JOIN aggregated_deps agg_deps
        ON agg_deps.a_run_id = c.t_run_id
        AND agg_deps.a_step_slug = c.t_step_slug;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION start_tasks(TEXT, BIGINT[], TEXT) IS
    'Claims queued tasks only. Sets claimed_at and renews pgmq VT via set_vt_batch. Returns only this-claim rows (no prior started re-return).';
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS start_tasks(TEXT, BIGINT[], TEXT)")
  end
end
