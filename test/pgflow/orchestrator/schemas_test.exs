defmodule Pgflow.Orchestrator.SchemasTest do
  use ExUnit.Case, async: true

  alias Pgflow.Orchestrator.Schemas

  describe "TaskGraph changeset" do
    test "valid changeset" do
      attrs = %{
        name: "test_task_graph",
        goal: "Build auth system",
        decomposer_module: "MyApp.GoalDecomposer",
        task_graph: %{tasks: %{}, root_tasks: []},
        max_depth: 3
      }

      changeset = Schemas.TaskGraph.changeset(%Schemas.TaskGraph{}, attrs)

      assert changeset.valid?
      assert changeset.changes.name == "test_task_graph"
      assert changeset.changes.goal == "Build auth system"
      assert changeset.changes.decomposer_module == "MyApp.GoalDecomposer"
      assert changeset.changes.max_depth == 3
    end

    test "invalid changeset with missing required fields" do
      attrs = %{name: "test_task_graph"}

      changeset = Schemas.TaskGraph.changeset(%Schemas.TaskGraph{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).goal
      assert "can't be blank" in errors_on(changeset).decomposer_module
      assert "can't be blank" in errors_on(changeset).task_graph
    end

    test "invalid changeset with invalid max_depth" do
      attrs = %{
        name: "test_task_graph",
        goal: "Build auth system",
        decomposer_module: "MyApp.GoalDecomposer",
        task_graph: %{tasks: %{}, root_tasks: []},
        max_depth: 0
      }

      changeset = Schemas.TaskGraph.changeset(%Schemas.TaskGraph{}, attrs)

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).max_depth
    end

    test "invalid changeset with max_depth too high" do
      attrs = %{
        name: "test_task_graph",
        goal: "Build auth system",
        decomposer_module: "MyApp.GoalDecomposer",
        task_graph: %{tasks: %{}, root_tasks: []},
        max_depth: 25
      }

      changeset = Schemas.TaskGraph.changeset(%Schemas.TaskGraph{}, attrs)

      refute changeset.valid?
      assert "must be less than 20" in errors_on(changeset).max_depth
    end
  end

  describe "Workflow changeset" do
    test "valid changeset" do
      attrs = %{
        name: "test_workflow",
        workflow_definition: %{steps: []},
        step_functions: %{"task1" => fn -> :ok end},
        max_parallel: 5,
        retry_attempts: 2,
        status: "created"
      }

      changeset = Schemas.Workflow.workflow_changeset(%Schemas.Workflow{}, attrs)

      assert changeset.valid?
      assert changeset.changes.name == "test_workflow"
      assert changeset.changes.max_parallel == 5
      assert changeset.changes.retry_attempts == 2
      assert changeset.changes.status == "created"
    end

    test "invalid changeset with missing required fields" do
      attrs = %{name: "test_workflow"}

      changeset = Schemas.Workflow.workflow_changeset(%Schemas.Workflow{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).workflow_definition
      assert "can't be blank" in errors_on(changeset).step_functions
    end

    test "invalid changeset with invalid max_parallel" do
      attrs = %{
        name: "test_workflow",
        workflow_definition: %{steps: []},
        step_functions: %{"task1" => fn -> :ok end},
        max_parallel: 0
      }

      changeset = Schemas.Workflow.workflow_changeset(%Schemas.Workflow{}, attrs)

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).max_parallel
    end

    test "invalid changeset with invalid status" do
      attrs = %{
        name: "test_workflow",
        workflow_definition: %{steps: []},
        step_functions: %{"task1" => fn -> :ok end},
        status: "invalid_status"
      }

      changeset = Schemas.Workflow.workflow_changeset(%Schemas.Workflow{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end
  end

  describe "Execution changeset" do
    test "valid changeset" do
      attrs = %{
        execution_id: "exec_123",
        goal_context: %{goal: "Build auth system"},
        status: "running",
        started_at: DateTime.utc_now()
      }

      changeset = Schemas.Execution.execution_changeset(%Schemas.Execution{}, attrs)

      assert changeset.valid?
      assert changeset.changes.execution_id == "exec_123"
      assert changeset.changes.status == "running"
    end

    test "invalid changeset with missing required fields" do
      attrs = %{status: "running"}

      changeset = Schemas.Execution.execution_changeset(%Schemas.Execution{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).execution_id
      assert "can't be blank" in errors_on(changeset).goal_context
    end

    test "invalid changeset with invalid status" do
      attrs = %{
        execution_id: "exec_123",
        goal_context: %{goal: "Build auth system"},
        status: "invalid_status"
      }

      changeset = Schemas.Execution.execution_changeset(%Schemas.Execution{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end
  end

  describe "TaskExecution changeset" do
    test "valid changeset" do
      attrs = %{
        task_id: "task_123",
        task_name: "Task 1",
        status: "pending",
        retry_count: 0
      }

      changeset = Schemas.TaskExecution.task_execution_changeset(%Schemas.TaskExecution{}, attrs)

      assert changeset.valid?
      assert changeset.changes.task_id == "task_123"
      assert changeset.changes.task_name == "Task 1"
      assert changeset.changes.status == "pending"
      assert changeset.changes.retry_count == 0
    end

    test "invalid changeset with missing required fields" do
      attrs = %{status: "pending"}

      changeset = Schemas.TaskExecution.task_execution_changeset(%Schemas.TaskExecution{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).task_id
      assert "can't be blank" in errors_on(changeset).task_name
    end

    test "invalid changeset with invalid retry_count" do
      attrs = %{
        task_id: "task_123",
        task_name: "Task 1",
        retry_count: 15
      }

      changeset = Schemas.TaskExecution.task_execution_changeset(%Schemas.TaskExecution{}, attrs)

      refute changeset.valid?
      assert "must be less than 10" in errors_on(changeset).retry_count
    end
  end

  describe "Event changeset" do
    test "valid changeset" do
      attrs = %{
        event_type: "task:started",
        event_data: %{task_id: "task_123"},
        timestamp: DateTime.utc_now()
      }

      changeset = Schemas.Event.event_changeset(%Schemas.Event{}, attrs)

      assert changeset.valid?
      assert changeset.changes.event_type == "task:started"
      assert changeset.changes.event_data == %{task_id: "task_123"}
    end

    test "invalid changeset with missing required fields" do
      attrs = %{timestamp: DateTime.utc_now()}

      changeset = Schemas.Event.event_changeset(%Schemas.Event{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).event_type
      assert "can't be blank" in errors_on(changeset).event_data
    end

    test "invalid changeset with invalid event_type" do
      attrs = %{
        event_type: "invalid:event",
        event_data: %{task_id: "task_123"}
      }

      changeset = Schemas.Event.event_changeset(%Schemas.Event{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).event_type
    end
  end

  describe "PerformanceMetric changeset" do
    test "valid changeset" do
      attrs = %{
        task_id: "task_123",
        metric_type: "execution_time",
        metric_value: 1500.0,
        metric_unit: "ms",
        context: %{workflow_id: "workflow_123"}
      }

      changeset = Schemas.PerformanceMetric.performance_metric_changeset(%Schemas.PerformanceMetric{}, attrs)

      assert changeset.valid?
      assert changeset.changes.metric_type == "execution_time"
      assert changeset.changes.metric_value == 1500.0
      assert changeset.changes.metric_unit == "ms"
    end

    test "invalid changeset with missing required fields" do
      attrs = %{task_id: "task_123"}

      changeset = Schemas.PerformanceMetric.performance_metric_changeset(%Schemas.PerformanceMetric{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).metric_type
      assert "can't be blank" in errors_on(changeset).metric_value
    end

    test "invalid changeset with invalid metric_type" do
      attrs = %{
        metric_type: "invalid_metric",
        metric_value: 1500.0
      }

      changeset = Schemas.PerformanceMetric.performance_metric_changeset(%Schemas.PerformanceMetric{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).metric_type
    end

    test "invalid changeset with negative metric_value" do
      attrs = %{
        metric_type: "execution_time",
        metric_value: -100.0
      }

      changeset = Schemas.PerformanceMetric.performance_metric_changeset(%Schemas.PerformanceMetric{}, attrs)

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).metric_value
    end
  end

  describe "LearningPattern changeset" do
    test "valid changeset" do
      attrs = %{
        workflow_name: "test_workflow",
        pattern_type: "parallelization",
        pattern_data: %{tasks: ["task1", "task2"]},
        confidence_score: 0.85,
        usage_count: 5
      }

      changeset = Schemas.LearningPattern.learning_pattern_changeset(%Schemas.LearningPattern{}, attrs)

      assert changeset.valid?
      assert changeset.changes.workflow_name == "test_workflow"
      assert changeset.changes.pattern_type == "parallelization"
      assert changeset.changes.confidence_score == 0.85
      assert changeset.changes.usage_count == 5
    end

    test "invalid changeset with missing required fields" do
      attrs = %{workflow_name: "test_workflow"}

      changeset = Schemas.LearningPattern.learning_pattern_changeset(%Schemas.LearningPattern{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).pattern_type
      assert "can't be blank" in errors_on(changeset).pattern_data
    end

    test "invalid changeset with invalid confidence_score" do
      attrs = %{
        workflow_name: "test_workflow",
        pattern_type: "parallelization",
        pattern_data: %{tasks: ["task1", "task2"]},
        confidence_score: 1.5
      }

      changeset = Schemas.LearningPattern.learning_pattern_changeset(%Schemas.LearningPattern{}, attrs)

      refute changeset.valid?
      assert "must be less than or equal to 1" in errors_on(changeset).confidence_score
    end

    test "invalid changeset with invalid pattern_type" do
      attrs = %{
        workflow_name: "test_workflow",
        pattern_type: "invalid_pattern",
        pattern_data: %{tasks: ["task1", "task2"]}
      }

      changeset = Schemas.LearningPattern.learning_pattern_changeset(%Schemas.LearningPattern{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).pattern_type
    end
  end

  # Helper function to get errors from changeset
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end