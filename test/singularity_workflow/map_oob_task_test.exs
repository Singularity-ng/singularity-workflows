defmodule Singularity.Workflow.MapOobTaskTest do
  @moduledoc """
  Falsifier: start_tasks must fail+archive map claims whose task_index is past
  the parent array length, and still return in-bounds indexes for execution.
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "start_tasks fails OOB map indexes and returns in-bounds slices" do
    slug = "test_map_oob_#{System.unique_integer([:positive])}"
    run_id = Ecto.UUID.generate()
    {:ok, run_bin} = Ecto.UUID.dump(run_id)
    worker = "worker-oob"

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
        VALUES ($1, 'fetch', 'single', 0, 1, 3, 60),
               ($1, 'process', 'map', 1, 4, 3, 60)
        """,
        [slug]
      )

    {:ok, _} =
      Repo.query(
        """
        INSERT INTO workflow_runs (id, workflow_slug, status, input, remaining_steps, started_at, inserted_at, updated_at)
        VALUES ($1, $2, 'started', '{}'::jsonb, 2, now(), now(), now())
        """,
        [run_bin, slug]
      )

    {:ok, _} =
      Repo.query(
        """
        INSERT INTO workflow_step_states (run_id, step_slug, workflow_slug, status, remaining_deps, remaining_tasks, initial_tasks, inserted_at, updated_at)
        VALUES
          ($1, 'fetch', $2, 'completed', 0, 0, 1, now(), now()),
          ($1, 'process', $2, 'started', 0, 4, 4, now(), now())
        """,
        [run_bin, slug]
      )

    {:ok, _} =
      Repo.query(
        """
        INSERT INTO workflow_step_dependencies (run_id, step_slug, depends_on_step, inserted_at)
        VALUES ($1, 'process', 'fetch', now())
        """,
        [run_bin]
      )

    {:ok, _} =
      Repo.query(
        """
        INSERT INTO workflow_step_tasks (
          run_id, step_slug, workflow_slug, task_index, status, output,
          idempotency_key, attempts_count, max_attempts, inserted_at, updated_at
        ) VALUES ($1, 'fetch', $2, 0, 'completed', '[10, 20]'::jsonb,
          $3, 1, 3, now(), now())
        """,
        [run_bin, slug, slug <> ":fetch:0"]
      )

    msg_ids =
      Enum.map(0..3, fn i ->
        {:ok, %{rows: [[mid]]}} =
          Repo.query(
            """
            WITH sent AS (SELECT * FROM pgmq.send($1, jsonb_build_object('i', $2::int)))
            INSERT INTO workflow_step_tasks (
              run_id, step_slug, workflow_slug, task_index, status, message_id,
              idempotency_key, attempts_count, max_attempts, inserted_at, updated_at
            )
            SELECT $3, 'process', $1, $2, 'queued', s.send, $1 || ':p:' || $2::text, 0, 3, now(), now()
            FROM sent s
            RETURNING message_id
            """,
            [slug, i, run_bin]
          )

        mid
      end)

    {:ok, %{rows: claimed}} =
      Repo.query(
        """
        SELECT task_index, input
        FROM start_tasks($1, $2::bigint[], $3)
        ORDER BY task_index
        """,
        [slug, msg_ids, worker]
      )

    assert claimed == [[0, 10], [1, 20]]

    {:ok, %{rows: statuses}} =
      Repo.query(
        """
        SELECT task_index, status, left(coalesce(error_message, ''), 20)
        FROM workflow_step_tasks
        WHERE workflow_slug = $1 AND step_slug = 'process'
        ORDER BY task_index
        """,
        [slug]
      )

    assert statuses == [
             [0, "started", ""],
             [1, "started", ""],
             [2, "failed", "[MAP_OOB] task_index"],
             [3, "failed", "[MAP_OOB] task_index"]
           ]
  end

  test "execute_dynamic runs in-bounds map workers; OOB indexes end failed" do
    alias Singularity.Workflow.{Executor, FlowBuilder, StepTask}
    import Ecto.Query

    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Singularity.Workflow.TestClock.reset()
    {:ok, _} = Singularity.Workflow.TestWorkflowPrefix.cleanup_by_prefix("test_map_oob_dyn_", Repo)

    slug = "test_map_oob_dyn_short"
    assert {:ok, _} = FlowBuilder.create_flow(slug, Repo)

    assert {:ok, _} =
             FlowBuilder.add_step(slug, "fetch", [], Repo, step_type: "single", initial_tasks: 1)

    assert {:ok, _} =
             FlowBuilder.add_step(slug, "process", ["fetch"], Repo,
               step_type: "map",
               initial_tasks: 4
             )

    agent = start_supervised!({Agent, fn -> [] end})

    step_functions = %{
      fetch: fn _ -> {:ok, [10, 20]} end,
      process: fn input ->
        Agent.update(agent, &[input | &1])
        {:ok, %{"item" => input}}
      end
    }

    _ = Executor.execute_dynamic(slug, %{}, step_functions, Repo, timeout: 45_000, poll_interval: 50)

    assert Agent.get(agent, & &1) |> Enum.sort() == [10, 20]

    statuses =
      from(t in StepTask,
        where: t.workflow_slug == ^slug and t.step_slug == "process",
        select: {t.task_index, t.status},
        order_by: [asc: t.task_index]
      )
      |> Repo.all()

    assert statuses == [{0, "completed"}, {1, "completed"}, {2, "failed"}, {3, "failed"}]
  end
end
