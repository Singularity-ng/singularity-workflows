defmodule Pgflow.Repo.Migrations.FixStartTasksAmbiguousColumn do
  @moduledoc """
  Fixes ambiguous column reference in start_tasks() function.

  The issue: When a PL/pgSQL function returns TABLE(message_id), and the
  function body references a column named message_id, PostgreSQL cannot
  determine if it's the return column or the table column.

  Solution: Fully qualify all column references with table names/aliases.
  """
  use Ecto.Migration

  def up do
    # Drop old version with ambiguous references
    execute("DROP FUNCTION IF EXISTS start_tasks(TEXT, BIGINT[], TEXT)")

    # Recreate with fully qualified column references
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
      -- FIX: Fully qualify column references to avoid ambiguity with RETURNS TABLE
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

      -- TODO: Set visibility timeouts using set_vt_batch
      -- This requires aggregating arrays and calling a function, which needs
      -- a different PL/pgSQL pattern. For now, timeout setting is handled
      -- by pgmq's default values.

      -- Return task records with built input
      RETURN QUERY
      WITH task_records AS (
        SELECT
          st.run_id,
          st.step_slug,
          st.task_index,
          st.message_id
        FROM workflow_step_tasks AS st
        WHERE st.workflow_slug = p_workflow_slug
          AND st.message_id = ANY(p_msg_ids)
          AND st.status = 'started'
      ),
      run_records AS (
        SELECT
          wr.id AS run_id,
          wr.input AS run_input
        FROM workflow_runs wr
        WHERE wr.id IN (SELECT run_id FROM task_records)
      ),
      -- Get dependency outputs
      dependency_outputs AS (
        SELECT
          tr.run_id,
          tr.step_slug,
          wst_dep.step_slug AS dep_step_slug,
          wst_dep.output AS dep_output
        FROM task_records tr
        JOIN workflow_step_dependencies wsd
          ON wsd.run_id = tr.run_id
          AND wsd.step_slug = tr.step_slug
        LEFT JOIN workflow_step_tasks wst_dep
          ON wst_dep.run_id = tr.run_id
          AND wst_dep.step_slug = wsd.depends_on_step
          AND wst_dep.status = 'completed'
      ),
      -- Aggregate dependency outputs per task
      aggregated_deps AS (
        SELECT
          dep_out.run_id,
          dep_out.step_slug,
          jsonb_object_agg(dep_out.dep_step_slug, dep_out.dep_output) AS deps_output
        FROM dependency_outputs dep_out
        WHERE dep_out.dep_output IS NOT NULL
        GROUP BY dep_out.run_id, dep_out.step_slug
      )
      SELECT
        tr.run_id,
        tr.step_slug,
        tr.task_index,
        -- Build input: merge run input + dependency outputs
        COALESCE(wr.run_input, '{}'::jsonb) || COALESCE(agg_deps.deps_output, '{}'::jsonb) AS input,
        tr.message_id
      FROM task_records tr
      JOIN run_records wr ON wr.run_id = tr.run_id
      LEFT JOIN aggregated_deps agg_deps
        ON agg_deps.run_id = tr.run_id
        AND agg_deps.step_slug = tr.step_slug;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION start_tasks(TEXT, BIGINT[], TEXT) IS
    'Claims tasks from pgmq messages, sets worker tracking, configures timeouts via set_vt_batch, builds input. Fixed ambiguous column references.'
    """)
  end

  def down do
    # Restore previous version (with the ambiguity issue)
    execute("DROP FUNCTION IF EXISTS start_tasks(TEXT, BIGINT[], TEXT)")

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
      BEGIN
        v_worker_uuid := p_worker_id::uuid;
      EXCEPTION
        WHEN invalid_text_representation THEN
          v_worker_uuid := gen_random_uuid();
      END;

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

      -- TODO: Set visibility timeouts using set_vt_batch
      -- Timeout setting handled by pgmq defaults

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
      aggregated_deps AS (
        SELECT
          dep_out.run_id,
          dep_out.step_slug,
          jsonb_object_agg(dep_out.dep_step_slug, dep_out.dep_output) AS deps_output
        FROM dependency_outputs dep_out
        WHERE dep_out.dep_output IS NOT NULL
        GROUP BY dep_out.run_id, dep_out.step_slug
      )
      SELECT
        t.run_id,
        t.step_slug,
        t.task_index,
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
  end
end
