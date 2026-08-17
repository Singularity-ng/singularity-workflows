defmodule Singularity.Workflow.Repo.Migrations.FailTaskRetryClearsClaimLease do
  @moduledoc """
  Clear claimed_at / claimed_by on fail_task retry requeue.

  Purpose: a requeued task must look like a fresh queued row so claim fence,
  reapers, and operators do not see a stale lease owner.

  Consumer: singularity_workflow.fail_task → TaskExecutor / C21.
  Permanent-fail archive path unchanged.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION singularity_workflow.fail_task(
      p_run_id UUID,
      p_step_slug TEXT,
      p_task_index INTEGER,
      p_error_message TEXT
    )
    RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_workflow_slug TEXT;
      v_max_attempts INTEGER;
      v_attempts_count INTEGER;
      v_message_id BIGINT;
      v_task_failed BOOLEAN := false;
    BEGIN
      SELECT
        t.workflow_slug,
        t.max_attempts,
        t.attempts_count,
        t.message_id
      INTO
        v_workflow_slug,
        v_max_attempts,
        v_attempts_count,
        v_message_id
      FROM workflow_step_tasks t
      WHERE t.run_id = p_run_id
        AND t.step_slug = p_step_slug
        AND t.task_index = p_task_index
        AND t.status = 'started';

      IF NOT FOUND THEN
        RETURN;
      END IF;

      IF v_attempts_count >= v_max_attempts THEN
        v_task_failed := true;
      END IF;

      IF v_task_failed THEN
        UPDATE workflow_step_tasks
        SET
          status = 'failed',
          failed_at = NOW(),
          error_message = p_error_message,
          claimed_by = NULL,
          claimed_at = NULL
        WHERE run_id = p_run_id
          AND step_slug = p_step_slug
          AND task_index = p_task_index
          AND status = 'started';

        UPDATE workflow_step_states
        SET
          status = 'failed',
          failed_at = NOW(),
          error_message = p_error_message
        WHERE run_id = p_run_id
          AND step_slug = p_step_slug;

        UPDATE workflow_runs
        SET
          status = 'failed',
          failed_at = NOW(),
          error_message = p_error_message
        WHERE id = p_run_id;

        IF v_message_id IS NOT NULL THEN
          PERFORM pgmq.archive(v_workflow_slug, ARRAY[v_message_id]);
        END IF;
      ELSE
        UPDATE workflow_step_tasks
        SET
          status = 'queued',
          started_at = NULL,
          claimed_by = NULL,
          claimed_at = NULL,
          error_message = p_error_message
        WHERE run_id = p_run_id
          AND step_slug = p_step_slug
          AND task_index = p_task_index
          AND status = 'started';

        IF v_message_id IS NOT NULL THEN
          PERFORM pgmq.set_vt(
            v_workflow_slug,
            v_message_id,
            singularity_workflow.calculate_retry_delay(5, v_attempts_count)
          );
        END IF;
      END IF;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION singularity_workflow.fail_task(UUID, TEXT, INTEGER, TEXT) IS
    'Fail or requeue a started task. Retry clears claimed_at/claimed_by and sets VT backoff. Permanent fail archives pgmq message.';
    """)
  end

  def down do
    # Prior body left claim fields on retry; restore via earlier migration if needed.
    :ok
  end
end
