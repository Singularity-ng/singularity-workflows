defmodule Singularity.Workflow.FailTaskPermanentArchiveTest do
  @moduledoc """
  Falsifier: when attempts_count >= max_attempts, fail_task must archive the
  pgmq message so it cannot redeliver after set_vt(0).
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "permanent fail_task archives message_id" do
    slug = "test_fail_arch_#{System.unique_integer([:positive])}"
    {:ok, run_bin} = Ecto.UUID.dump(Ecto.UUID.generate())
    worker = "worker-fail"

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
        VALUES ($1, 'step1', 'single', 0, 1, 2, 60)
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
        SELECT $2, 'step1', $1, 0, 'started', s.send, $3, 2, 2,
               $4, now(), now(), now(), now()
        FROM sent s
        RETURNING message_id
        """,
        [slug, run_bin, slug <> ":step1:0", worker]
      )

    {:ok, _} =
      Repo.query("SELECT singularity_workflow.fail_task($1, 'step1', 0, 'permanent boom')", [
        run_bin
      ])

    {:ok, %{rows: [[status, mid]]}} =
      Repo.query(
        """
        SELECT status, message_id
        FROM workflow_step_tasks
        WHERE workflow_slug = $1 AND task_index = 0 AND step_slug = 'step1'
        """,
        [slug]
      )

    assert status == "failed"
    # message_id may remain for audit; archive is the pgmq contract
    _ = mid

    _ = Repo.query("SELECT pgmq.set_vt($1, $2, 0)", [slug, msg_id])

    {:ok, %{rows: read_rows}} =
      Repo.query("SELECT msg_id FROM pgmq.read($1, 1, 10)", [slug])

    read_ids = Enum.map(read_rows, fn [id | _] -> id end)
    refute msg_id in read_ids
  end
end
