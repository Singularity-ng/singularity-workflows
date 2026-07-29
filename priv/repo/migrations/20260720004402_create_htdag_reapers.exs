defmodule Singularity.Workflow.Repo.Migrations.CreateHtdagReapers do
  @moduledoc """
  HTDAG stuck + orphan reapers (ACE dual-reaper doctrine, adapted).

  - rearm_stuck_started_tasks: started + expired claimed_at grace → requeue
    WITHOUT clearing message_id (keeps VT redelivery; no duplicate send).
  - enqueue_orphaned_step_tasks: queued + NULL message_id → pgmq.send + bind id.

  Never DELETE live pgmq rows; inverse orphans use archive elsewhere.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION singularity_workflow.rearm_stuck_started_tasks(
      grace_seconds INTEGER DEFAULT 600
    )
    RETURNS INTEGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      r RECORD;
      v_count INTEGER := 0;
    BEGIN
      FOR r IN
        UPDATE workflow_step_tasks
        SET
          status = 'queued',
          started_at = NULL,
          claimed_by = NULL,
          claimed_at = NULL,
          updated_at = NOW()
        WHERE status = 'started'
          AND (
            (claimed_at IS NOT NULL AND claimed_at < NOW() - make_interval(secs => grace_seconds))
            OR (claimed_at IS NULL AND started_at IS NOT NULL
                AND started_at < NOW() - make_interval(secs => grace_seconds))
          )
        RETURNING workflow_slug, message_id
      LOOP
        v_count := v_count + 1;
        IF r.message_id IS NOT NULL THEN
          BEGIN
            PERFORM pgmq.set_vt(r.workflow_slug, r.message_id, 0);
          EXCEPTION
            WHEN OTHERS THEN
              RAISE WARNING 'rearm_stuck set_vt failed slug=% msg=%: %',
                r.workflow_slug, r.message_id, SQLERRM;
          END;
        END IF;
      END LOOP;

      RETURN v_count;
    END;
    $$;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION singularity_workflow.enqueue_orphaned_step_tasks()
    RETURNS INTEGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      r RECORD;
      v_msg_id BIGINT;
      v_count INTEGER := 0;
    BEGIN
      FOR r IN
        SELECT run_id, step_slug, task_index, workflow_slug, idempotency_key
        FROM workflow_step_tasks
        WHERE status = 'queued'
          AND message_id IS NULL
          AND inserted_at < NOW() - INTERVAL '10 seconds'
        ORDER BY inserted_at
        LIMIT 100
      LOOP
        BEGIN
          PERFORM singularity_workflow.ensure_workflow_queue(r.workflow_slug);
          SELECT pgmq.send(
            r.workflow_slug,
            jsonb_build_object(
              'run_id', r.run_id,
              'step_slug', r.step_slug,
              'task_index', r.task_index,
              'idempotency_key', r.idempotency_key
            )
          ) INTO v_msg_id;
          UPDATE workflow_step_tasks
          SET message_id = v_msg_id, updated_at = NOW()
          WHERE run_id = r.run_id
            AND step_slug = r.step_slug
            AND task_index = r.task_index
            AND status = 'queued'
            AND message_id IS NULL;
          IF FOUND THEN
            v_count := v_count + 1;
          END IF;
        EXCEPTION
          WHEN OTHERS THEN
            RAISE WARNING 'enqueue_orphaned_step_tasks failed for %/%/%: %',
              r.run_id, r.step_slug, r.task_index, SQLERRM;
        END;
      END LOOP;

      RETURN v_count;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION singularity_workflow.rearm_stuck_started_tasks(INTEGER) IS
    'Requeue started tasks past claimed_at grace without clearing message_id; VT set to 0 for reclaim.';
    """)

    execute("""
    COMMENT ON FUNCTION singularity_workflow.enqueue_orphaned_step_tasks() IS
    'Enqueue queued tasks with NULL message_id (age>=10s, limit 100).';
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS workflow_step_tasks_stuck_started_idx
      ON workflow_step_tasks (claimed_at)
      WHERE status = 'started';
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS workflow_step_tasks_orphan_queued_idx
      ON workflow_step_tasks (inserted_at)
      WHERE status = 'queued' AND message_id IS NULL;
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS workflow_step_tasks_orphan_queued_idx")
    execute("DROP INDEX IF EXISTS workflow_step_tasks_stuck_started_idx")
    execute("DROP FUNCTION IF EXISTS singularity_workflow.enqueue_orphaned_step_tasks()")
    execute("DROP FUNCTION IF EXISTS singularity_workflow.rearm_stuck_started_tasks(INTEGER)")
  end
end
