defmodule Singularity.Workflow.StartTasksClaimTest do
  @moduledoc """
  Falsifier: fenced start_tasks must claim queued rows (set_vt_batch must not abort).
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "start_tasks claims queued message after set_vt_batch shape fix" do
    slug = "test_start_tasks_claim_#{System.unique_integer([:positive])}"
    run_id = Ecto.UUID.generate()
    {:ok, run_bin} = Ecto.UUID.dump(run_id)
    worker = Ecto.UUID.generate()

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
        VALUES ($1, 'fetch', 'single', 0, 1, 3, 60)
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
        VALUES ($1, 'fetch', $2, 'started', 0, 1, 1, now(), now())
        """,
        [run_bin, slug]
      )

    {:ok, %{rows: [[msg_id]]}} =
      Repo.query(
        """
        WITH sent AS (SELECT * FROM pgmq.send($1, '{"n":1}'::jsonb))
        INSERT INTO workflow_step_tasks (
          run_id, step_slug, workflow_slug, task_index, status, message_id,
          idempotency_key, attempts_count, max_attempts, inserted_at, updated_at
        )
        SELECT $2, 'fetch', $1, 0, 'queued', s.send, $1 || ':fetch:0', 0, 3, now(), now()
        FROM sent s
        RETURNING message_id
        """,
        [slug, run_bin]
      )

    {:ok, %{rows: claimed}} =
      Repo.query(
        """
        SELECT run_id::text, step_slug, task_index, message_id
        FROM start_tasks($1, ARRAY[$2]::bigint[], $3)
        """,
        [slug, msg_id, worker]
      )

    assert length(claimed) == 1
    [[claimed_run, "fetch", 0, ^msg_id]] = claimed
    assert claimed_run == run_id

    {:ok, %{rows: [[status, claimed_by]]}} =
      Repo.query(
        """
        SELECT status, claimed_by FROM workflow_step_tasks
        WHERE workflow_slug = $1 AND message_id = $2
        """,
        [slug, msg_id]
      )

    assert status == "started"
    assert claimed_by == worker
  end
end
