defmodule Singularity.Workflow.MapReduceClaimTest do
  @moduledoc """
  Falsifier: start_tasks for a save step after a completed map must return
  nested process outputs as an ordered JSON array.
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "start_tasks aggregates map dep outputs for save" do
    slug = "test_map_red_claim_#{System.unique_integer([:positive])}"
    {:ok, run_bin} = Ecto.UUID.dump(Ecto.UUID.generate())

    {:ok, _} = Repo.query("SELECT pgmq.create($1)", [slug])

    {:ok, _} =
      Repo.query(
        "INSERT INTO workflows (workflow_slug, max_attempts, timeout, created_at) VALUES ($1,3,60,now()) ON CONFLICT DO NOTHING",
        [slug]
      )

    for {step, type, idx, n} <- [
          {"fetch", "single", 0, 1},
          {"process", "map", 1, 3},
          {"save", "single", 2, 1}
        ] do
      {:ok, _} =
        Repo.query(
          """
          INSERT INTO workflow_steps (workflow_slug, step_slug, step_type, step_index, initial_tasks, max_attempts, timeout)
          VALUES ($1,$2,$3,$4,$5,3,60)
          """,
          [slug, step, type, idx, n]
        )
    end

    {:ok, _} =
      Repo.query(
        """
        INSERT INTO workflow_runs (id, workflow_slug, status, input, remaining_steps, started_at, inserted_at, updated_at)
        VALUES ($1,$2,'started','{}'::jsonb,1,now(),now(),now())
        """,
        [run_bin, slug]
      )

    for {step, status, rem} <- [
          {"fetch", "completed", 0},
          {"process", "completed", 0},
          {"save", "started", 1}
        ] do
      {:ok, _} =
        Repo.query(
          """
          INSERT INTO workflow_step_states (run_id, step_slug, workflow_slug, status, remaining_deps, remaining_tasks, initial_tasks, inserted_at, updated_at)
          VALUES ($1,$2,$3,$4,0,$5,$5,now(),now())
          """,
          [run_bin, step, slug, status, rem]
        )
    end

    {:ok, _} =
      Repo.query(
        "INSERT INTO workflow_step_dependencies (run_id, step_slug, depends_on_step, inserted_at) VALUES ($1,'process','fetch',now())",
        [run_bin]
      )

    {:ok, _} =
      Repo.query(
        "INSERT INTO workflow_step_dependencies (run_id, step_slug, depends_on_step, inserted_at) VALUES ($1,'save','process',now())",
        [run_bin]
      )

    {:ok, _} =
      Repo.query(
        """
        INSERT INTO workflow_step_tasks (
          run_id, step_slug, workflow_slug, task_index, status, output,
          idempotency_key, attempts_count, max_attempts, inserted_at, updated_at
        ) VALUES ($1,'fetch',$2,0,'completed','[1,2,3]'::jsonb,$3,1,3,now(),now())
        """,
        [run_bin, slug, slug <> ":fetch:0"]
      )

    for i <- 0..2 do
      {:ok, _} =
        Repo.query(
          """
          INSERT INTO workflow_step_tasks (
            run_id, step_slug, workflow_slug, task_index, status, output,
            idempotency_key, attempts_count, max_attempts, inserted_at, updated_at
          ) VALUES ($1,'process',$2,$3,'completed',($4::text)::jsonb,$5,1,3,now(),now())
          """,
          [run_bin, slug, i, Jason.encode!(%{"item" => i}), "#{slug}:process:#{i}"]
        )
    end

    {:ok, %{rows: [[msg_id]]}} =
      Repo.query(
        """
        WITH sent AS (SELECT * FROM pgmq.send($1, '{}'::jsonb))
        INSERT INTO workflow_step_tasks (
          run_id, step_slug, workflow_slug, task_index, status, message_id,
          idempotency_key, attempts_count, max_attempts, inserted_at, updated_at
        )
        SELECT $2,'save',$1,0,'queued',s.send,$3,0,3,now(),now()
        FROM sent s
        RETURNING message_id
        """,
        [slug, run_bin, slug <> ":save:0"]
      )

    {:ok, %{rows: claimed}} =
      Repo.query(
        "SELECT input FROM start_tasks($1, ARRAY[$2]::bigint[], 'w-save')",
        [slug, msg_id]
      )

    assert length(claimed) == 1
    [[input]] = claimed
    assert is_list(input["process"])
    assert Enum.map(input["process"], & &1["item"]) == [0, 1, 2]
  end
end
