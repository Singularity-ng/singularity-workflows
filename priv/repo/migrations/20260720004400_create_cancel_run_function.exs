defmodule Singularity.Workflow.Repo.Migrations.CreateCancelRunFunction do
  @moduledoc """
  Creates singularity_workflow.cancel_run/3.

  Purpose: cancel a workflow run and archive every live pgmq message for its
  queued/started tasks in the same transaction — closing the cancel queue-spin
  leak (harvest C19 cancel gap; ACE TaskQueue.cancel_task contract).

  Consumer: Singularity.Workflow.Executor.cancel_workflow_run/3 and the Engine
  C19 spine attach path. Map fan-out / complete_task / fail_task are untouched.
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

      IF NOT p_force AND v_status IN ('completed', 'failed') THEN
        RAISE EXCEPTION 'cancel_run: run already finished (%)', v_status
          USING ERRCODE = 'P0001';
      END IF;

      -- Capture message ids before clearing them (ACE: drain queue with SoR).
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
    'Cancel a run: mark queued/started tasks cancelled, mark run failed, archive pgmq messages. Returns archived message count. p_force bypasses already-finished guard.';
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS singularity_workflow.cancel_run(UUID, TEXT, BOOLEAN)")
    execute("DROP FUNCTION IF EXISTS singularity_workflow.cancel_run(UUID, TEXT)")
  end
end
