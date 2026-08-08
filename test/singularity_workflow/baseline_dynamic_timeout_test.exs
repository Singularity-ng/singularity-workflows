defmodule Singularity.Workflow.BaselineDynamicTimeoutTest do
  use ExUnit.Case, async: false

  alias Singularity.Workflow.{Executor, FlowBuilder, Repo, WorkflowRun}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Singularity.Workflow.TestClock.reset()
    {:ok, _} = Singularity.Workflow.TestWorkflowPrefix.cleanup_by_prefix("test_dyn_to_", Repo)
    :ok
  end

  test "simple execute_dynamic completes with explicit timeout" do
    {:ok, _} = FlowBuilder.create_flow("test_dyn_to_simple", Repo)
    {:ok, _} = FlowBuilder.add_step("test_dyn_to_simple", "step1", [], Repo)
    {:ok, _} = FlowBuilder.add_step("test_dyn_to_simple", "step2", ["step1"], Repo)

    fns = %{
      step1: fn input -> {:ok, Map.put(input, "s1", true)} end,
      step2: fn input -> {:ok, Map.put(input, "s2", true)} end
    }

    result =
      Executor.execute_dynamic("test_dyn_to_simple", %{"initial" => true}, fns, Repo,
        timeout: 15_000,
        poll_interval: 50
      )

    {:ok, %{rows: runs}} =
      Repo.query("SELECT id::text, status, remaining_steps FROM workflow_runs WHERE workflow_slug=$1", [
        "test_dyn_to_simple"
      ])

    {:ok, %{rows: states}} =
      Repo.query(
        "SELECT step_slug, status, remaining_deps, remaining_tasks FROM workflow_step_states WHERE workflow_slug=$1",
        ["test_dyn_to_simple"]
      )

    {:ok, %{rows: tasks}} =
      Repo.query(
        """
        SELECT step_slug, task_index, status, message_id IS NOT NULL
        FROM workflow_step_tasks WHERE workflow_slug = $1 ORDER BY step_slug, task_index
        """,
        ["test_dyn_to_simple"]
      )

    IO.inspect(result, label: "BASELINE_RESULT")
    IO.inspect(runs, label: "RUNS")
    IO.inspect(states, label: "STATES")
    IO.inspect(tasks, label: "STEP_TASKS")

    assert {:ok, result} = result
    # Leaf is step2; its output is flat-merged prior keys + s2 (jsonb string keys)
    assert result["s1"] == true
    assert result["s2"] == true
    assert hd(runs) |> Enum.at(1) == "completed"
  end
end
