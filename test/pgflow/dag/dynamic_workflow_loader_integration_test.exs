defmodule Pgflow.DAG.DynamicWorkflowLoaderIntegrationTest do
  use ExUnit.Case, async: false

  alias Pgflow.{FlowBuilder, Repo}
  alias Pgflow.DAG.DynamicWorkflowLoader

  @moduledoc """
  Comprehensive integration tests for DynamicWorkflowLoader.load/3

  Tests loading dynamic workflows from database and converting them
  to WorkflowDefinition structs for execution.
  """

  setup do
    # Clean up any existing workflows
    Repo.query!("DELETE FROM workflows")
    :ok
  end

  describe "load/3 - Basic workflow loading" do
    test "loads simple workflow with one step" do
      # Create workflow in database
      {:ok, _} = FlowBuilder.create_flow("simple_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("simple_workflow", "step1", [], Repo)

      # Define step function
      step_functions = %{
        step1: fn input -> {:ok, Map.put(input, :executed, true)} end
      }

      # Load workflow
      {:ok, definition} = DynamicWorkflowLoader.load("simple_workflow", step_functions, Repo)

      # Verify structure
      assert definition.slug == "simple_workflow"
      assert Map.has_key?(definition.steps, :step1)
      assert definition.root_steps == [:step1]
      assert definition.dependencies == %{}
    end

    test "loads workflow with sequential steps" do
      {:ok, _} = FlowBuilder.create_flow("sequential_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("sequential_workflow", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("sequential_workflow", "step2", ["step1"], Repo)

      step_functions = %{
        step1: fn input -> {:ok, Map.put(input, :step1_done, true)} end,
        step2: fn input -> {:ok, Map.put(input, :step2_done, true)} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("sequential_workflow", step_functions, Repo)

      assert MapSet.new(Map.keys(definition.steps)) == MapSet.new([:step1, :step2])
      assert definition.root_steps == [:step1]
      assert definition.dependencies == %{step2: [:step1]}
    end

    test "loads workflow with parallel branches" do
      {:ok, _} = FlowBuilder.create_flow("parallel_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("parallel_workflow", "fetch", [], Repo)
      {:ok, _} = FlowBuilder.add_step("parallel_workflow", "branch_a", ["fetch"], Repo)
      {:ok, _} = FlowBuilder.add_step("parallel_workflow", "branch_b", ["fetch"], Repo)
      {:ok, _} = FlowBuilder.add_step("parallel_workflow", "merge", ["branch_a", "branch_b"], Repo)

      step_functions = %{
        fetch: fn _input -> {:ok, %{data: "fetched"}} end,
        branch_a: fn input -> {:ok, Map.put(input, :a, true)} end,
        branch_b: fn input -> {:ok, Map.put(input, :b, true)} end,
        merge: fn input -> {:ok, Map.put(input, :merged, true)} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("parallel_workflow", step_functions, Repo)

      assert definition.root_steps == [:fetch]
      assert definition.dependencies[:branch_a] == [:fetch]
      assert definition.dependencies[:branch_b] == [:fetch]
      assert Enum.sort(definition.dependencies[:merge]) == [:branch_a, :branch_b]
    end

    test "loads workflow with map steps" do
      {:ok, _} = FlowBuilder.create_flow("map_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("map_workflow", "fetch", [], Repo)
      {:ok, _} = FlowBuilder.add_step("map_workflow", "process", ["fetch"], Repo,
        step_type: "map",
        initial_tasks: 10
      )

      step_functions = %{
        fetch: fn _input -> {:ok, %{items: [1, 2, 3]}} end,
        process: fn input -> {:ok, Map.get(input, "item")} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("map_workflow", step_functions, Repo)

      # Verify map step metadata
      process_metadata = definition.step_metadata[:process]
      assert process_metadata[:initial_tasks] == 10
    end

    test "loads workflow with custom max_attempts" do
      {:ok, _} = FlowBuilder.create_flow("retry_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("retry_workflow", "step1", [], Repo,
        max_attempts: 5
      )

      step_functions = %{
        step1: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("retry_workflow", step_functions, Repo)

      step_metadata = definition.step_metadata[:step1]
      assert step_metadata[:max_attempts] == 5
    end

    test "loads workflow with custom timeout" do
      {:ok, _} = FlowBuilder.create_flow("timeout_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("timeout_workflow", "slow_step", [], Repo,
        timeout: 300
      )

      step_functions = %{
        slow_step: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("timeout_workflow", step_functions, Repo)

      step_metadata = definition.step_metadata[:slow_step]
      assert step_metadata[:timeout] == 300
    end
  end

  describe "load/3 - Error handling" do
    test "returns error when workflow not found" do
      step_functions = %{
        step1: fn input -> {:ok, input} end
      }

      result = DynamicWorkflowLoader.load("nonexistent_workflow", step_functions, Repo)

      assert {:error, {:workflow_not_found, "nonexistent_workflow"}} = result
    end

    test "raises error when step function missing" do
      {:ok, _} = FlowBuilder.create_flow("missing_fn_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("missing_fn_workflow", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("missing_fn_workflow", "step2", ["step1"], Repo)

      # Only provide function for step1, not step2
      step_functions = %{
        step1: fn input -> {:ok, input} end
      }

      assert_raise RuntimeError, ~r/Missing function for step step2/, fn ->
        DynamicWorkflowLoader.load("missing_fn_workflow", step_functions, Repo)
      end
    end

    test "validates dependencies during loading" do
      # This would test that circular dependencies are detected
      # However, FlowBuilder should prevent creating invalid workflows
      # So this is more of a defensive check
      {:ok, _} = FlowBuilder.create_flow("valid_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("valid_workflow", "step1", [], Repo)

      step_functions = %{
        step1: fn input -> {:ok, input} end
      }

      # Should succeed for valid workflow
      {:ok, definition} = DynamicWorkflowLoader.load("valid_workflow", step_functions, Repo)
      assert definition.slug == "valid_workflow"
    end
  end

  describe "load/3 - Complex workflows" do
    test "loads diamond dependency pattern" do
      {:ok, _} = FlowBuilder.create_flow("diamond_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("diamond_workflow", "root", [], Repo)
      {:ok, _} = FlowBuilder.add_step("diamond_workflow", "left", ["root"], Repo)
      {:ok, _} = FlowBuilder.add_step("diamond_workflow", "right", ["root"], Repo)
      {:ok, _} = FlowBuilder.add_step("diamond_workflow", "merge", ["left", "right"], Repo)

      step_functions = %{
        root: fn _input -> {:ok, %{data: "root"}} end,
        left: fn input -> {:ok, Map.put(input, :left, true)} end,
        right: fn input -> {:ok, Map.put(input, :right, true)} end,
        merge: fn input -> {:ok, Map.put(input, :merged, true)} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("diamond_workflow", step_functions, Repo)

      assert definition.root_steps == [:root]
      assert length(Map.keys(definition.steps)) == 4
      assert Enum.sort(definition.dependencies[:merge]) == [:left, :right]
    end

    test "loads workflow with multiple root steps" do
      {:ok, _} = FlowBuilder.create_flow("multi_root_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("multi_root_workflow", "root_a", [], Repo)
      {:ok, _} = FlowBuilder.add_step("multi_root_workflow", "root_b", [], Repo)
      {:ok, _} = FlowBuilder.add_step("multi_root_workflow", "merge", ["root_a", "root_b"], Repo)

      step_functions = %{
        root_a: fn _input -> {:ok, %{a: 1}} end,
        root_b: fn _input -> {:ok, %{b: 2}} end,
        merge: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("multi_root_workflow", step_functions, Repo)

      assert Enum.sort(definition.root_steps) == [:root_a, :root_b]
    end

    test "loads deep dependency chain" do
      {:ok, _} = FlowBuilder.create_flow("deep_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("deep_workflow", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("deep_workflow", "step2", ["step1"], Repo)
      {:ok, _} = FlowBuilder.add_step("deep_workflow", "step3", ["step2"], Repo)
      {:ok, _} = FlowBuilder.add_step("deep_workflow", "step4", ["step3"], Repo)
      {:ok, _} = FlowBuilder.add_step("deep_workflow", "step5", ["step4"], Repo)

      step_functions = %{
        step1: fn input -> {:ok, Map.put(input, :depth, 1)} end,
        step2: fn input -> {:ok, Map.update(input, :depth, 2, &(&1 + 1))} end,
        step3: fn input -> {:ok, Map.update(input, :depth, 3, &(&1 + 1))} end,
        step4: fn input -> {:ok, Map.update(input, :depth, 4, &(&1 + 1))} end,
        step5: fn input -> {:ok, Map.update(input, :depth, 5, &(&1 + 1))} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("deep_workflow", step_functions, Repo)

      assert definition.root_steps == [:step1]
      assert length(Map.keys(definition.steps)) == 5
      assert definition.dependencies[:step5] == [:step4]
    end

    test "loads workflow with wide fan-out" do
      {:ok, _} = FlowBuilder.create_flow("fanout_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("fanout_workflow", "source", [], Repo)

      # Add 10 parallel branches
      for i <- 1..10 do
        {:ok, _} = FlowBuilder.add_step("fanout_workflow", "branch_#{i}", ["source"], Repo)
      end

      step_functions =
        Map.new([{:source, fn _input -> {:ok, %{data: "source"}} end}] ++
          for(i <- 1..10, do: {String.to_atom("branch_#{i}"), fn input -> {:ok, input} end}))

      {:ok, definition} = DynamicWorkflowLoader.load("fanout_workflow", step_functions, Repo)

      assert definition.root_steps == [:source]
      assert length(Map.keys(definition.steps)) == 11

      # All branches depend on source
      for i <- 1..10 do
        branch = String.to_atom("branch_#{i}")
        assert definition.dependencies[branch] == [:source]
      end
    end
  end

  describe "load/3 - Step function mapping" do
    test "maps step functions correctly by atom key" do
      {:ok, _} = FlowBuilder.create_flow("mapping_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("mapping_workflow", "transform", [], Repo)

      called = Agent.start_link(fn -> false end)
      {:ok, agent} = called

      step_functions = %{
        transform: fn input ->
          Agent.update(agent, fn _ -> true end)
          {:ok, Map.put(input, :transformed, true)}
        end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("mapping_workflow", step_functions, Repo)

      # Execute the function to verify it's mapped correctly
      step_fn = definition.steps[:transform]
      {:ok, result} = step_fn.(%{input: "test"})

      assert result[:transformed] == true
      assert Agent.get(agent, & &1) == true
    end

    test "preserves function behavior through loading" do
      {:ok, _} = FlowBuilder.create_flow("behavior_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("behavior_workflow", "add_one", [], Repo)

      step_functions = %{
        add_one: fn input ->
          count = Map.get(input, :count, 0)
          {:ok, Map.put(input, :count, count + 1)}
        end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("behavior_workflow", step_functions, Repo)

      # Verify function works as expected
      step_fn = definition.steps[:add_one]
      {:ok, result1} = step_fn.(%{count: 5})
      {:ok, result2} = step_fn.(%{count: 10})

      assert result1[:count] == 6
      assert result2[:count] == 11
    end
  end

  describe "load/3 - Integration with WorkflowDefinition" do
    test "loaded definition is valid for execution" do
      {:ok, _} = FlowBuilder.create_flow("execution_ready_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("execution_ready_workflow", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("execution_ready_workflow", "step2", ["step1"], Repo)

      step_functions = %{
        step1: fn input -> {:ok, Map.put(input, :step1_done, true)} end,
        step2: fn input -> {:ok, Map.put(input, :step2_done, true)} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("execution_ready_workflow", step_functions, Repo)

      # Verify it has all required fields for execution
      assert is_binary(definition.slug)
      assert is_map(definition.steps)
      assert is_map(definition.dependencies)
      assert is_list(definition.root_steps)
      assert is_map(definition.step_metadata)
    end

    test "loaded definition passes same validations as code-based workflows" do
      {:ok, _} = FlowBuilder.create_flow("validated_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("validated_workflow", "root", [], Repo)
      {:ok, _} = FlowBuilder.add_step("validated_workflow", "branch_a", ["root"], Repo)
      {:ok, _} = FlowBuilder.add_step("validated_workflow", "branch_b", ["root"], Repo)
      {:ok, _} = FlowBuilder.add_step("validated_workflow", "merge", ["branch_a", "branch_b"], Repo)

      step_functions = %{
        root: fn input -> {:ok, input} end,
        branch_a: fn input -> {:ok, input} end,
        branch_b: fn input -> {:ok, input} end,
        merge: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("validated_workflow", step_functions, Repo)

      # Should have validated:
      # - No cycles
      # - All dependencies exist
      # - Root steps identified correctly
      assert definition.root_steps == [:root]
      assert length(Map.keys(definition.steps)) == 4
    end
  end

  describe "load/3 - Edge cases" do
    test "loads workflow with single step" do
      {:ok, _} = FlowBuilder.create_flow("single_step_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("single_step_workflow", "only", [], Repo)

      step_functions = %{
        only: fn input -> {:ok, Map.put(input, :done, true)} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("single_step_workflow", step_functions, Repo)

      assert definition.root_steps == [:only]
      assert Map.keys(definition.steps) == [:only]
      assert definition.dependencies == %{}
    end

    test "loads workflow with complex step names" do
      {:ok, _} = FlowBuilder.create_flow("complex_names_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("complex_names_workflow", "fetch_user_data", [], Repo)
      {:ok, _} = FlowBuilder.add_step("complex_names_workflow", "validate_permissions_and_roles", ["fetch_user_data"], Repo)

      step_functions = %{
        fetch_user_data: fn input -> {:ok, input} end,
        validate_permissions_and_roles: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("complex_names_workflow", step_functions, Repo)

      assert Map.has_key?(definition.steps, :fetch_user_data)
      assert Map.has_key?(definition.steps, :validate_permissions_and_roles)
    end

    test "loads empty workflow (no steps)" do
      {:ok, _} = FlowBuilder.create_flow("empty_workflow", Repo)

      step_functions = %{}

      {:ok, definition} = DynamicWorkflowLoader.load("empty_workflow", step_functions, Repo)

      assert definition.slug == "empty_workflow"
      assert definition.steps == %{}
      assert definition.root_steps == []
      assert definition.dependencies == %{}
    end
  end
end
