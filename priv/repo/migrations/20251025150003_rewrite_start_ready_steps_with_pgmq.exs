defmodule QuantumFlow.Repo.Migrations.RewriteStartReadyStepsWithPgmq do
  @moduledoc """
  Rewrites start_ready_steps() to use pgmq for task coordination.

  Matches QuantumFlow's architecture:
  1. Find ready steps (remaining_deps = 0)
  2. Mark as started
  3. Create step_tasks records
  4. Send messages to pgmq queue

  This is the KEY function for QuantumFlow parity - uses pgmq for work distribution!
  """
  use Ecto.Migration

  def up do
    # Drop old version
    execute("DROP FUNCTION IF EXISTS start_ready_steps(UUID)")

    # Create new version with pgmq integration
    execute("""
    CREATE OR REPLACE FUNCTION start_ready_steps(p_run_id UUID)
    RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_workflow_slug TEXT;
    BEGIN
      -- Get workflow slug for queue name
      SELECT workflow_slug INTO v_workflow_slug
      FROM workflow_runs
      WHERE id = p_run_id;

      -- Ensure queue exists for this workflow
      PERFORM QuantumFlow.ensure_workflow_queue(v_workflow_slug);

      -- Mark ready steps as started and send tasks to pgmq
      WITH ready_steps AS (
        SELECT *
        FROM workflow_step_states
        WHERE run_id = p_run_id
          AND status = 'created'
          AND remaining_deps = 0
          AND initial_tasks IS NOT NULL
          AND initial_tasks > 0
        FOR UPDATE
      ),
      -- Mark steps as started
      started_steps AS (
        UPDATE workflow_step_states
        SET
          status = 'started',
          remaining_tasks = ready_steps.initial_tasks,
          started_at = NOW()
        FROM ready_steps
        WHERE workflow_step_states.run_id = ready_steps.run_id
          AND workflow_step_states.step_slug = ready_steps.step_slug
        RETURNING workflow_step_states.*
      ),
      -- Generate task records with message payloads
      task_messages AS (
        SELECT
          started_step.run_id,
          started_step.step_slug,
          started_step.workflow_slug,
          task_idx.task_index,
          jsonb_build_object(
            'workflow_slug', started_step.workflow_slug,
            'run_id', started_step.run_id,
            'step_slug', started_step.step_slug,
            'task_index', task_idx.task_index
          ) AS message
        FROM started_steps AS started_step
        CROSS JOIN LATERAL generate_series(0, started_step.initial_tasks - 1) AS task_idx(task_index)
      ),
      -- Batch messages by step for efficient pgmq.send_batch
      message_batches AS (
        SELECT
          workflow_slug,
          run_id,
          step_slug,
          array_agg(message ORDER BY task_index) AS messages,
          array_agg(task_index ORDER BY task_index) AS task_indices
        FROM task_messages
        GROUP BY workflow_slug, run_id, step_slug
      ),
      -- Send messages to pgmq and get msg_ids back
      sent_messages AS (
        SELECT
          mb.workflow_slug,
          mb.run_id,
          mb.step_slug,
          task_indices.task_index,
          msg_ids.msg_id
        FROM message_batches mb
        CROSS JOIN LATERAL unnest(mb.task_indices) WITH ORDINALITY AS task_indices(task_index, idx_ord)
        CROSS JOIN LATERAL pgmq.send_batch(mb.workflow_slug, mb.messages, 0) WITH ORDINALITY AS msg_ids(msg_id, msg_ord)
        WHERE task_indices.idx_ord = msg_ids.msg_ord
      )
      -- Create step_tasks records with message_ids
      INSERT INTO workflow_step_tasks (
        run_id,
        step_slug,
        task_index,
        workflow_slug,
        status,
        input,
        message_id,
        attempts_count,
        max_attempts,
        inserted_at,
        updated_at
      )
      SELECT
        sm.run_id,
        sm.step_slug,
        sm.task_index,
        sm.workflow_slug,
        'queued',
        '{}'::jsonb,
        sm.msg_id,
        0,
        3,  -- Default max_attempts
        NOW(),
        NOW()
      FROM sent_messages sm;

      -- Handle empty map steps (initial_tasks = 0)
      UPDATE workflow_step_states
      SET
        status = 'completed',
        started_at = NOW(),
        completed_at = NOW(),
        remaining_tasks = 0
      WHERE
        run_id = p_run_id
        AND status = 'created'
        AND remaining_deps = 0
        AND initial_tasks = 0;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION start_ready_steps(UUID) IS
    'Finds steps with all dependencies completed, marks as started, creates task records, and sends messages to pgmq queue. Matches QuantumFlow architecture.'
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS start_ready_steps(UUID)")

    # Restore old version (non-pgmq)
    execute("""
    CREATE OR REPLACE FUNCTION start_ready_steps(p_run_id UUID)
    RETURNS TABLE (
      step_slug TEXT,
      initial_tasks INTEGER
    )
    LANGUAGE plpgsql
    AS $$
    DECLARE
      v_step_count INTEGER := 0;
    BEGIN
      UPDATE workflow_step_states
      SET
        status = 'started',
        remaining_tasks = initial_tasks,
        started_at = NOW()
      WHERE
        run_id = p_run_id
        AND status = 'created'
        AND remaining_deps = 0
        AND initial_tasks IS NOT NULL
      RETURNING workflow_step_states.step_slug, workflow_step_states.initial_tasks
      INTO step_slug, initial_tasks;

      GET DIAGNOSTICS v_step_count = ROW_COUNT;

      IF v_step_count > 0 THEN
        UPDATE workflow_step_states
        SET
          status = 'completed',
          remaining_tasks = 0,
          completed_at = NOW()
        WHERE
          run_id = p_run_id
          AND status = 'started'
          AND initial_tasks = 0;
      END IF;

      RETURN QUERY
      SELECT
        wss.step_slug,
        wss.initial_tasks
      FROM workflow_step_states wss
      WHERE
        wss.run_id = p_run_id
        AND wss.status = 'started'
        AND wss.remaining_tasks > 0;
    END;
    $$;
    """)
  end
end
