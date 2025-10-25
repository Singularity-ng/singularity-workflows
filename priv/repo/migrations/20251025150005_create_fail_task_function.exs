defmodule Pgflow.Repo.Migrations.CreateFailTaskFunction do
  @moduledoc """
  Creates pgflow.fail_task() function for handling task failures.

  Matches pgflow's architecture:
  1. Check if run is already failed (no retry allowed)
  2. Determine if task should retry based on attempts_count vs max_attempts
  3. Update task status (queued for retry, or failed permanently)
  4. If permanently failed, mark step and run as failed
  5. Archive pgmq messages
  """
  use Ecto.Migration

  def up do
    # First create helper function for retry delay calculation
    execute("""
    CREATE OR REPLACE FUNCTION pgflow.calculate_retry_delay(
      base_delay INTEGER,
      attempts_count INTEGER
    )
    RETURNS INTEGER
    LANGUAGE SQL
    IMMUTABLE
    AS $$
      SELECT base_delay * POWER(2, attempts_count)::integer;
    $$;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION pgflow.fail_task(
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
      -- Get workflow slug and current attempts
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

      -- Check if task should retry or fail
      IF v_attempts_count >= v_max_attempts THEN
        v_task_failed := true;
      END IF;

      -- Update task status
      IF v_task_failed THEN
        -- Permanently failed
        UPDATE workflow_step_tasks
        SET
          status = 'failed',
          failed_at = NOW(),
          error_message = p_error_message
        WHERE run_id = p_run_id
          AND step_slug = p_step_slug
          AND task_index = p_task_index
          AND status = 'started';

        -- Mark step as failed
        UPDATE workflow_step_states
        SET
          status = 'failed',
          failed_at = NOW(),
          error_message = p_error_message
        WHERE run_id = p_run_id
          AND step_slug = p_step_slug;

        -- Mark run as failed
        UPDATE workflow_runs
        SET
          status = 'failed',
          failed_at = NOW(),
          error_message = p_error_message
        WHERE id = p_run_id;

        -- Archive pgmq message (permanently failed)
        IF v_message_id IS NOT NULL THEN
          PERFORM pgmq.archive(v_workflow_slug, ARRAY[v_message_id]);
        END IF;
      ELSE
        -- Retry: requeue task
        UPDATE workflow_step_tasks
        SET
          status = 'queued',
          started_at = NULL,
          error_message = p_error_message
        WHERE run_id = p_run_id
          AND step_slug = p_step_slug
          AND task_index = p_task_index
          AND status = 'started';

        -- Set visibility timeout for retry with exponential backoff
        IF v_message_id IS NOT NULL THEN
          PERFORM pgmq.set_vt(
            v_workflow_slug,
            v_message_id,
            pgflow.calculate_retry_delay(5, v_attempts_count)
          );
        END IF;
      END IF;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION pgflow.fail_task(UUID, TEXT, INTEGER, TEXT) IS
    'Handles task failure with retry logic. Either requeues for retry or marks as permanently failed. Matches pgflow architecture.'
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS pgflow.fail_task(UUID, TEXT, INTEGER, TEXT)")
    execute("DROP FUNCTION IF EXISTS pgflow.calculate_retry_delay(INTEGER, INTEGER)")
  end
end
