defmodule Singularity.Workflow.WorkflowComposerTest do
  use ExUnit.Case, async: true

  alias Singularity.Workflow.WorkflowComposer

  setup do
    Singularity.Workflow.Test.MoxHelper.setup_mox()
    Mox.set_mox_global()
    :ok
  end

  describe "compose_from_goal/5" do
    test "composes and executes workflow successfully" do
      decomposer = fn goal ->
        {:ok,
         [
           %{id: "task1", description: "Task 1", depends_on: []},
           %{id: "task2", description: "Task 2", depends_on: ["task1"]}
         ]}
      end

      step_functions = %{
        "task1" => fn _ -> {:ok, "result1"} end,
        "task2" => fn _ -> {:ok, "result2"} end
      }

      # Mock the Orchestrator modules
      Mox.stub(Singularity.Workflow.Orchestrator.Mock, :decompose_goal, fn _, _, _ ->
        {:ok, %{tasks: %{}, root_tasks: [], max_depth: 2, created_at: DateTime.utc_now()}}
      end)

      Mox.stub(Singularity.Workflow.Orchestrator.Mock, :create_workflow, fn _, _, _ ->
        {:ok, %{name: "test_workflow", steps: [], max_parallel: 10}}
      end)

      Mox.stub(Singularity.Workflow.Orchestrator.Executor.Mock, :execute_workflow, fn _, _, _, _ ->
        {:ok, %{success: true, results: %{"task1" => "result1", "task2" => "result2"}}}
      end)

      {:ok, result} =
        WorkflowComposer.compose_from_goal(
          "Build auth system",
          decomposer,
          step_functions,
          Singularity.Workflow.Repo
        )

      # Focused assertions for critical behavior
      assert result.success == true
      assert result.results["task1"] == "result1"
      assert result.results["task2"] == "result2"

      # Snapshot for execution result structure regression detection
      Singularity.Workflow.Test.Snapshot.assert_snapshot(result, "workflow_composer_execution_result")
    end

    test "handles decomposition failure" do
      decomposer = fn _goal -> {:error, :decomposition_failed} end
      step_functions = %{}

      Mox.stub(Singularity.Workflow.Orchestrator.Mock, :decompose_goal, fn _, _, _ ->
        {:error, :decomposition_failed}
      end)

      {:error, :decomposition_failed} =
        WorkflowComposer.compose_from_goal(
          "Invalid goal",
          decomposer,
          step_functions,
          Singularity.Workflow.Repo
        )
    end

    test "handles workflow creation failure" do
      decomposer = fn _goal ->
        {:ok, [%{id: "task1", description: "Task 1", depends_on: []}]}
      end

      step_functions = %{}

      Mox.stub(Singularity.Workflow.Orchestrator.Mock, :decompose_goal, fn _, _, _ ->
        {:ok, %{tasks: %{}, root_tasks: [], max_depth: 1, created_at: DateTime.utc_now()}}
      end)

      Mox.stub(Singularity.Workflow.Orchestrator.Mock, :create_workflow, fn _, _, _ ->
        {:error, :workflow_creation_failed}
      end)

      {:error, :workflow_creation_failed} =
        WorkflowComposer.compose_from_goal(
          "Test goal",
          decomposer,
          step_functions,
          Singularity.Workflow.Repo
        )
    end

    test "respects optimization and monitoring options" do
      decomposer = fn _goal ->
        {:ok, [%{id: "task1", description: "Task 1", depends_on: []}]}
      end

      step_functions = %{
        "task1" => fn _ -> {:ok, "result1"} end
      }

      Mox.stub(Singularity.Workflow.Orchestrator.Mock, :decompose_goal, fn _, _, _ ->
        {:ok, %{tasks: %{}, root_tasks: [], max_depth: 1, created_at: DateTime.utc_now()}}
      end)

      Mox.stub(Singularity.Workflow.Orchestrator.Mock, :create_workflow, fn _, _, _ ->
        {:ok, %{name: "test_workflow", steps: [], max_parallel: 10}}
      end)

      Mox.stub(Singularity.Workflow.Orchestrator.Executor.Mock, :execute_workflow, fn _, _, _, opts ->
        assert Keyword.get(opts, :monitor) == true
        {:ok, %{success: true}}
      end)

      WorkflowComposer.compose_from_goal(
        "Test goal",
        decomposer,
        step_functions,
        Singularity.Workflow.Repo,
        optimize: true,
        monitor: true
      )
    end
  end

  describe "compose_from_task_graph/4" do
    test "composes workflow from existing task graph" do
      task_graph = %{
        tasks: %{
          "task1" => %{id: "task1", description: "Task 1", depends_on: []}
        },
        root_tasks: [%{id: "task1", description: "Task 1", depends_on: []}],
        max_depth: 1,
        created_at: DateTime.utc_now()
      }

      step_functions = %{
        "task1" => fn _ -> {:ok, "result1"} end
      }

      Mox.stub(Singularity.Workflow.Orchestrator.Mock, :create_workflow, fn _, _, _ ->
        {:ok, %{name: "test_workflow", steps: [], max_parallel: 10}}
      end)

      Mox.stub(Singularity.Workflow.Orchestrator.Executor.Mock, :execute_workflow, fn _, _, _, _ ->
        {:ok, %{success: true}}
      end)

      {:ok, result} =
        WorkflowComposer.compose_from_task_graph(
          task_graph,
          step_functions,
          Singularity.Workflow.Repo
        )

      assert result.success == true
    end
  end

  describe "compose_multiple_workflows/5" do
    test "composes multiple workflows from complex goal" do
      decomposer = fn _goal ->
        {:ok,
         [
           %{
             tasks: %{"task1" => %{id: "task1", description: "Task 1", depends_on: []}},
             root_tasks: [],
             max_depth: 1,
             created_at: DateTime.utc_now()
           },
           %{
             tasks: %{"task2" => %{id: "task2", description: "Task 2", depends_on: []}},
             root_tasks: [],
             max_depth: 1,
             created_at: DateTime.utc_now()
           }
         ]}
      end

      step_functions = %{
        "task1" => fn _ -> {:ok, "result1"} end,
        "task2" => fn _ -> {:ok, "result2"} end
      }

      Mox.stub(Singularity.Workflow.Orchestrator.Mock, :create_workflow, fn _, _, _ ->
        {:ok, %{name: "test_workflow", steps: [], max_parallel: 10}}
      end)

      Mox.stub(Singularity.Workflow.Orchestrator.Executor.Mock, :execute_workflow, fn _, _, _, _ ->
        {:ok, %{success: true}}
      end)

      {:ok, results} =
        WorkflowComposer.compose_multiple_workflows(
          "Complex goal",
          decomposer,
          step_functions,
          Singularity.Workflow.Repo
        )

      assert length(results) == 2
      assert Enum.all?(results, &(&1.success == true))
    end

    test "handles partial workflow failures" do
      decomposer = fn _goal ->
        {:ok,
         [
           %{
             tasks: %{"task1" => %{id: "task1", description: "Task 1", depends_on: []}},
             root_tasks: [],
             max_depth: 1,
             created_at: DateTime.utc_now()
           },
           %{
             tasks: %{"task2" => %{id: "task2", description: "Task 2", depends_on: []}},
             root_tasks: [],
             max_depth: 1,
             created_at: DateTime.utc_now()
           }
         ]}
      end

      step_functions = %{
        "task1" => fn _ -> {:ok, "result1"} end,
        "task2" => fn _ -> {:ok, "result2"} end
      }

      Mox.stub(Singularity.Workflow.Orchestrator.Mock, :create_workflow, fn _, _, _ ->
        {:ok, %{name: "test_workflow", steps: [], max_parallel: 10}}
      end)

      Mox.stub(Singularity.Workflow.Orchestrator.Executor.Mock, :execute_workflow, fn _, _, _, _ ->
        {:error, :execution_failed}
      end)

      {:error, :workflow_execution_failed} =
        WorkflowComposer.compose_multiple_workflows(
          "Complex goal",
          decomposer,
          step_functions,
          Singularity.Workflow.Repo
        )
    end
  end

  describe "get_composition_stats/2" do
    test "returns composition statistics" do
      {:ok, stats} = WorkflowComposer.get_composition_stats(Singularity.Workflow.Repo)

      assert %{
               total_workflows: total,
               successful_compositions: successful,
               failed_compositions: failed,
               avg_execution_time: avg_time,
               most_common_goals: common_goals
             } = stats

      assert is_integer(total)
      assert is_integer(successful)
      assert is_integer(failed)
      assert is_integer(avg_time)
      assert is_list(common_goals)
    end

    test "filters statistics by workflow name" do
      {:ok, stats} =
        WorkflowComposer.get_composition_stats(Singularity.Workflow.Repo,
          workflow_name: "test_workflow"
        )

      assert is_map(stats)
    end
  end
end
