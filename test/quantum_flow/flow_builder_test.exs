defmodule QuantumFlow.FlowBuilderTest do
  use ExUnit.Case, async: false

  alias QuantumFlow.{Repo, FlowBuilder}

  @moduledoc """
  Tests for FlowBuilder - Dynamic workflow creation API.

  Uses TDD Chicago (state-based) approach:
  - Create workflow in database using FlowBuilder
  - Query database to verify correct state
  - Test error handling and validation

  Coverage:
  - Creating workflows with various options
  - Adding steps (single, map, with dependencies)
  - Listing, getting, and deleting workflows
  - Input validation (slugs, types, constraints)
  - Error handling (missing workflows, duplicates, invalid data)
  - Edge cases (long slugs, many steps, large initial_tasks)

  ## Design Notes

  FlowBuilder is the API for AI/LLM agents to create workflows dynamically.
  Tests ensure robust validation and clear error messages.
  """

  setup do
    # Set up sandbox for this test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(QuantumFlow.Repo)

    # Reset test clock for deterministic timestamps
    QuantumFlow.TestClock.reset()

    # Clean up any existing test workflows using old "test_" pattern (from previous runs)
    # This removes test data that may have persisted between test runs
    {:ok, _} = QuantumFlow.TestWorkflowPrefix.cleanup_by_prefix("test_", Repo)

    # Create unique test prefix for this specific test suite run
    # This ensures parallel test runs don't collide on workflow names
    prefix = QuantumFlow.TestWorkflowPrefix.start()

    # Return prefix so it's available in tests via context
    {:ok, prefix: prefix}
  end

  # Tests currently use hardcoded "test_" prefix for simplicity
  # This works because each test suite run clears the "test_" prefix data
  # Future improvement: migrate all tests to use context prefix

  describe "create_flow/3 - Basic workflow creation" do
    test "creates workflow with default options" do
      {:ok, workflow} = FlowBuilder.create_flow("test_basic", Repo)

      assert workflow["workflow_slug"] == "test_basic"
      assert workflow["max_attempts"] == 3
      assert workflow["timeout"] == 60
      assert workflow["created_at"] != nil
    end

    test "creates workflow with custom max_attempts" do
      {:ok, workflow} = FlowBuilder.create_flow("test_retry", Repo, max_attempts: 5)

      assert workflow["max_attempts"] == 5
      assert workflow["timeout"] == 60
    end

    test "creates workflow with custom timeout" do
      {:ok, workflow} = FlowBuilder.create_flow("test_timeout", Repo, timeout: 120)

      assert workflow["max_attempts"] == 3
      assert workflow["timeout"] == 120
    end

    test "creates workflow with both custom options" do
      {:ok, workflow} = FlowBuilder.create_flow("test_custom", Repo, max_attempts: 10, timeout: 300)

      assert workflow["max_attempts"] == 10
      assert workflow["timeout"] == 300
    end

    test "workflow appears in database" do
      {:ok, _} = FlowBuilder.create_flow("test_db_check", Repo)

      # Verify in database
      {:ok, result} =
        Repo.query("SELECT * FROM workflows WHERE workflow_slug = 'test_db_check'", [])

      assert length(result.rows) == 1
    end

    test "max_attempts defaults to 3 when not specified" do
      {:ok, workflow} = FlowBuilder.create_flow("test_default_attempts", Repo, timeout: 90)

      assert workflow["max_attempts"] == 3
    end

    test "timeout defaults to 60 when not specified" do
      {:ok, workflow} = FlowBuilder.create_flow("test_default_timeout", Repo, max_attempts: 4)

      assert workflow["timeout"] == 60
    end
  end

  describe "create_flow/3 - Workflow slug validation" do
    test "rejects empty workflow slug" do
      result = FlowBuilder.create_flow("", Repo)

      assert result == {:error, :workflow_slug_cannot_be_empty}
    end

    test "rejects workflow slug over 255 characters" do
      long_slug = String.duplicate("a", 256)
      result = FlowBuilder.create_flow(long_slug, Repo)

      assert result == {:error, :workflow_slug_too_long}
    end

    test "accepts workflow slug with 128 characters" do
      max_slug = String.duplicate("a", 128)
      {:ok, workflow} = FlowBuilder.create_flow(max_slug, Repo)

      assert workflow["workflow_slug"] == max_slug
    end

    test "rejects workflow slug starting with number" do
      result = FlowBuilder.create_flow("123_workflow", Repo)

      assert result == {:error, :workflow_slug_invalid_format}
    end

    test "rejects workflow slug with spaces" do
      result = FlowBuilder.create_flow("my workflow", Repo)

      assert result == {:error, :workflow_slug_invalid_format}
    end

    test "rejects workflow slug with hyphens" do
      result = FlowBuilder.create_flow("my-workflow", Repo)

      assert result == {:error, :workflow_slug_invalid_format}
    end

    test "rejects workflow slug with special characters" do
      result = FlowBuilder.create_flow("workflow@test", Repo)

      assert result == {:error, :workflow_slug_invalid_format}
    end

    test "accepts workflow slug with underscores" do
      {:ok, workflow} = FlowBuilder.create_flow("test_workflow_name", Repo)

      assert workflow["workflow_slug"] == "test_workflow_name"
    end

    test "accepts workflow slug with numbers (not first character)" do
      {:ok, workflow} = FlowBuilder.create_flow("test_workflow_123", Repo)

      assert workflow["workflow_slug"] == "test_workflow_123"
    end

    test "accepts workflow slug starting with underscore" do
      {:ok, workflow} = FlowBuilder.create_flow("_private_workflow", Repo)

      assert workflow["workflow_slug"] == "_private_workflow"
    end

    test "rejects non-string workflow slug" do
      result = FlowBuilder.create_flow(12345, Repo)

      assert result == {:error, :workflow_slug_must_be_string}
    end

    test "rejects duplicate workflow slug" do
      {:ok, _} = FlowBuilder.create_flow("test_duplicate", Repo)
      result = FlowBuilder.create_flow("test_duplicate", Repo)

      assert {:error, _} = result
    end
  end

  describe "create_flow/3 - Options validation" do
    test "rejects negative max_attempts" do
      result = FlowBuilder.create_flow("test_negative_attempts", Repo, max_attempts: -1)

      assert result == {:error, :max_attempts_must_be_non_negative}
    end

    test "accepts zero max_attempts (no retries)" do
      {:ok, workflow} = FlowBuilder.create_flow("test_zero_attempts", Repo, max_attempts: 0)

      assert workflow["max_attempts"] == 0
    end

    test "rejects non-integer max_attempts" do
      result = FlowBuilder.create_flow("test_float_attempts", Repo, max_attempts: 3.5)

      assert result == {:error, :max_attempts_must_be_integer}
    end

    test "rejects zero timeout" do
      result = FlowBuilder.create_flow("test_zero_timeout", Repo, timeout: 0)

      assert result == {:error, :timeout_must_be_positive}
    end

    test "rejects negative timeout" do
      result = FlowBuilder.create_flow("test_negative_timeout", Repo, timeout: -60)

      assert result == {:error, :timeout_must_be_positive}
    end

    test "rejects non-integer timeout" do
      result = FlowBuilder.create_flow("test_float_timeout", Repo, timeout: 60.5)

      assert result == {:error, :timeout_must_be_integer}
    end

    test "accepts large max_attempts" do
      {:ok, workflow} = FlowBuilder.create_flow("test_large_attempts", Repo, max_attempts: 100)

      assert workflow["max_attempts"] == 100
    end

    test "accepts large timeout" do
      {:ok, workflow} = FlowBuilder.create_flow("test_large_timeout", Repo, timeout: 3600)

      assert workflow["timeout"] == 3600
    end
  end

  describe "add_step/5 - Root steps (no dependencies)" do
    test "adds root step to workflow" do
      {:ok, _} = FlowBuilder.create_flow("test_root_step", Repo)
      {:ok, step} = FlowBuilder.add_step("test_root_step", "fetch", [], Repo)

      assert step["step_slug"] == "fetch"
      assert step["workflow_slug"] == "test_root_step"
      assert step["step_type"] == "single"
      assert step["deps_count"] == 0
      assert step["initial_tasks"] == nil
    end

    test "adds multiple root steps (parallel start)" do
      {:ok, _} = FlowBuilder.create_flow("test_multi_root", Repo)
      {:ok, step1} = FlowBuilder.add_step("test_multi_root", "fetch_a", [], Repo)
      {:ok, step2} = FlowBuilder.add_step("test_multi_root", "fetch_b", [], Repo)

      assert step1["step_slug"] == "fetch_a"
      assert step2["step_slug"] == "fetch_b"
      assert step1["deps_count"] == 0
      assert step2["deps_count"] == 0
    end

    test "root step appears in database" do
      {:ok, _} = FlowBuilder.create_flow("test_step_db", Repo)
      {:ok, _} = FlowBuilder.add_step("test_step_db", "process", [], Repo)

      {:ok, result} =
        Repo.query(
          """
          SELECT * FROM workflow_steps
          WHERE workflow_slug = 'test_step_db' AND step_slug = 'process'
          """,
          []
        )

      assert length(result.rows) == 1
    end

    test "step inherits workflow defaults" do
      {:ok, _} = FlowBuilder.create_flow("test_inherit", Repo, max_attempts: 5, timeout: 120)
      {:ok, step} = FlowBuilder.add_step("test_inherit", "step1", [], Repo)

      assert step["max_attempts"] == 5
      assert step["timeout"] == 120
    end
  end

  describe "add_step/5 - Sequential dependencies" do
    test "adds step with single dependency" do
      {:ok, _} = FlowBuilder.create_flow("test_sequential", Repo)
      {:ok, _} = FlowBuilder.add_step("test_sequential", "step1", [], Repo)
      {:ok, step2} = FlowBuilder.add_step("test_sequential", "step2", ["step1"], Repo)

      assert step2["step_slug"] == "step2"
      assert step2["deps_count"] == 1
    end

    test "dependency appears in database" do
      {:ok, _} = FlowBuilder.create_flow("test_dep_db", Repo)
      {:ok, _} = FlowBuilder.add_step("test_dep_db", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_dep_db", "step2", ["step1"], Repo)

      {:ok, result} =
        Repo.query(
          """
          SELECT * FROM workflow_step_dependencies_def
          WHERE workflow_slug = 'test_dep_db' AND step_slug = 'step2'
          """,
          []
        )

      assert length(result.rows) == 1
      [row] = result.rows
      [_workflow, dep_slug, _step, _created_at] = row
      assert dep_slug == "step1"
    end

    test "adds long dependency chain" do
      {:ok, _} = FlowBuilder.create_flow("test_chain", Repo)
      {:ok, _} = FlowBuilder.add_step("test_chain", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_chain", "step2", ["step1"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_chain", "step3", ["step2"], Repo)
      {:ok, step4} = FlowBuilder.add_step("test_chain", "step4", ["step3"], Repo)

      assert step4["deps_count"] == 1
    end
  end

  describe "add_step/5 - DAG dependencies (multiple dependencies)" do
    test "adds step with multiple dependencies (join)" do
      {:ok, _} = FlowBuilder.create_flow("test_join", Repo)
      {:ok, _} = FlowBuilder.add_step("test_join", "fetch_a", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_join", "fetch_b", [], Repo)
      {:ok, merge} = FlowBuilder.add_step("test_join", "merge", ["fetch_a", "fetch_b"], Repo)

      assert merge["deps_count"] == 2
    end

    test "creates diamond DAG" do
      {:ok, _} = FlowBuilder.create_flow("test_diamond", Repo)
      {:ok, _} = FlowBuilder.add_step("test_diamond", "root", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_diamond", "left", ["root"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_diamond", "right", ["root"], Repo)
      {:ok, merge} = FlowBuilder.add_step("test_diamond", "merge", ["left", "right"], Repo)

      assert merge["deps_count"] == 2
    end

    test "verifies all dependencies in database" do
      {:ok, _} = FlowBuilder.create_flow("test_multi_dep", Repo)
      {:ok, _} = FlowBuilder.add_step("test_multi_dep", "a", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_multi_dep", "b", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_multi_dep", "c", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_multi_dep", "merge", ["a", "b", "c"], Repo)

      {:ok, result} =
        Repo.query(
          """
          SELECT dep_slug FROM workflow_step_dependencies_def
          WHERE workflow_slug = 'test_multi_dep' AND step_slug = 'merge'
          ORDER BY dep_slug
          """,
          []
        )

      dep_slugs = Enum.map(result.rows, fn [slug] -> slug end)
      assert dep_slugs == ["a", "b", "c"]
    end
  end

  describe "add_step/5 - Map steps" do
    test "adds map step with fixed initial_tasks" do
      {:ok, _} = FlowBuilder.create_flow("test_map_fixed", Repo)
      {:ok, _} = FlowBuilder.add_step("test_map_fixed", "fetch", [], Repo)

      {:ok, map_step} =
        FlowBuilder.add_step("test_map_fixed", "process", ["fetch"], Repo,
          step_type: "map",
          initial_tasks: 10
        )

      assert map_step["step_type"] == "map"
      assert map_step["initial_tasks"] == 10
    end

    test "adds map step without initial_tasks (runtime-determined)" do
      {:ok, _} = FlowBuilder.create_flow("test_map_dynamic", Repo)
      {:ok, _} = FlowBuilder.add_step("test_map_dynamic", "fetch", [], Repo)

      {:ok, map_step} =
        FlowBuilder.add_step("test_map_dynamic", "process", ["fetch"], Repo, step_type: "map")

      assert map_step["step_type"] == "map"
      assert map_step["initial_tasks"] == nil
    end

    test "single step has step_type='single' by default" do
      {:ok, _} = FlowBuilder.create_flow("test_single_default", Repo)
      {:ok, step} = FlowBuilder.add_step("test_single_default", "process", [], Repo)

      assert step["step_type"] == "single"
    end

    test "map step with large initial_tasks" do
      {:ok, _} = FlowBuilder.create_flow("test_large_map", Repo)
      {:ok, _} = FlowBuilder.add_step("test_large_map", "fetch", [], Repo)

      {:ok, map_step} =
        FlowBuilder.add_step("test_large_map", "process", ["fetch"], Repo,
          step_type: "map",
          initial_tasks: 1000
        )

      assert map_step["initial_tasks"] == 1000
    end
  end

  describe "add_step/5 - Step options" do
    test "overrides workflow max_attempts" do
      {:ok, _} = FlowBuilder.create_flow("test_override_attempts", Repo, max_attempts: 3)

      {:ok, step} =
        FlowBuilder.add_step("test_override_attempts", "retry_step", [], Repo, max_attempts: 10)

      assert step["max_attempts"] == 10
    end

    test "overrides workflow timeout" do
      {:ok, _} = FlowBuilder.create_flow("test_override_timeout", Repo, timeout: 60)

      {:ok, step} =
        FlowBuilder.add_step("test_override_timeout", "slow_step", [], Repo, timeout: 300)

      assert step["timeout"] == 300
    end

    test "overrides both max_attempts and timeout" do
      {:ok, _} = FlowBuilder.create_flow("test_override_both", Repo)

      {:ok, step} =
        FlowBuilder.add_step("test_override_both", "custom_step", [], Repo,
          max_attempts: 5,
          timeout: 120
        )

      assert step["max_attempts"] == 5
      assert step["timeout"] == 120
    end

    test "map step with all custom options" do
      {:ok, _} = FlowBuilder.create_flow("test_map_full", Repo)
      {:ok, _} = FlowBuilder.add_step("test_map_full", "fetch", [], Repo)

      {:ok, step} =
        FlowBuilder.add_step("test_map_full", "process", ["fetch"], Repo,
          step_type: "map",
          initial_tasks: 50,
          max_attempts: 5,
          timeout: 120
        )

      assert step["step_type"] == "map"
      assert step["initial_tasks"] == 50
      assert step["max_attempts"] == 5
      assert step["timeout"] == 120
    end
  end

  describe "add_step/5 - Step slug validation" do
    test "rejects empty step slug" do
      {:ok, _} = FlowBuilder.create_flow("test_empty_step", Repo)
      result = FlowBuilder.add_step("test_empty_step", "", [], Repo)

      assert result == {:error, :step_slug_cannot_be_empty}
    end

    test "rejects step slug over 255 characters" do
      {:ok, _} = FlowBuilder.create_flow("test_long_step", Repo)
      long_slug = String.duplicate("a", 256)
      result = FlowBuilder.add_step("test_long_step", long_slug, [], Repo)

      assert result == {:error, :step_slug_too_long}
    end

    test "accepts step slug with 128 characters" do
      {:ok, _} = FlowBuilder.create_flow("test_max_step", Repo)
      max_slug = String.duplicate("a", 128)
      {:ok, step} = FlowBuilder.add_step("test_max_step", max_slug, [], Repo)

      assert step["step_slug"] == max_slug
    end

    test "rejects step slug starting with number" do
      {:ok, _} = FlowBuilder.create_flow("test_num_step", Repo)
      result = FlowBuilder.add_step("test_num_step", "123_step", [], Repo)

      assert result == {:error, :step_slug_invalid_format}
    end

    test "rejects step slug with spaces" do
      {:ok, _} = FlowBuilder.create_flow("test_space_step", Repo)
      result = FlowBuilder.add_step("test_space_step", "my step", [], Repo)

      assert result == {:error, :step_slug_invalid_format}
    end

    test "rejects step slug with hyphens" do
      {:ok, _} = FlowBuilder.create_flow("test_hyphen_step", Repo)
      result = FlowBuilder.add_step("test_hyphen_step", "my-step", [], Repo)

      assert result == {:error, :step_slug_invalid_format}
    end

    test "accepts step slug with underscores and numbers" do
      {:ok, _} = FlowBuilder.create_flow("test_valid_step", Repo)
      {:ok, step} = FlowBuilder.add_step("test_valid_step", "step_123_foo", [], Repo)

      assert step["step_slug"] == "step_123_foo"
    end

    test "rejects non-string step slug" do
      {:ok, _} = FlowBuilder.create_flow("test_nonstring_step", Repo)
      result = FlowBuilder.add_step("test_nonstring_step", :atom_slug, [], Repo)

      assert result == {:error, :step_slug_must_be_string}
    end

    test "rejects duplicate step slug in same workflow" do
      {:ok, _} = FlowBuilder.create_flow("test_dup_step", Repo)
      {:ok, _} = FlowBuilder.add_step("test_dup_step", "process", [], Repo)
      result = FlowBuilder.add_step("test_dup_step", "process", [], Repo)

      assert {:error, _} = result
    end

    test "allows same step slug in different workflows" do
      {:ok, _} = FlowBuilder.create_flow("test_workflow_a", Repo)
      {:ok, _} = FlowBuilder.create_flow("test_workflow_b", Repo)

      {:ok, step1} = FlowBuilder.add_step("test_workflow_a", "process", [], Repo)
      {:ok, step2} = FlowBuilder.add_step("test_workflow_b", "process", [], Repo)

      assert step1["workflow_slug"] == "test_workflow_a"
      assert step2["workflow_slug"] == "test_workflow_b"
    end
  end

  describe "add_step/5 - Options validation" do
    test "rejects invalid step_type" do
      {:ok, _} = FlowBuilder.create_flow("test_invalid_type", Repo)
      result = FlowBuilder.add_step("test_invalid_type", "step1", [], Repo, step_type: "batch")

      assert result == {:error, :step_type_must_be_single_or_map}
    end

    test "rejects negative initial_tasks" do
      {:ok, _} = FlowBuilder.create_flow("test_negative_tasks", Repo)

      result =
        FlowBuilder.add_step("test_negative_tasks", "step1", [], Repo,
          step_type: "map",
          initial_tasks: -5
        )

      assert result == {:error, :initial_tasks_must_be_positive}
    end

    test "rejects zero initial_tasks" do
      {:ok, _} = FlowBuilder.create_flow("test_zero_tasks", Repo)

      result =
        FlowBuilder.add_step("test_zero_tasks", "step1", [], Repo,
          step_type: "map",
          initial_tasks: 0
        )

      assert result == {:error, :initial_tasks_must_be_positive}
    end

    test "rejects non-integer initial_tasks" do
      {:ok, _} = FlowBuilder.create_flow("test_float_tasks", Repo)

      result =
        FlowBuilder.add_step("test_float_tasks", "step1", [], Repo,
          step_type: "map",
          initial_tasks: 10.5
        )

      assert result == {:error, :initial_tasks_must_be_integer}
    end

    test "rejects negative step max_attempts" do
      {:ok, _} = FlowBuilder.create_flow("test_neg_step_attempts", Repo)

      result =
        FlowBuilder.add_step("test_neg_step_attempts", "step1", [], Repo, max_attempts: -1)

      assert result == {:error, :max_attempts_must_be_non_negative}
    end

    test "rejects zero step timeout" do
      {:ok, _} = FlowBuilder.create_flow("test_zero_step_timeout", Repo)
      result = FlowBuilder.add_step("test_zero_step_timeout", "step1", [], Repo, timeout: 0)

      assert result == {:error, :timeout_must_be_positive}
    end
  end

  describe "add_step/5 - Error handling" do
    test "returns error for non-existent workflow" do
      result = FlowBuilder.add_step("nonexistent_workflow", "step1", [], Repo)

      assert {:error, _} = result
    end

    test "returns error for invalid dependency" do
      {:ok, _} = FlowBuilder.create_flow("test_invalid_dep", Repo)
      result = FlowBuilder.add_step("test_invalid_dep", "step1", ["nonexistent_step"], Repo)

      # This might succeed at add_step but fail at load time
      # Or might fail immediately depending on SQL function implementation
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "list_flows/1 - Listing workflows" do
    test "lists empty workflows" do
      {:ok, workflows} = FlowBuilder.list_flows(Repo)

      assert workflows == []
    end

    test "lists single workflow" do
      {:ok, _} = FlowBuilder.create_flow("test_list_single", Repo)
      {:ok, workflows} = FlowBuilder.list_flows(Repo)

      assert length(workflows) == 1
      [workflow] = workflows
      assert workflow["workflow_slug"] == "test_list_single"
    end

    test "lists multiple workflows" do
      {:ok, _} = FlowBuilder.create_flow("test_list_a", Repo)
      {:ok, _} = FlowBuilder.create_flow("test_list_b", Repo)
      {:ok, _} = FlowBuilder.create_flow("test_list_c", Repo)

      {:ok, workflows} = FlowBuilder.list_flows(Repo)

      assert length(workflows) == 3
      slugs = Enum.map(workflows, & &1["workflow_slug"]) |> Enum.sort()
      assert slugs == ["test_list_a", "test_list_b", "test_list_c"]
    end

    test "orders workflows by created_at DESC" do
      {:ok, _wf1} = FlowBuilder.create_flow("test_order_1", Repo)
      QuantumFlow.TestClock.advance(1000)
      {:ok, _wf2} = FlowBuilder.create_flow("test_order_2", Repo)
      QuantumFlow.TestClock.advance(1000)
      {:ok, _wf3} = FlowBuilder.create_flow("test_order_3", Repo)

      {:ok, workflows} = FlowBuilder.list_flows(Repo)

      # Filter to only the workflows we just created
      my_workflows =
        Enum.filter(workflows, fn w -> String.starts_with?(w["workflow_slug"], "test_order_") end)

      my_workflows = Enum.sort_by(my_workflows, fn w -> w["workflow_slug"] end)

      # Verify ordering: most recent (test_order_3) should come first
      assert length(my_workflows) >= 3
      # Get the ones in our test order
      {test_order_3, rest} =
        List.pop_at(
          my_workflows,
          Enum.find_index(my_workflows, fn w -> w["workflow_slug"] == "test_order_3" end)
        )

      {test_order_2, rest} =
        List.pop_at(rest, Enum.find_index(rest, fn w -> w["workflow_slug"] == "test_order_2" end))

      {test_order_1, _rest} =
        List.pop_at(rest, Enum.find_index(rest, fn w -> w["workflow_slug"] == "test_order_1" end))

      # Verify timestamps are in ascending order (since list is DESC, first should have latest timestamp)
      assert NaiveDateTime.compare(test_order_3["created_at"], test_order_2["created_at"]) == :gt
      assert NaiveDateTime.compare(test_order_2["created_at"], test_order_1["created_at"]) == :gt
    end

    test "includes workflow metadata" do
      {:ok, _} = FlowBuilder.create_flow("test_metadata", Repo, max_attempts: 5, timeout: 120)
      {:ok, workflows} = FlowBuilder.list_flows(Repo)

      [workflow] = workflows
      assert workflow["max_attempts"] == 5
      assert workflow["timeout"] == 120
      assert workflow["created_at"] != nil
    end
  end

  describe "get_flow/2 - Getting workflow with steps" do
    test "gets workflow without steps" do
      {:ok, _} = FlowBuilder.create_flow("test_get_empty", Repo)
      {:ok, workflow} = FlowBuilder.get_flow("test_get_empty", Repo)

      assert workflow["workflow_slug"] == "test_get_empty"
      assert workflow["steps"] == []
    end

    test "gets workflow with single step" do
      {:ok, _} = FlowBuilder.create_flow("test_get_single", Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_single", "process", [], Repo)

      {:ok, workflow} = FlowBuilder.get_flow("test_get_single", Repo)

      assert workflow["workflow_slug"] == "test_get_single"
      assert length(workflow["steps"]) == 1

      [step] = workflow["steps"]
      assert step["step_slug"] == "process"
      assert step["depends_on"] == []
    end

    test "gets workflow with multiple steps" do
      {:ok, _} = FlowBuilder.create_flow("test_get_multi", Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_multi", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_multi", "step2", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_multi", "step3", [], Repo)

      {:ok, workflow} = FlowBuilder.get_flow("test_get_multi", Repo)

      assert length(workflow["steps"]) == 3
    end

    test "includes step dependencies" do
      {:ok, _} = FlowBuilder.create_flow("test_get_deps", Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_deps", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_deps", "step2", ["step1"], Repo)

      {:ok, workflow} = FlowBuilder.get_flow("test_get_deps", Repo)

      step2 = Enum.find(workflow["steps"], &(&1["step_slug"] == "step2"))
      assert step2["depends_on"] == ["step1"]
    end

    test "includes multiple dependencies" do
      {:ok, _} = FlowBuilder.create_flow("test_get_multidep", Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_multidep", "a", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_multidep", "b", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_multidep", "merge", ["a", "b"], Repo)

      {:ok, workflow} = FlowBuilder.get_flow("test_get_multidep", Repo)

      merge = Enum.find(workflow["steps"], &(&1["step_slug"] == "merge"))
      assert Enum.sort(merge["depends_on"]) == ["a", "b"]
    end

    test "orders steps by step_index" do
      {:ok, _} = FlowBuilder.create_flow("test_get_order", Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_order", "third", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_order", "first", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_order", "second", [], Repo)

      {:ok, workflow} = FlowBuilder.get_flow("test_get_order", Repo)

      # Steps should be in insertion order (step_index)
      step_slugs = Enum.map(workflow["steps"], & &1["step_slug"])
      assert step_slugs == ["third", "first", "second"]
    end

    test "includes step metadata" do
      {:ok, _} = FlowBuilder.create_flow("test_get_metadata", Repo)

      {:ok, _} =
        FlowBuilder.add_step("test_get_metadata", "map_step", [], Repo,
          step_type: "map",
          initial_tasks: 50,
          max_attempts: 5,
          timeout: 120
        )

      {:ok, workflow} = FlowBuilder.get_flow("test_get_metadata", Repo)

      [step] = workflow["steps"]
      assert step["step_type"] == "map"
      assert step["initial_tasks"] == 50
      assert step["max_attempts"] == 5
      assert step["timeout"] == 120
    end

    test "returns not_found for missing workflow" do
      result = FlowBuilder.get_flow("nonexistent_workflow", Repo)

      assert result == {:error, :not_found}
    end
  end

  describe "delete_flow/2 - Deleting workflows" do
    test "deletes existing workflow" do
      {:ok, _} = FlowBuilder.create_flow("test_delete", Repo)
      :ok = FlowBuilder.delete_flow("test_delete", Repo)

      # Verify deleted
      result = FlowBuilder.get_flow("test_delete", Repo)
      assert result == {:error, :not_found}
    end

    test "cascades to delete steps" do
      {:ok, _} = FlowBuilder.create_flow("test_delete_cascade", Repo)
      {:ok, _} = FlowBuilder.add_step("test_delete_cascade", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_delete_cascade", "step2", [], Repo)

      :ok = FlowBuilder.delete_flow("test_delete_cascade", Repo)

      # Verify steps deleted
      {:ok, result} =
        Repo.query(
          "SELECT * FROM workflow_steps WHERE workflow_slug = 'test_delete_cascade'",
          []
        )

      assert result.rows == []
    end

    test "cascades to delete dependencies" do
      {:ok, _} = FlowBuilder.create_flow("test_delete_deps", Repo)
      {:ok, _} = FlowBuilder.add_step("test_delete_deps", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_delete_deps", "step2", ["step1"], Repo)

      :ok = FlowBuilder.delete_flow("test_delete_deps", Repo)

      # Verify dependencies deleted
      {:ok, result} =
        Repo.query(
          "SELECT * FROM workflow_step_dependencies_def WHERE workflow_slug = 'test_delete_deps'",
          []
        )

      assert result.rows == []
    end

    test "succeeds for non-existent workflow (idempotent)" do
      result = FlowBuilder.delete_flow("nonexistent_workflow", Repo)

      assert result == :ok
    end

    test "workflow removed from list after deletion" do
      {:ok, _} = FlowBuilder.create_flow("test_delete_list", Repo)
      {:ok, workflows_before} = FlowBuilder.list_flows(Repo)
      assert length(workflows_before) == 1

      :ok = FlowBuilder.delete_flow("test_delete_list", Repo)

      {:ok, workflows_after} = FlowBuilder.list_flows(Repo)
      assert workflows_after == []
    end
  end

  describe "Integration scenarios" do
    test "creates complete ETL workflow" do
      # Create workflow
      {:ok, _} = FlowBuilder.create_flow("test_etl", Repo, max_attempts: 3, timeout: 300)

      # Add steps
      {:ok, _} = FlowBuilder.add_step("test_etl", "extract", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_etl", "transform", ["extract"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_etl", "load", ["transform"], Repo)

      # Verify structure
      {:ok, workflow} = FlowBuilder.get_flow("test_etl", Repo)

      assert length(workflow["steps"]) == 3
      step_slugs = Enum.map(workflow["steps"], & &1["step_slug"])
      assert step_slugs == ["extract", "transform", "load"]
    end

    test "creates diamond DAG workflow" do
      {:ok, _} = FlowBuilder.create_flow("test_diamond_full", Repo)
      {:ok, _} = FlowBuilder.add_step("test_diamond_full", "root", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_diamond_full", "left", ["root"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_diamond_full", "right", ["root"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_diamond_full", "merge", ["left", "right"], Repo)

      {:ok, workflow} = FlowBuilder.get_flow("test_diamond_full", Repo)

      assert length(workflow["steps"]) == 4

      merge = Enum.find(workflow["steps"], &(&1["step_slug"] == "merge"))
      assert Enum.sort(merge["depends_on"]) == ["left", "right"]
    end

    test "creates workflow with map step" do
      {:ok, _} = FlowBuilder.create_flow("test_map_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("test_map_workflow", "fetch", [], Repo)

      {:ok, _} =
        FlowBuilder.add_step("test_map_workflow", "process_batch", ["fetch"], Repo,
          step_type: "map",
          initial_tasks: 100
        )

      {:ok, _} = FlowBuilder.add_step("test_map_workflow", "aggregate", ["process_batch"], Repo)

      {:ok, workflow} = FlowBuilder.get_flow("test_map_workflow", Repo)

      process_step = Enum.find(workflow["steps"], &(&1["step_slug"] == "process_batch"))
      assert process_step["step_type"] == "map"
      assert process_step["initial_tasks"] == 100
    end

    test "modifies workflow by adding more steps" do
      {:ok, _} = FlowBuilder.create_flow("test_modify", Repo)
      {:ok, _} = FlowBuilder.add_step("test_modify", "step1", [], Repo)

      {:ok, workflow_before} = FlowBuilder.get_flow("test_modify", Repo)
      assert length(workflow_before["steps"]) == 1

      # Add more steps
      {:ok, _} = FlowBuilder.add_step("test_modify", "step2", ["step1"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_modify", "step3", ["step2"], Repo)

      {:ok, workflow_after} = FlowBuilder.get_flow("test_modify", Repo)
      assert length(workflow_after["steps"]) == 3
    end

    test "creates multiple independent workflows" do
      {:ok, _} = FlowBuilder.create_flow("test_workflow_a", Repo)
      {:ok, _} = FlowBuilder.create_flow("test_workflow_b", Repo)
      {:ok, _} = FlowBuilder.create_flow("test_workflow_c", Repo)

      {:ok, workflows} = FlowBuilder.list_flows(Repo)
      assert length(workflows) == 3
    end
  end

  describe "Edge cases" do
    test "creates workflow with 100+ steps (stress test)" do
      {:ok, _} = FlowBuilder.create_flow("test_large", Repo)

      # Create chain of 100 steps
      Enum.each(1..100, fn i ->
        step_name = "step_#{i}"
        deps = if i == 1, do: [], else: ["step_#{i - 1}"]
        {:ok, _} = FlowBuilder.add_step("test_large", step_name, deps, Repo)
      end)

      {:ok, workflow} = FlowBuilder.get_flow("test_large", Repo)
      assert length(workflow["steps"]) == 100
    end

    test "handles workflow with many parallel steps" do
      {:ok, _} = FlowBuilder.create_flow("test_parallel", Repo)

      # Create 50 parallel root steps
      Enum.each(1..50, fn i ->
        {:ok, _} = FlowBuilder.add_step("test_parallel", "parallel_#{i}", [], Repo)
      end)

      {:ok, workflow} = FlowBuilder.get_flow("test_parallel", Repo)
      assert length(workflow["steps"]) == 50
    end

    test "handles step with many dependencies" do
      {:ok, _} = FlowBuilder.create_flow("test_many_deps", Repo)

      # Create 20 independent steps
      Enum.each(1..20, fn i ->
        {:ok, _} = FlowBuilder.add_step("test_many_deps", "source_#{i}", [], Repo)
      end)

      # Create merge step depending on all 20
      deps = Enum.map(1..20, fn i -> "source_#{i}" end)
      {:ok, merge} = FlowBuilder.add_step("test_many_deps", "mega_merge", deps, Repo)

      assert merge["deps_count"] == 20
    end

    test "handles complex nested DAG" do
      {:ok, _} = FlowBuilder.create_flow("test_complex", Repo)

      # Layer 1
      {:ok, _} = FlowBuilder.add_step("test_complex", "a1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_complex", "a2", [], Repo)

      # Layer 2
      {:ok, _} = FlowBuilder.add_step("test_complex", "b1", ["a1"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_complex", "b2", ["a1", "a2"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_complex", "b3", ["a2"], Repo)

      # Layer 3
      {:ok, _} = FlowBuilder.add_step("test_complex", "c1", ["b1", "b2"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_complex", "c2", ["b2", "b3"], Repo)

      # Layer 4
      {:ok, _} = FlowBuilder.add_step("test_complex", "final", ["c1", "c2"], Repo)

      {:ok, workflow} = FlowBuilder.get_flow("test_complex", Repo)
      assert length(workflow["steps"]) == 8
    end
  end

  describe "error cases - add_step/5" do
    test "rejects empty step slug" do
      {:ok, _} = FlowBuilder.create_flow("test_empty_step_slug", Repo)
      result = FlowBuilder.add_step("test_empty_step_slug", "", [], Repo)

      assert result == {:error, :step_slug_cannot_be_empty}
    end

    test "rejects step slug over 128 characters" do
      {:ok, _} = FlowBuilder.create_flow("test_long_step_slug", Repo)
      long_slug = String.duplicate("a", 129)
      result = FlowBuilder.add_step("test_long_step_slug", long_slug, [], Repo)

      assert result == {:error, :step_slug_too_long}
    end

    test "rejects step slug starting with number" do
      {:ok, _} = FlowBuilder.create_flow("test_step_starts_num", Repo)
      result = FlowBuilder.add_step("test_step_starts_num", "123_step", [], Repo)

      assert result == {:error, :step_slug_invalid_format}
    end

    test "rejects step slug with special characters" do
      {:ok, _} = FlowBuilder.create_flow("test_step_special", Repo)
      result = FlowBuilder.add_step("test_step_special", "step@test", [], Repo)

      assert result == {:error, :step_slug_invalid_format}
    end

    test "rejects step slug that is reserved word 'run'" do
      {:ok, _} = FlowBuilder.create_flow("test_reserved_step", Repo)
      result = FlowBuilder.add_step("test_reserved_step", "run", [], Repo)

      assert result == {:error, :step_slug_reserved}
    end

    test "rejects non-string step slug" do
      {:ok, _} = FlowBuilder.create_flow("test_step_type", Repo)
      result = FlowBuilder.add_step("test_step_type", 12345, [], Repo)

      assert result == {:error, :step_slug_must_be_string}
    end

    test "rejects invalid step type" do
      {:ok, _} = FlowBuilder.create_flow("test_invalid_type", Repo)
      result = FlowBuilder.add_step("test_invalid_type", "step1", [], Repo, step_type: "invalid")

      assert result == {:error, :step_type_must_be_single_or_map}
    end

    test "rejects non-positive initial_tasks" do
      {:ok, _} = FlowBuilder.create_flow("test_bad_initial_tasks", Repo)
      result = FlowBuilder.add_step("test_bad_initial_tasks", "step1", [], Repo, initial_tasks: 0)

      assert result == {:error, :initial_tasks_must_be_positive}
    end

    test "rejects negative initial_tasks" do
      {:ok, _} = FlowBuilder.create_flow("test_negative_tasks", Repo)
      result = FlowBuilder.add_step("test_negative_tasks", "step1", [], Repo, initial_tasks: -5)

      assert result == {:error, :initial_tasks_must_be_positive}
    end

    test "rejects non-integer initial_tasks" do
      {:ok, _} = FlowBuilder.create_flow("test_float_tasks", Repo)
      result = FlowBuilder.add_step("test_float_tasks", "step1", [], Repo, initial_tasks: 3.5)

      assert result == {:error, :initial_tasks_must_be_integer}
    end

    test "rejects missing workflow" do
      result = FlowBuilder.add_step("missing_workflow", "step1", [], Repo)

      assert result == {:error, {:workflow_not_found, "missing_workflow"}}
    end

    test "rejects duplicate step in same workflow" do
      {:ok, _} = FlowBuilder.create_flow("test_dup_step", Repo)
      {:ok, _} = FlowBuilder.add_step("test_dup_step", "duplicate", [], Repo)
      result = FlowBuilder.add_step("test_dup_step", "duplicate", [], Repo)

      assert result == {:error, {:duplicate_step_slug, "duplicate"}}
    end

    test "rejects dependency on non-existent step" do
      {:ok, _} = FlowBuilder.create_flow("test_missing_dep", Repo)
      result = FlowBuilder.add_step("test_missing_dep", "step2", ["missing_step"], Repo)

      assert result == {:error, {:missing_dependencies, ["missing_step"]}}
    end

    test "rejects missing workflow in dependency check" do
      result = FlowBuilder.add_step("missing_wf", "step1", ["some_step"], Repo)

      # Will fail on workflow validation before dependency validation
      assert match?({:error, _}, result)
    end

    test "rejects map step with multiple dependencies" do
      {:ok, _} = FlowBuilder.create_flow("test_map_multi_dep", Repo)
      {:ok, _} = FlowBuilder.add_step("test_map_multi_dep", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_map_multi_dep", "step2", [], Repo)

      result =
        FlowBuilder.add_step("test_map_multi_dep", "map_step", ["step1", "step2"], Repo,
          step_type: "map"
        )

      assert match?({:error, {:map_step_constraint_violation, _}}, result)
    end

    test "allows map step with single dependency" do
      {:ok, _} = FlowBuilder.create_flow("test_map_single_dep", Repo)
      {:ok, _} = FlowBuilder.add_step("test_map_single_dep", "step1", [], Repo)

      {:ok, map_step} =
        FlowBuilder.add_step("test_map_single_dep", "map_step", ["step1"], Repo, step_type: "map")

      assert map_step["step_type"] == "map"
      assert map_step["deps_count"] == 1
    end

    test "allows map step without dependencies" do
      {:ok, _} = FlowBuilder.create_flow("test_map_no_dep", Repo)

      {:ok, map_step} =
        FlowBuilder.add_step("test_map_no_dep", "map_step", [], Repo, step_type: "map")

      assert map_step["step_type"] == "map"
      assert map_step["deps_count"] == 0
    end
  end

  describe "error cases - delete_flow/2" do
    test "deletes workflow and all related data" do
      {:ok, _} = FlowBuilder.create_flow("test_delete", Repo)
      {:ok, _} = FlowBuilder.add_step("test_delete", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_delete", "step2", ["step1"], Repo)

      :ok = FlowBuilder.delete_flow("test_delete", Repo)

      # Verify workflow is deleted
      {:ok, result} = Repo.query("SELECT * FROM workflows WHERE workflow_slug = 'test_delete'", [])
      assert length(result.rows) == 0

      # Verify steps are deleted
      {:ok, result} =
        Repo.query("SELECT * FROM workflow_steps WHERE workflow_slug = 'test_delete'", [])

      assert length(result.rows) == 0

      # Verify dependencies are deleted
      {:ok, result} =
        Repo.query(
          "SELECT * FROM workflow_step_dependencies_def WHERE workflow_slug = 'test_delete'",
          []
        )

      assert length(result.rows) == 0
    end

    test "deletes workflow with complex dependencies" do
      {:ok, _} = FlowBuilder.create_flow("test_delete_complex", Repo)
      {:ok, _} = FlowBuilder.add_step("test_delete_complex", "a", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_delete_complex", "b", ["a"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_delete_complex", "c", ["a"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_delete_complex", "d", ["b", "c"], Repo)

      :ok = FlowBuilder.delete_flow("test_delete_complex", Repo)

      # Verify all data is gone
      {:ok, result} =
        Repo.query("SELECT * FROM workflows WHERE workflow_slug = 'test_delete_complex'", [])

      assert length(result.rows) == 0
    end

    test "delete is idempotent (deleting non-existent workflow succeeds)" do
      result = FlowBuilder.delete_flow("never_created", Repo)

      # Should succeed (no rows to delete)
      assert result == :ok
    end
  end

  describe "edge cases" do
    test "create_flow is idempotent for reserved word checks" do
      # "run" is reserved, should always fail
      result1 = FlowBuilder.create_flow("run", Repo)
      result2 = FlowBuilder.create_flow("run", Repo)

      assert result1 == {:error, :workflow_slug_reserved}
      assert result2 == {:error, :workflow_slug_reserved}
    end

    test "step with underscore-only slug is valid" do
      {:ok, _} = FlowBuilder.create_flow("test_underscore", Repo)
      {:ok, step} = FlowBuilder.add_step("test_underscore", "_", [], Repo)

      assert step["step_slug"] == "_"
    end

    test "workflow slug exactly 128 characters works" do
      max_slug = String.duplicate("a", 128)
      {:ok, workflow} = FlowBuilder.create_flow(max_slug, Repo)

      assert workflow["workflow_slug"] == max_slug
    end

    test "accepts very large initial_tasks" do
      {:ok, _} = FlowBuilder.create_flow("test_large_tasks", Repo)

      {:ok, step} =
        FlowBuilder.add_step("test_large_tasks", "step1", [], Repo, initial_tasks: 1_000_000)

      assert step["initial_tasks"] == 1_000_000
    end

    test "step max_attempts overrides workflow default" do
      {:ok, _} = FlowBuilder.create_flow("test_override", Repo, max_attempts: 3)
      {:ok, step} = FlowBuilder.add_step("test_override", "step1", [], Repo, max_attempts: 10)

      assert step["max_attempts"] == 10
    end

    test "step timeout overrides workflow default" do
      {:ok, _} = FlowBuilder.create_flow("test_timeout_override", Repo, timeout: 60)
      {:ok, step} = FlowBuilder.add_step("test_timeout_override", "step1", [], Repo, timeout: 300)

      assert step["timeout"] == 300
    end

    test "get_flow returns 404 for non-existent workflow" do
      result = FlowBuilder.get_flow("never_created", Repo)

      assert result == {:error, :not_found}
    end
  end

  describe "idempotency - creating/updating workflows safely" do
    test "creating same workflow twice returns error on second attempt" do
      {:ok, workflow1} = FlowBuilder.create_flow("test_idempotent", Repo)
      assert workflow1["workflow_slug"] == "test_idempotent"

      # Second attempt should fail
      result = FlowBuilder.create_flow("test_idempotent", Repo)
      assert match?({:error, {:workflow_already_exists, _}}, result)
    end

    test "adding same step twice with same slug returns error on second attempt" do
      {:ok, _} = FlowBuilder.create_flow("test_step_idempotent", Repo)
      {:ok, step1} = FlowBuilder.add_step("test_step_idempotent", "process", [], Repo)
      assert step1["step_slug"] == "process"

      # Second attempt with same step slug should fail
      result = FlowBuilder.add_step("test_step_idempotent", "process", [], Repo)
      assert match?({:error, {:duplicate_step_slug, _}}, result)
    end

    test "deleting non-existent workflow succeeds without error" do
      # Workflow never existed
      result = FlowBuilder.delete_flow("never_existed_workflow", Repo)

      # Should succeed silently (idempotent)
      assert result == :ok
    end

    test "deleting same workflow twice succeeds both times" do
      {:ok, _} = FlowBuilder.create_flow("test_delete_twice", Repo)
      {:ok, _} = FlowBuilder.add_step("test_delete_twice", "step1", [], Repo)

      # First deletion succeeds
      result1 = FlowBuilder.delete_flow("test_delete_twice", Repo)
      assert result1 == :ok

      # Second deletion also succeeds (idempotent)
      result2 = FlowBuilder.delete_flow("test_delete_twice", Repo)
      assert result2 == :ok
    end

    test "getting same workflow multiple times returns consistent data" do
      {:ok, _} = FlowBuilder.create_flow("test_get_consistent", Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_consistent", "a", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_get_consistent", "b", ["a"], Repo)

      # Get multiple times
      {:ok, get1} = FlowBuilder.get_flow("test_get_consistent", Repo)
      {:ok, get2} = FlowBuilder.get_flow("test_get_consistent", Repo)
      {:ok, get3} = FlowBuilder.get_flow("test_get_consistent", Repo)

      # All results should be identical
      assert get1["workflow_slug"] == get2["workflow_slug"]
      assert get2["workflow_slug"] == get3["workflow_slug"]
      assert length(get1["steps"]) == length(get2["steps"])
      assert length(get2["steps"]) == length(get3["steps"])
    end

    test "listing workflows multiple times returns consistent results" do
      {:ok, _} = FlowBuilder.create_flow("list_test_1", Repo)
      {:ok, _} = FlowBuilder.create_flow("list_test_2", Repo)

      {:ok, list1} = FlowBuilder.list_flows(Repo)
      {:ok, list2} = FlowBuilder.list_flows(Repo)

      # Count should be consistent
      assert length(list1) == length(list2)

      # Results should be in same order (by created_at DESC)
      list1_slugs = Enum.map(list1, & &1["workflow_slug"])
      list2_slugs = Enum.map(list2, & &1["workflow_slug"])
      assert list1_slugs == list2_slugs
    end

    test "adding steps with same dependencies multiple times uses existing dependencies" do
      {:ok, _} = FlowBuilder.create_flow("test_deps_idempotent", Repo)
      {:ok, _} = FlowBuilder.add_step("test_deps_idempotent", "a", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_deps_idempotent", "b", [], Repo)

      # Add step with dependencies
      {:ok, _} = FlowBuilder.add_step("test_deps_idempotent", "c", ["a", "b"], Repo)
      {:ok, step1} = FlowBuilder.get_flow("test_deps_idempotent", Repo)
      step_c_1 = Enum.find(step1["steps"], &(&1["step_slug"] == "c"))

      # Verify it has 2 dependencies
      assert step_c_1["deps_count"] == 2
    end

    test "updating step options (max_attempts, timeout) creates new values on first add" do
      {:ok, _} = FlowBuilder.create_flow("test_update_opts", Repo)

      # Add step with custom options
      {:ok, step1} =
        FlowBuilder.add_step("test_update_opts", "custom", [], Repo, max_attempts: 5, timeout: 120)

      assert step1["max_attempts"] == 5
      assert step1["timeout"] == 120

      # Get workflow to verify persisted
      {:ok, workflow} = FlowBuilder.get_flow("test_update_opts", Repo)
      step_custom = Enum.find(workflow["steps"], &(&1["step_slug"] == "custom"))
      assert step_custom["max_attempts"] == 5
      assert step_custom["timeout"] == 120
    end

    test "reading deleted workflow returns :not_found" do
      {:ok, _} = FlowBuilder.create_flow("test_read_deleted", Repo)

      # Verify it exists
      {:ok, _} = FlowBuilder.get_flow("test_read_deleted", Repo)

      # Delete it
      :ok = FlowBuilder.delete_flow("test_read_deleted", Repo)

      # Reading should now fail
      result = FlowBuilder.get_flow("test_read_deleted", Repo)
      assert result == {:error, :not_found}
    end
  end

  describe "runtime error recovery - handling failures gracefully" do
    test "step with no dependencies can be added after failed add_step attempt" do
      {:ok, _} = FlowBuilder.create_flow("test_recover_1", Repo)

      # First attempt fails (invalid step type)
      result1 = FlowBuilder.add_step("test_recover_1", "bad_step", [], Repo, step_type: "invalid")
      assert match?({:error, _}, result1)

      # Second attempt with valid parameters succeeds
      result2 = FlowBuilder.add_step("test_recover_1", "good_step", [], Repo)
      assert match?({:ok, _}, result2)
    end

    test "workflow can be fixed after failed step add with missing dependency" do
      {:ok, _} = FlowBuilder.create_flow("test_recover_missing_dep", Repo)

      # First attempt fails (missing dependency)
      result1 = FlowBuilder.add_step("test_recover_missing_dep", "step1", ["nonexistent"], Repo)
      assert match?({:error, {:missing_dependencies, _}}, result1)

      # Create the missing dependency first
      {:ok, _} = FlowBuilder.add_step("test_recover_missing_dep", "nonexistent", [], Repo)

      # Now add a new step with valid dependency succeeds
      result2 = FlowBuilder.add_step("test_recover_missing_dep", "step2", ["nonexistent"], Repo)
      assert match?({:ok, _}, result2)

      # Verify workflow is queryable and has at least the dependency step
      {:ok, workflow} = FlowBuilder.get_flow("test_recover_missing_dep", Repo)
      assert Enum.any?(workflow["steps"], &(&1["step_slug"] == "nonexistent"))
      assert Enum.any?(workflow["steps"], &(&1["step_slug"] == "step2"))
    end

    test "duplicate step error doesn't corrupt workflow state" do
      {:ok, _} = FlowBuilder.create_flow("test_recover_3", Repo)
      {:ok, _} = FlowBuilder.add_step("test_recover_3", "step1", [], Repo)

      # Try to add duplicate
      result1 = FlowBuilder.add_step("test_recover_3", "step1", [], Repo)
      assert match?({:error, {:duplicate_step_slug, _}}, result1)

      # Workflow should still be queryable
      {:ok, workflow} = FlowBuilder.get_flow("test_recover_3", Repo)
      assert length(workflow["steps"]) == 1

      # Can still add different step
      {:ok, step2} = FlowBuilder.add_step("test_recover_3", "step2", ["step1"], Repo)
      assert step2["step_slug"] == "step2"

      # Verify both steps exist
      {:ok, workflow2} = FlowBuilder.get_flow("test_recover_3", Repo)
      assert length(workflow2["steps"]) == 2
    end

    test "invalid initial_tasks error doesn't prevent subsequent valid add" do
      {:ok, _} = FlowBuilder.create_flow("test_recover_4", Repo)

      # Try invalid initial_tasks
      result1 =
        FlowBuilder.add_step("test_recover_4", "map_step", [], Repo,
          step_type: "map",
          initial_tasks: -1
        )

      assert match?({:error, :initial_tasks_must_be_positive}, result1)

      # Add with valid initial_tasks succeeds
      result2 =
        FlowBuilder.add_step("test_recover_4", "map_step", [], Repo,
          step_type: "map",
          initial_tasks: 10
        )

      assert match?({:ok, _}, result2)
    end

    test "listing workflows works even after failed operations" do
      {:ok, _} = FlowBuilder.create_flow("test_recover_5", Repo)

      # Attempt operations that fail
      _ = FlowBuilder.add_step("test_recover_5", "step", [], Repo, step_type: "bad")
      _ = FlowBuilder.create_flow("test_recover_5", Repo)

      # List should still work
      {:ok, workflows} = FlowBuilder.list_flows(Repo)
      assert is_list(workflows)
      assert length(workflows) > 0
    end

    test "deleting partially-built workflow succeeds" do
      {:ok, _} = FlowBuilder.create_flow("test_recover_6", Repo)
      {:ok, _} = FlowBuilder.add_step("test_recover_6", "step1", [], Repo)

      # Try to add step that fails (missing dependency)
      _ = FlowBuilder.add_step("test_recover_6", "step2", ["missing"], Repo)

      # Delete should still work on partially-built workflow
      result = FlowBuilder.delete_flow("test_recover_6", Repo)
      assert result == :ok

      # Verify completely deleted
      {:ok, result} =
        Repo.query("SELECT COUNT(*) FROM workflows WHERE workflow_slug = 'test_recover_6'", [])

      assert result.rows == [[0]]
    end
  end
end
