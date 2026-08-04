defmodule Singularity.Workflow.StartTasksRaceClaimTest do
  @moduledoc """
  Falsifier: two concurrent start_tasks on the same msg_id must yield exactly
  one claim (attempts_count=1, single claimed_by).
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    # Allow two client connections to race inside one checked-out sandbox owner
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "concurrent start_tasks on one msg_id claims exactly once" do
    slug = "test_race_claim_#{System.unique_integer([:positive])}"
    run_id = Ecto.UUID.generate()
    {:ok, run_bin} = Ecto.UUID.dump(run_id)

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

    parent = self()

    t1 =
      Task.async(fn ->
        :ok = Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
        {:ok, %{rows: rows}} =
          Repo.query("SELECT count(*) FROM start_tasks($1, ARRAY[$2]::bigint[], $3)", [
            slug,
            msg_id,
            "race-w1"
          ])

        send(parent, {:done, :w1, rows})
        rows
      end)

    t2 =
      Task.async(fn ->
        :ok = Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
        {:ok, %{rows: rows}} =
          Repo.query("SELECT count(*) FROM start_tasks($1, ARRAY[$2]::bigint[], $3)", [
            slug,
            msg_id,
            "race-w2"
          ])

        send(parent, {:done, :w2, rows})
        rows
      end)

    r1 = Task.await(t1, 15_000)
    r2 = Task.await(t2, 15_000)

    claimed_counts = [hd(hd(r1)), hd(hd(r2))] |> Enum.sort()
    assert claimed_counts == [0, 1]

    {:ok, %{rows: [[status, attempts]]}} =
      Repo.query(
        """
        SELECT status, attempts_count
        FROM workflow_step_tasks
        WHERE workflow_slug = $1 AND message_id = $2
        """,
        [slug, msg_id]
      )

    assert status == "started"
    assert attempts == 1
  end
end
