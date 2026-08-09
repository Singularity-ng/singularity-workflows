defmodule Singularity.Workflow.Repo.Migrations.FlatMergeStartTasksDepOutputs do
  @moduledoc """
  Flat-merge object-typed dependency outputs into start_tasks input.

  Purpose: pipeline steps (validate after transform) must see prior keys at the
  top level after jsonb round-trip. Nested-by-step-slug remains so HTDAG/map
  consumers can still address a specific dep (e.g. fetch array under "fetch").

  Consumer: public.start_tasks → TaskExecutor / C21 HtdagPgmqClient.
  Does not change map fan-out, complete_task, or claim fencing.
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
          jsonb_object_agg(dep_out.d_dep_step_slug, dep_out.d_output)
            FILTER (WHERE dep_out.d_output IS NOT NULL) AS a_deps_nested,
          COALESCE(
            (
              SELECT jsonb_object_agg(kv.key, kv.value)
              FROM dependency_outputs flat
              CROSS JOIN LATERAL jsonb_each(flat.d_output) AS kv(key, value)
              WHERE flat.d_run_id = dep_out.d_run_id
                AND flat.d_step_slug = dep_out.d_step_slug
                AND flat.d_output IS NOT NULL
                AND jsonb_typeof(flat.d_output) = 'object'
            ),
            '{}'::jsonb
          ) AS a_deps_flat
        FROM dependency_outputs dep_out
        GROUP BY dep_out.d_run_id, dep_out.d_step_slug
      )
      SELECT
        c.t_run_id AS run_id,
        c.t_step_slug::TEXT AS step_slug,
        c.t_task_index AS task_index,
        COALESCE(wr.r_input, '{}'::jsonb)
          || COALESCE(agg_deps.a_deps_flat, '{}'::jsonb)
          || COALESCE(agg_deps.a_deps_nested, '{}'::jsonb) AS input,
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
    'Claims queued tasks only. Sets claimed_at and renews pgmq VT via set_vt_batch. Returns only this-claim rows. Input = run.input || flat object dep merge || nested-by-step deps.';
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS start_tasks(TEXT, BIGINT[], TEXT)")
  end
end
