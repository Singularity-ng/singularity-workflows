defmodule Singularity.Workflow.EnqueueOrphanedTest do
  @moduledoc """
  Falsifier: enqueue_orphaned_step_tasks binds exactly one pgmq message_id onto
  a queued row that had NULL message_id — no duplicate send on second call.
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "enqueue_orphaned binds one message_id; second call is a no-op" do
    slug = "test_orphan_#{System.unique_integer([:positive])}"
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

    {:ok, _} =
      Repo.query(
        """
        INSERT INTO workflow_step_tasks (
          run_id, step_slug, workflow_slug, task_index, status, message_id,
          idempotency_key, attempts_count, max_attempts, inserted_at, updated_at
        ) VALUES ($1, 'step1', $2, 0, 'queued', NULL, $3, 0, 3, now() - interval '15 seconds', now())
        """,
        [run_bin, slug, slug <> ":step1:0"]
      )

    {:ok, _} = Repo.query("SELECT singularity_workflow.enqueue_orphaned_step_tasks()", [])

    {:ok, %{rows: [[mid1]]}} =
      Repo.query(
        """
        SELECT message_id FROM workflow_step_tasks
        WHERE workflow_slug = $1 AND step_slug = 'step1' AND task_index = 0
        """,
        [slug]
      )

    assert is_integer(mid1)

    {:ok, _} = Repo.query("SELECT singularity_workflow.enqueue_orphaned_step_tasks()", [])

    {:ok, %{rows: [[mid2]]}} =
      Repo.query(
        """
        SELECT message_id FROM workflow_step_tasks
        WHERE workflow_slug = $1 AND step_slug = 'step1' AND task_index = 0
        """,
        [slug]
      )

    assert mid2 == mid1
  end
end
