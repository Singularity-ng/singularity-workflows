defmodule Singularity.Workflow.Repo.Migrations.CancelRunIdempotentOnFailed do
  @moduledoc """
  Make cancel_run idempotent when the run is already failed.

  Purpose: concurrent dual cancel (FOR UPDATE serializes) must not raise on the
  loser — SpaceX-grade cancel is safe to retry. completed stays guarded;
  failed returns 0 after draining any leftover message_ids.

  Consumer: Executor.cancel_workflow_run/3 and Engine C19 spine cancel_run.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION singularity_workflow.cancel_run(
      p_run_id UUID,
      p_reason TEXT DEFAULT 'cancelled',
      p_force BOOLEAN DEFAULT false
    )
    RETURNS INTEGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_workflow_slug TEXT;
      v_status TEXT;
      v_msg_ids BIGINT[];
      v_archived INTEGER := 0;
    BEGIN
      SELECT status, workflow_slug
      INTO v_status, v_workflow_slug
      FROM workflow_runs
      WHERE id = p_run_id
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'cancel_run: run not found: %', p_run_id
          USING ERRCODE = 'P0002';
      END IF;

      -- completed is terminal success — refuse unless forced.
      IF NOT p_force AND v_status = 'completed' THEN
        RAISE EXCEPTION 'cancel_run: run already finished (%)', v_status
          USING ERRCODE = 'P0001';
      END IF;

      -- failed is idempotent cancel: drain leftovers, return archived count.
      -- Concurrent dual cancel serializes on FOR UPDATE; the loser hits this path.
      IF NOT p_force AND v_status = 'failed' THEN
        SELECT COALESCE(array_agg(message_id), ARRAY[]::BIGINT[])
        INTO v_msg_ids
        FROM workflow_step_tasks
        WHERE run_id = p_run_id
          AND message_id IS NOT NULL;

        IF array_length(v_msg_ids, 1) IS NOT NULL THEN
          PERFORM pgmq.archive(v_workflow_slug, v_msg_ids);
          v_archived := array_length(v_msg_ids, 1);

          UPDATE workflow_step_tasks
          SET
            message_id = NULL,
            claimed_by = NULL,
            claimed_at = NULL,
            updated_at = NOW()
          WHERE run_id = p_run_id
            AND message_id IS NOT NULL;
        END IF;

        RETURN v_archived;
      END IF;

      SELECT COALESCE(array_agg(message_id), ARRAY[]::BIGINT[])
      INTO v_msg_ids
      FROM workflow_step_tasks
      WHERE run_id = p_run_id
        AND status IN ('queued', 'started')
        AND message_id IS NOT NULL;

      UPDATE workflow_step_tasks
      SET
        status = 'cancelled',
        updated_at = NOW(),
        message_id = NULL,
        claimed_by = NULL,
        claimed_at = NULL
      WHERE run_id = p_run_id
        AND status IN ('queued', 'started');

      UPDATE workflow_runs
      SET
        status = 'failed',
        error_message = p_reason,
        failed_at = NOW(),
        updated_at = NOW()
      WHERE id = p_run_id;

      IF array_length(v_msg_ids, 1) IS NOT NULL THEN
        PERFORM pgmq.archive(v_workflow_slug, v_msg_ids);
        v_archived := array_length(v_msg_ids, 1);
      END IF;

      RETURN v_archived;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION singularity_workflow.cancel_run(UUID, TEXT, BOOLEAN) IS
    'Cancel a run: mark queued/started tasks cancelled, mark run failed, archive pgmq messages. Idempotent on already-failed (returns leftover archive count). completed stays guarded unless p_force.';
    """)
  end

  def down do
    # Restore prior non-idempotent body from 20260720004400.
    execute("""
    CREATE OR REPLACE FUNCTION singularity_workflow.cancel_run(
      p_run_id UUID,
      p_reason TEXT DEFAULT 'cancelled',
      p_force BOOLEAN DEFAULT false
    )
    RETURNS INTEGER
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_workflow_slug TEXT;
      v_status TEXT;
      v_msg_ids BIGINT[];
      v_archived INTEGER := 0;
    BEGIN
      SELECT status, workflow_slug
      INTO v_status, v_workflow_slug
      FROM workflow_runs
      WHERE id = p_run_id
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'cancel_run: run not found: %', p_run_id
          USING ERRCODE = 'P0002';
      END IF;

      IF NOT p_force AND v_status IN ('completed', 'failed') THEN
        RAISE EXCEPTION 'cancel_run: run already finished (%)', v_status
          USING ERRCODE = 'P0001';
      END IF;

      SELECT COALESCE(array_agg(message_id), ARRAY[]::BIGINT[])
      INTO v_msg_ids
      FROM workflow_step_tasks
      WHERE run_id = p_run_id
        AND status IN ('queued', 'started')
        AND message_id IS NOT NULL;

      UPDATE workflow_step_tasks
      SET
        status = 'cancelled',
        updated_at = NOW(),
        message_id = NULL,
        claimed_by = NULL,
        claimed_at = NULL
      WHERE run_id = p_run_id
        AND status IN ('queued', 'started');

      UPDATE workflow_runs
      SET
        status = 'failed',
        error_message = p_reason,
        failed_at = NOW(),
        updated_at = NOW()
      WHERE id = p_run_id;

      IF array_length(v_msg_ids, 1) IS NOT NULL THEN
        PERFORM pgmq.archive(v_workflow_slug, v_msg_ids);
        v_archived := array_length(v_msg_ids, 1);
      END IF;

      RETURN v_archived;
    END;
    $$;
    """)
  end
end
