defmodule Singularity.Workflow.FailTaskRetryClaimTest do
  @moduledoc """
  Falsifier: fail_task retry must clear claim lease fields so a requeued
  task is indistinguishable from a fresh queued row (no stale claimed_by).
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "fail_task below max_attempts clears claimed_at and claimed_by" do
    slug = "test_fail_claim_#{System.unique_integer([:positive])}"
    run_id = Ecto.UUID.generate()
    {:ok, run_bin} = Ecto.UUID.dump(run_id)
    worker = "worker-a"

    {:ok, _} = Repo.query("SELECT pgmq.create($1)", [slug])

    {:ok, _} =
      Repo.query(
        """
        INSERT INTO workflows (workflow_slug, max_attempts, timeout, created_at)
        VALUES ($1, 3, 60, now())
        ON CONFLICT DO NOTHING
        """,
        [slug]
      )

    {:ok, _} =
      Repo.query(
        """
        INSERT INTO workflow_steps (workflow_slug, step_slug, step_type, step_index, initial_tasks, max_attempts, timeout)
        VALUES ($1, 'step1', 'single', 0, 1, 3, 60)
        """,
        [slug]
      )

    {:ok, _} =
      Repo.query(
        """
        INSERT INTO workflow_runs (id, workflow_slug, status, input, remaining_steps, started_at, inserted_at, updated_at)
        VALUES ($1, $2, 'started', '{}'::jsonb, 1, now(), now(), now())
        """,
        [run_bin, slug]
      )

    {:ok, _} =
      Repo.query(
        """
        INSERT INTO workflow_step_states (run_id, step_slug, workflow_slug, status, remaining_deps, remaining_tasks, initial_tasks, inserted_at, updated_at)
        VALUES ($1, 'step1', $2, 'started', 0, 1, 1, now(), now())
        """,
        [run_bin, slug]
      )

    {:ok, %{rows: [[msg_id]]}} =
      Repo.query(
        """
        WITH sent AS (SELECT * FROM pgmq.send($1, '{"n":1}'::jsonb))
        INSERT INTO workflow_step_tasks (
          run_id, step_slug, workflow_slug, task_index, status, message_id,
          idempotency_key, attempts_count, max_attempts,
          claimed_by, claimed_at, started_at, inserted_at, updated_at
        )
        SELECT $2, 'step1', $1, 0, 'started', s.send, $1 || ':step1:0', 1, 3,
               $3, now(), now(), now(), now()
        FROM sent s
        RETURNING message_id
        """,
        [slug, run_bin, worker]
      )

    {:ok, _} =
      Repo.query("SELECT singularity_workflow.fail_task($1, 'step1', 0, 'boom')", [run_bin])

    {:ok, %{rows: [[status, claimed_by, has_claimed_at]]}} =
      Repo.query(
        """
        SELECT status, claimed_by, claimed_at IS NOT NULL
        FROM workflow_step_tasks
        WHERE workflow_slug = $1 AND message_id = $2
        """,
        [slug, msg_id]
      )

    assert status == "queued"
    assert claimed_by == nil
    assert has_claimed_at == false
  end
end
