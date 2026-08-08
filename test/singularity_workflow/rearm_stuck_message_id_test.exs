defmodule Singularity.Workflow.RearmStuckMessageIdTest do
  @moduledoc """
  Falsifier: rearm_stuck_started_tasks must requeue without clearing message_id
  (no duplicate pgmq.send).
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "rearm_stuck keeps message_id and sets status queued" do
    slug = "test_rearm_#{System.unique_integer([:positive])}"
    {:ok, run_bin} = Ecto.UUID.dump(Ecto.UUID.generate())

    {:ok, _} = Repo.query("SELECT pgmq.create($1)", [slug])

    {:ok, _} =
      Repo.query(
        """
        INSERT INTO workflows (workflow_slug, max_attempts, timeout, created_at)
        VALUES ($1, 3, 60, now()) ON CONFLICT DO NOTHING
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
        SELECT $2, 'step1', $1, 0, 'started', s.send, $3, 1, 3,
               'w1', now() - interval '20 minutes', now() - interval '20 minutes',
               now(), now()
        FROM sent s
        RETURNING message_id
        """,
        [slug, run_bin, slug <> ":step1:0"]
      )

    # grace default 600s; claimed_at is 20 minutes ago
    {:ok, _} = Repo.query("SELECT singularity_workflow.rearm_stuck_started_tasks(600)", [])

    {:ok, %{rows: [[status, mid, claimed_by]]}} =
      Repo.query(
        """
        SELECT status, message_id, claimed_by
        FROM workflow_step_tasks
        WHERE workflow_slug = $1 AND step_slug = 'step1' AND task_index = 0
        """,
        [slug]
      )

    assert status == "queued"
    assert mid == msg_id
    assert claimed_by == nil
  end
end
