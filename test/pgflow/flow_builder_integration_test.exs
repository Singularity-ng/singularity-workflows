defmodule Pgflow.FlowBuilderIntegrationTest do
  use ExUnit.Case, async: false

  alias Pgflow.{FlowBuilder, Repo}
  import Ecto.Query

  @moduledoc """
  Comprehensive FlowBuilder integration tests covering all public API functions.

  Tests real database operations for:
  - create_flow/3
  - add_step/5
  - list_flows/1
  - get_flow/2
  - delete_flow/2
  """

  setup do
    # Clean up any existing workflows
    Repo.query!("DELETE FROM workflows")
    :ok
  end

  describe "create_flow/3" do
    test "creates workflow with valid slug" do
      {:ok, workflow} = FlowBuilder.create_flow("test_workflow", Repo)

      assert workflow["workflow_slug"] == "test_workflow"
      assert workflow["max_attempts"] == 3
      assert workflow["timeout"] == 60
    end

    test "creates workflow with custom max_attempts" do
      {:ok, workflow} = FlowBuilder.create_flow("retry_workflow", Repo, max_attempts: 5)

      assert workflow["workflow_slug"] == "retry_workflow"
      assert workflow["max_attempts"] == 5
    end

    test "creates workflow with custom timeout" do
      {:ok, workflow} = FlowBuilder.create_flow("timeout_workflow", Repo, timeout: 120)

      assert workflow["workflow_slug"] == "timeout_workflow"
      assert workflow["timeout"] == 120
    end

    test "creates workflow with both custom options" do
      {:ok, workflow} = FlowBuilder.create_flow("custom_workflow", Repo,
        max_attempts: 10,
        timeout: 300
      )

      assert workflow["max_attempts"] == 10
      assert workflow["timeout"] == 300
    end

    test "rejects empty workflow slug" do
      result = FlowBuilder.create_flow("", Repo)

      assert {:error, :workflow_slug_cannot_be_empty} = result
    end

    test "rejects workflow slug starting with number" do
      result = FlowBuilder.create_flow("123workflow", Repo)

      assert {:error, :workflow_slug_invalid_format} = result
    end

    test "rejects workflow slug with hyphens" do
      result = FlowBuilder.create_flow("my-workflow", Repo)

      assert {:error, :workflow_slug_invalid_format} = result
    end

    test "rejects workflow slug with spaces" do
      result = FlowBuilder.create_flow("my workflow", Repo)

      assert {:error, :workflow_slug_invalid_format} = result
    end

    test "rejects workflow slug longer than 255 characters" do
      long_slug = String.duplicate("a", 256)
      result = FlowBuilder.create_flow(long_slug, Repo)

      assert {:error, :workflow_slug_too_long} = result
    end

    test "rejects non-string workflow slug" do
      result = FlowBuilder.create_flow(:atom_slug, Repo)

      assert {:error, :workflow_slug_must_be_string} = result
    end

    test "rejects negative max_attempts" do
      result = FlowBuilder.create_flow("workflow", Repo, max_attempts: -1)

      assert {:error, :max_attempts_must_be_non_negative} = result
    end

    test "rejects zero timeout" do
      result = FlowBuilder.create_flow("workflow", Repo, timeout: 0)

      assert {:error, :timeout_must_be_positive} = result
    end

    test "rejects non-integer max_attempts" do
      result = FlowBuilder.create_flow("workflow", Repo, max_attempts: "five")

      assert {:error, :max_attempts_must_be_integer} = result
    end

    test "accepts workflow slug with underscores" do
      {:ok, workflow} = FlowBuilder.create_flow("my_workflow_v2", Repo)

      assert workflow["workflow_slug"] == "my_workflow_v2"
    end

    test "accepts workflow slug starting with underscore" do
      {:ok, workflow} = FlowBuilder.create_flow("_private", Repo)

      assert workflow["workflow_slug"] == "_private"
    end

    test "prevents duplicate workflow slugs" do
      {:ok, _} = FlowBuilder.create_flow("duplicate", Repo)
      result = FlowBuilder.create_flow("duplicate", Repo)

      # Should get error from PostgreSQL constraint
      assert {:error, _} = result
    end
  end

  describe "add_step/5" do
    setup do
      {:ok, _} = FlowBuilder.create_flow("test_workflow", Repo)
      :ok
    end

    test "adds root step with no dependencies" do
      {:ok, step} = FlowBuilder.add_step("test_workflow", "fetch", [], Repo)

      assert step["step_slug"] == "fetch"
      assert step["workflow_slug"] == "test_workflow"
      assert step["step_type"] == "single"
    end

    test "adds dependent step" do
      {:ok, _} = FlowBuilder.add_step("test_workflow", "fetch", [], Repo)
      {:ok, step} = FlowBuilder.add_step("test_workflow", "process", ["fetch"], Repo)

      assert step["step_slug"] == "process"
      assert step["deps_count"] == 1
    end

    test "adds map step with initial_tasks" do
      {:ok, _} = FlowBuilder.add_step("test_workflow", "fetch", [], Repo)
      {:ok, step} = FlowBuilder.add_step("test_workflow", "process_batch", ["fetch"], Repo,
        step_type: "map",
        initial_tasks: 50
      )

      assert step["step_type"] == "map"
      assert step["initial_tasks"] == 50
    end

    test "adds step with custom max_attempts" do
      {:ok, step} = FlowBuilder.add_step("test_workflow", "retry_step", [], Repo,
        max_attempts: 5
      )

      assert step["max_attempts"] == 5
    end

    test "adds step with custom timeout" do
      {:ok, step} = FlowBuilder.add_step("test_workflow", "slow_step", [], Repo,
        timeout: 300
      )

      assert step["timeout"] == 300
    end

    test "adds step with multiple dependencies" do
      {:ok, _} = FlowBuilder.add_step("test_workflow", "step_a", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_workflow", "step_b", [], Repo)
      {:ok, step} = FlowBuilder.add_step("test_workflow", "merge", ["step_a", "step_b"], Repo)

      assert step["deps_count"] == 2
    end

    test "rejects step with non-existent workflow" do
      result = FlowBuilder.add_step("nonexistent", "step", [], Repo)

      assert {:error, _} = result
    end

    test "rejects empty step slug" do
      result = FlowBuilder.add_step("test_workflow", "", [], Repo)

      assert {:error, :step_slug_cannot_be_empty} = result
    end

    test "rejects step slug starting with number" do
      result = FlowBuilder.add_step("test_workflow", "123step", [], Repo)

      assert {:error, :step_slug_invalid_format} = result
    end

    test "rejects step slug with special characters" do
      result = FlowBuilder.add_step("test_workflow", "step-name", [], Repo)

      assert {:error, :step_slug_invalid_format} = result
    end

    test "rejects invalid step type" do
      result = FlowBuilder.add_step("test_workflow", "step", [], Repo,
        step_type: "invalid"
      )

      assert {:error, :step_type_must_be_single_or_map} = result
    end

    test "rejects negative initial_tasks" do
      result = FlowBuilder.add_step("test_workflow", "step", [], Repo,
        initial_tasks: -1
      )

      assert {:error, :initial_tasks_must_be_positive} = result
    end

    test "rejects zero initial_tasks" do
      result = FlowBuilder.add_step("test_workflow", "step", [], Repo,
        initial_tasks: 0
      )

      assert {:error, :initial_tasks_must_be_positive} = result
    end

    test "prevents duplicate step slugs in same workflow" do
      {:ok, _} = FlowBuilder.add_step("test_workflow", "duplicate", [], Repo)
      result = FlowBuilder.add_step("test_workflow", "duplicate", [], Repo)

      assert {:error, _} = result
    end
  end

  describe "list_flows/1" do
    test "returns empty list when no workflows exist" do
      {:ok, workflows} = FlowBuilder.list_flows(Repo)

      assert workflows == []
    end

    test "returns all workflows" do
      {:ok, _} = FlowBuilder.create_flow("workflow_1", Repo)
      {:ok, _} = FlowBuilder.create_flow("workflow_2", Repo)
      {:ok, _} = FlowBuilder.create_flow("workflow_3", Repo)

      {:ok, workflows} = FlowBuilder.list_flows(Repo)

      assert length(workflows) == 3
      slugs = Enum.map(workflows, & &1["workflow_slug"]) |> Enum.sort()
      assert slugs == ["workflow_1", "workflow_2", "workflow_3"]
    end

    test "returns workflows ordered by created_at DESC" do
      {:ok, _} = FlowBuilder.create_flow("first", Repo)
      :timer.sleep(10)
      {:ok, _} = FlowBuilder.create_flow("second", Repo)
      :timer.sleep(10)
      {:ok, _} = FlowBuilder.create_flow("third", Repo)

      {:ok, workflows} = FlowBuilder.list_flows(Repo)

      # Most recent first
      assert hd(workflows)["workflow_slug"] == "third"
      assert List.last(workflows)["workflow_slug"] == "first"
    end

    test "includes workflow metadata" do
      {:ok, _} = FlowBuilder.create_flow("test", Repo, max_attempts: 5, timeout: 120)

      {:ok, [workflow]} = FlowBuilder.list_flows(Repo)

      assert workflow["workflow_slug"] == "test"
      assert workflow["max_attempts"] == 5
      assert workflow["timeout"] == 120
      assert Map.has_key?(workflow, "created_at")
    end
  end

  describe "get_flow/2" do
    test "returns workflow with steps" do
      {:ok, _} = FlowBuilder.create_flow("test_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("test_workflow", "fetch", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_workflow", "process", ["fetch"], Repo)

      {:ok, workflow} = FlowBuilder.get_flow("test_workflow", Repo)

      assert workflow["workflow_slug"] == "test_workflow"
      assert length(workflow["steps"]) == 2
    end

    test "includes step dependencies" do
      {:ok, _} = FlowBuilder.create_flow("test_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("test_workflow", "fetch", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_workflow", "process", ["fetch"], Repo)

      {:ok, workflow} = FlowBuilder.get_flow("test_workflow", Repo)

      fetch_step = Enum.find(workflow["steps"], &(&1["step_slug"] == "fetch"))
      process_step = Enum.find(workflow["steps"], &(&1["step_slug"] == "process"))

      assert fetch_step["depends_on"] == []
      assert process_step["depends_on"] == ["fetch"]
    end

    test "includes multiple dependencies" do
      {:ok, _} = FlowBuilder.create_flow("test_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("test_workflow", "step_a", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_workflow", "step_b", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_workflow", "merge", ["step_a", "step_b"], Repo)

      {:ok, workflow} = FlowBuilder.get_flow("test_workflow", Repo)

      merge_step = Enum.find(workflow["steps"], &(&1["step_slug"] == "merge"))
      assert Enum.sort(merge_step["depends_on"]) == ["step_a", "step_b"]
    end

    test "returns error for non-existent workflow" do
      result = FlowBuilder.get_flow("nonexistent", Repo)

      assert {:error, :not_found} = result
    end

    test "returns workflow with no steps" do
      {:ok, _} = FlowBuilder.create_flow("empty_workflow", Repo)

      {:ok, workflow} = FlowBuilder.get_flow("empty_workflow", Repo)

      assert workflow["workflow_slug"] == "empty_workflow"
      assert workflow["steps"] == []
    end

    test "includes step metadata" do
      {:ok, _} = FlowBuilder.create_flow("test_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("test_workflow", "map_step", [], Repo,
        step_type: "map",
        initial_tasks: 10,
        max_attempts: 5,
        timeout: 300
      )

      {:ok, workflow} = FlowBuilder.get_flow("test_workflow", Repo)

      step = hd(workflow["steps"])
      assert step["step_type"] == "map"
      assert step["initial_tasks"] == 10
      assert step["max_attempts"] == 5
      assert step["timeout"] == 300
    end
  end

  describe "delete_flow/2" do
    test "deletes workflow and all its steps" do
      {:ok, _} = FlowBuilder.create_flow("test_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("test_workflow", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_workflow", "step2", ["step1"], Repo)

      :ok = FlowBuilder.delete_flow("test_workflow", Repo)

      # Workflow should be gone
      assert {:error, :not_found} = FlowBuilder.get_flow("test_workflow", Repo)

      # Steps should be gone (cascade delete)
      {:ok, result} = Repo.query(
        "SELECT COUNT(*) FROM workflow_steps WHERE workflow_slug = $1",
        ["test_workflow"]
      )
      assert result.rows == [[0]]
    end

    test "deletes workflow with no steps" do
      {:ok, _} = FlowBuilder.create_flow("empty_workflow", Repo)

      :ok = FlowBuilder.delete_flow("empty_workflow", Repo)

      assert {:error, :not_found} = FlowBuilder.get_flow("empty_workflow", Repo)
    end

    test "returns ok even if workflow doesn't exist" do
      result = FlowBuilder.delete_flow("nonexistent", Repo)

      assert :ok = result
    end

    test "deletes specific workflow without affecting others" do
      {:ok, _} = FlowBuilder.create_flow("workflow_1", Repo)
      {:ok, _} = FlowBuilder.create_flow("workflow_2", Repo)
      {:ok, _} = FlowBuilder.create_flow("workflow_3", Repo)

      :ok = FlowBuilder.delete_flow("workflow_2", Repo)

      {:ok, workflows} = FlowBuilder.list_flows(Repo)
      slugs = Enum.map(workflows, & &1["workflow_slug"]) |> Enum.sort()
      assert slugs == ["workflow_1", "workflow_3"]
    end
  end

  describe "Integration scenarios" do
    test "build complete ETL workflow" do
      # Create workflow
      {:ok, _} = FlowBuilder.create_flow("etl_pipeline", Repo,
        max_attempts: 5,
        timeout: 300
      )

      # Add steps
      {:ok, _} = FlowBuilder.add_step("etl_pipeline", "extract", [], Repo)
      {:ok, _} = FlowBuilder.add_step("etl_pipeline", "validate", ["extract"], Repo)
      {:ok, _} = FlowBuilder.add_step("etl_pipeline", "transform", ["validate"], Repo,
        step_type: "map",
        initial_tasks: 100
      )
      {:ok, _} = FlowBuilder.add_step("etl_pipeline", "load", ["transform"], Repo)

      # Verify structure
      {:ok, workflow} = FlowBuilder.get_flow("etl_pipeline", Repo)

      assert length(workflow["steps"]) == 4
      assert workflow["max_attempts"] == 5

      # Verify dependencies
      transform_step = Enum.find(workflow["steps"], &(&1["step_slug"] == "transform"))
      assert transform_step["depends_on"] == ["validate"]
      assert transform_step["step_type"] == "map"
    end

    test "build parallel processing workflow" do
      {:ok, _} = FlowBuilder.create_flow("parallel_workflow", Repo)

      # Root step
      {:ok, _} = FlowBuilder.add_step("parallel_workflow", "fetch", [], Repo)

      # Parallel branches
      {:ok, _} = FlowBuilder.add_step("parallel_workflow", "branch_a", ["fetch"], Repo)
      {:ok, _} = FlowBuilder.add_step("parallel_workflow", "branch_b", ["fetch"], Repo)
      {:ok, _} = FlowBuilder.add_step("parallel_workflow", "branch_c", ["fetch"], Repo)

      # Merge step
      {:ok, _} = FlowBuilder.add_step("parallel_workflow", "merge",
        ["branch_a", "branch_b", "branch_c"], Repo)

      {:ok, workflow} = FlowBuilder.get_flow("parallel_workflow", Repo)

      merge_step = Enum.find(workflow["steps"], &(&1["step_slug"] == "merge"))
      assert merge_step["deps_count"] == 3
    end

    test "workflow lifecycle: create, update, delete" do
      # Create
      {:ok, _} = FlowBuilder.create_flow("lifecycle_test", Repo)

      # Add steps
      {:ok, _} = FlowBuilder.add_step("lifecycle_test", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("lifecycle_test", "step2", ["step1"], Repo)

      # Verify exists
      {:ok, workflow} = FlowBuilder.get_flow("lifecycle_test", Repo)
      assert length(workflow["steps"]) == 2

      # Delete
      :ok = FlowBuilder.delete_flow("lifecycle_test", Repo)

      # Verify gone
      assert {:error, :not_found} = FlowBuilder.get_flow("lifecycle_test", Repo)
    end
  end
end
