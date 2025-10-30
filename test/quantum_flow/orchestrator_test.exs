defmodule QuantumFlow.OrchestratorTest do
  use ExUnit.Case, async: true

  alias QuantumFlow.Orchestrator

  setup do
    QuantumFlow.Test.MoxHelper.setup_mox()
    Mox.set_mox_global()
    :ok
  end

  describe "decompose_goal/3" do
    test "decomposes goal successfully" do
      decomposer = fn goal ->
        {:ok,
         [
           %{id: "task1", description: "Analyze requirements", depends_on: []},
           %{id: "task2", description: "Design architecture", depends_on: ["task1"]},
           %{id: "task3", description: "Implement solution", depends_on: ["task2"]}
         ]}
      end

      {:ok, task_graph} = Orchestrator.decompose_goal("Build auth system", decomposer)

      # Focused assertions for critical properties
      assert %{tasks: tasks, root_tasks: root_tasks} = task_graph
      assert map_size(tasks) == 3
      assert length(root_tasks) == 1
      assert tasks["task1"].description == "Analyze requirements"
      assert tasks["task2"].depends_on == ["task1"]
      assert tasks["task3"].depends_on == ["task2"]

      # Snapshot for complete structure regression detection
      QuantumFlow.Test.Snapshot.assert_snapshot(task_graph, "orchestrator_decompose_goal_linear")
    end

    test "handles decomposer errors" do
      decomposer = fn _goal -> {:error, :decomposition_failed} end

      {:error, :decomposition_failed} = Orchestrator.decompose_goal("Invalid goal", decomposer)
    end

    test "handles invalid decomposer results" do
      decomposer = fn _goal -> :invalid_result end

      {:error, :invalid_decomposer_result} = Orchestrator.decompose_goal("Invalid goal", decomposer)
    end

    test "handles decomposer exceptions" do
      decomposer = fn _goal -> raise "Decomposer error" end

      {:error, %RuntimeError{message: "Decomposer error"}} =
        Orchestrator.decompose_goal("Invalid goal", decomposer)
    end

    test "respects max_depth option" do
      decomposer = fn goal ->
        {:ok,
         [
           %{id: "task1", description: "Task 1", depends_on: []},
           %{id: "task2", description: "Task 2", depends_on: ["task1"]},
           %{id: "task3", description: "Task 3", depends_on: ["task2"]}
         ]}
      end

      {:ok, task_graph} = Orchestrator.decompose_goal("Test goal", decomposer, max_depth: 2)

      assert task_graph.max_depth == 2
    end
  end

  describe "create_workflow/3" do
    test "creates workflow from task graph" do
      task_graph = %{
        tasks: %{
          "task1" => %{id: "task1", description: "Task 1", depends_on: []},
          "task2" => %{id: "task2", description: "Task 2", depends_on: ["task1"]}
        },
        root_tasks: [%{id: "task1", description: "Task 1", depends_on: []}],
        max_depth: 2,
        created_at: DateTime.utc_now()
      }

      step_functions = %{
        "task1" => fn _ -> {:ok, "result1"} end,
        "task2" => fn _ -> {:ok, "result2"} end
      }

      {:ok, workflow} = Orchestrator.create_workflow(task_graph, step_functions)

      assert workflow.name == "htdag_workflow"
      assert length(workflow.steps) == 2
      assert workflow.max_parallel == 10
      assert workflow.task_graph == task_graph
    end

    test "handles missing step functions" do
      task_graph = %{
        tasks: %{
          "task1" => %{id: "task1", description: "Task 1", depends_on: []}
        },
        root_tasks: [%{id: "task1", description: "Task 1", depends_on: []}],
        max_depth: 1,
        created_at: DateTime.utc_now()
      }

      step_functions = %{}

      {:error, %RuntimeError{message: "No step function found for task: task1"}} =
        Orchestrator.create_workflow(task_graph, step_functions)
    end

    test "respects workflow options" do
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

      opts = [
        workflow_name: "custom_workflow",
        max_parallel: 5,
        retry_attempts: 2
      ]

      {:ok, workflow} = Orchestrator.create_workflow(task_graph, step_functions, opts)

      assert workflow.name == "custom_workflow"
      assert workflow.max_parallel == 5
    end
  end

  describe "execute_goal/5" do
    test "executes goal successfully" do
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

      # Mock the Executor
      Mox.stub(QuantumFlow.Executor.Mock, :execute, fn _workflow, _context, _repo ->
        {:ok, %{success: true, results: %{"task1" => "result1", "task2" => "result2"}}}
      end)

      {:ok, result} =
        Orchestrator.execute_goal("Test goal", decomposer, step_functions, QuantumFlow.Repo)

      assert result.success == true
      assert result.results["task1"] == "result1"
      assert result.results["task2"] == "result2"
    end

    test "handles decomposition failure" do
      decomposer = fn _goal -> {:error, :decomposition_failed} end
      step_functions = %{}

      {:error, :decomposition_failed} =
        Orchestrator.execute_goal("Invalid goal", decomposer, step_functions, QuantumFlow.Repo)
    end

    test "handles workflow creation failure" do
      decomposer = fn _goal ->
        {:ok, [%{id: "task1", description: "Task 1", depends_on: []}]}
      end

      # Missing step function
      step_functions = %{}

      {:error, %RuntimeError{}} =
        Orchestrator.execute_goal("Test goal", decomposer, step_functions, QuantumFlow.Repo)
    end
  end

  describe "get_execution_stats/2" do
    test "returns execution statistics" do
      {:ok, stats} = Orchestrator.get_execution_stats("test_workflow", QuantumFlow.Repo)

      assert %{total_executions: total, success_rate: rate, avg_duration: duration} = stats
      assert is_integer(total)
      assert is_float(rate)
      assert is_integer(duration)
    end
  end
end
