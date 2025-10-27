defmodule Pgflow.DAG.DynamicWorkflowLoaderTest do
  use ExUnit.Case, async: false

  alias Pgflow.{Repo, FlowBuilder, DAG.DynamicWorkflowLoader, DAG.WorkflowDefinition}

  @moduledoc """
  Comprehensive DynamicWorkflowLoader tests covering:
  - Chicago-style TDD (state-based testing)
  - Loading workflows from database
  - Step function mapping
  - Dependency graph reconstruction
  - Error handling
  """

  setup do
    # Set up sandbox for this test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    # Clean up any existing test workflows
    Repo.query("DELETE FROM workflows WHERE workflow_slug LIKE 'test_%'", [])
    :ok
  end

  describe "Loading workflow metadata" do
    test "loads workflow configuration" do
      # Create workflow via FlowBuilder
      {:ok, _} = FlowBuilder.create_flow("test_load_config", Repo, max_attempts: 5, timeout: 120)
      {:ok, _} = FlowBuilder.add_step("test_load_config", "step1", [], Repo)

      # Load via DynamicWorkflowLoader
      step_functions = %{step1: fn input -> {:ok, input} end}
      {:ok, definition} = DynamicWorkflowLoader.load("test_load_config", step_functions, Repo)

      assert definition.slug == "test_load_config"
      assert definition.steps[:step1] != nil
    end

    test "handles missing workflow" do
      step_functions = %{step1: fn input -> {:ok, input} end}
      result = DynamicWorkflowLoader.load("nonexistent_workflow", step_functions, Repo)

      assert {:error, {:workflow_not_found, "nonexistent_workflow"}} = result
    end

    test "loads all workflow steps" do
      {:ok, _} = FlowBuilder.create_flow("test_load_steps", Repo)
      {:ok, _} = FlowBuilder.add_step("test_load_steps", "fetch", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_load_steps", "process", ["fetch"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_load_steps", "save", ["process"], Repo)

      step_functions = %{
        fetch: fn _ -> {:ok, %{data: "fetched"}} end,
        process: fn input -> {:ok, Map.put(input, :processed, true)} end,
        save: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_load_steps", step_functions, Repo)

      assert map_size(definition.steps) == 3
      assert definition.steps[:fetch] != nil
      assert definition.steps[:process] != nil
      assert definition.steps[:save] != nil
    end

    test "handles workflow with no steps" do
      {:ok, _} = FlowBuilder.create_flow("test_empty_workflow", Repo)

      step_functions = %{}
      result = DynamicWorkflowLoader.load("test_empty_workflow", step_functions, Repo)

      # Should fail because no root steps can be found
      assert {:error, :no_root_steps} = result
    end

    test "loads step dependencies" do
      {:ok, _} = FlowBuilder.create_flow("test_deps", Repo)
      {:ok, _} = FlowBuilder.add_step("test_deps", "root", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_deps", "child", ["root"], Repo)

      step_functions = %{
        root: fn _ -> {:ok, %{}} end,
        child: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_deps", step_functions, Repo)

      assert definition.dependencies[:root] == []
      assert definition.dependencies[:child] == [:root]
    end

    test "handles workflow with no dependencies (single root step)" do
      {:ok, _} = FlowBuilder.create_flow("test_single_root", Repo)
      {:ok, _} = FlowBuilder.add_step("test_single_root", "only_step", [], Repo)

      step_functions = %{only_step: fn input -> {:ok, input} end}

      {:ok, definition} = DynamicWorkflowLoader.load("test_single_root", step_functions, Repo)

      assert definition.dependencies[:only_step] == []
      assert definition.root_steps == [:only_step]
    end
  end

  describe "Dependency graph reconstruction" do
    test "creates step → dependencies map" do
      {:ok, _} = FlowBuilder.create_flow("test_dep_map", Repo)
      {:ok, _} = FlowBuilder.add_step("test_dep_map", "step_root", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_dep_map", "step_b", ["step_root"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_dep_map", "step_c", ["step_root"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_dep_map", "step_a", ["step_b", "step_c"], Repo)

      step_functions = %{
        step_root: fn _ -> {:ok, %{}} end,
        step_a: fn input -> {:ok, input} end,
        step_b: fn input -> {:ok, input} end,
        step_c: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_dep_map", step_functions, Repo)

      assert Enum.sort(definition.dependencies[:step_a]) == [:step_b, :step_c]
      assert definition.dependencies[:step_b] == [:step_root]
      assert definition.dependencies[:step_c] == [:step_root]
      assert definition.dependencies[:step_root] == []
    end

    test "identifies root steps" do
      {:ok, _} = FlowBuilder.create_flow("test_roots", Repo)
      {:ok, _} = FlowBuilder.add_step("test_roots", "root1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_roots", "root2", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_roots", "child", ["root1", "root2"], Repo)

      step_functions = %{
        root1: fn _ -> {:ok, %{}} end,
        root2: fn _ -> {:ok, %{}} end,
        child: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_roots", step_functions, Repo)

      assert Enum.sort(definition.root_steps) == [:root1, :root2]
    end

    test "handles single root step" do
      {:ok, _} = FlowBuilder.create_flow("test_single_root_chain", Repo)
      {:ok, _} = FlowBuilder.add_step("test_single_root_chain", "root", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_single_root_chain", "step1", ["root"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_single_root_chain", "step2", ["step1"], Repo)

      step_functions = %{
        root: fn _ -> {:ok, %{}} end,
        step1: fn input -> {:ok, input} end,
        step2: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_single_root_chain", step_functions, Repo)

      assert definition.root_steps == [:root]
    end

    test "handles multiple root steps (parallel start)" do
      {:ok, _} = FlowBuilder.create_flow("test_multi_roots", Repo)
      {:ok, _} = FlowBuilder.add_step("test_multi_roots", "fetch_a", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_multi_roots", "fetch_b", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_multi_roots", "fetch_c", [], Repo)

      {:ok, _} =
        FlowBuilder.add_step("test_multi_roots", "merge", ["fetch_a", "fetch_b", "fetch_c"], Repo)

      step_functions = %{
        fetch_a: fn _ -> {:ok, %{a: 1}} end,
        fetch_b: fn _ -> {:ok, %{b: 2}} end,
        fetch_c: fn _ -> {:ok, %{c: 3}} end,
        merge: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_multi_roots", step_functions, Repo)

      assert Enum.sort(definition.root_steps) == [:fetch_a, :fetch_b, :fetch_c]
    end

    test "handles diamond dependencies" do
      {:ok, _} = FlowBuilder.create_flow("test_diamond", Repo)
      {:ok, _} = FlowBuilder.add_step("test_diamond", "a", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_diamond", "b", ["a"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_diamond", "c", ["a"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_diamond", "d", ["b", "c"], Repo)

      step_functions = %{
        a: fn _ -> {:ok, %{data: "a"}} end,
        b: fn input -> {:ok, Map.put(input, :b, true)} end,
        c: fn input -> {:ok, Map.put(input, :c, true)} end,
        d: fn input -> {:ok, Map.put(input, :d, true)} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_diamond", step_functions, Repo)

      assert definition.dependencies[:b] == [:a]
      assert definition.dependencies[:c] == [:a]
      assert Enum.sort(definition.dependencies[:d]) == [:b, :c]
    end

    test "handles complex DAGs" do
      {:ok, _} = FlowBuilder.create_flow("test_complex", Repo)
      {:ok, _} = FlowBuilder.add_step("test_complex", "a1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_complex", "a2", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_complex", "b1", ["a1"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_complex", "b2", ["a1", "a2"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_complex", "b3", ["a2"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_complex", "c1", ["b1", "b2"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_complex", "c2", ["b2", "b3"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_complex", "final", ["c1", "c2"], Repo)

      step_functions = %{
        a1: fn _ -> {:ok, %{}} end,
        a2: fn _ -> {:ok, %{}} end,
        b1: fn input -> {:ok, input} end,
        b2: fn input -> {:ok, input} end,
        b3: fn input -> {:ok, input} end,
        c1: fn input -> {:ok, input} end,
        c2: fn input -> {:ok, input} end,
        final: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_complex", step_functions, Repo)

      assert Enum.sort(definition.root_steps) == [:a1, :a2]
      assert definition.dependencies[:b1] == [:a1]
      assert Enum.sort(definition.dependencies[:b2]) == [:a1, :a2]
      assert definition.dependencies[:b3] == [:a2]
      assert Enum.sort(definition.dependencies[:c1]) == [:b1, :b2]
      assert Enum.sort(definition.dependencies[:c2]) == [:b2, :b3]
      assert Enum.sort(definition.dependencies[:final]) == [:c1, :c2]
    end
  end

  describe "Step function mapping" do
    test "maps step slugs to provided functions" do
      {:ok, _} = FlowBuilder.create_flow("test_fn_mapping", Repo)
      {:ok, _} = FlowBuilder.add_step("test_fn_mapping", "fetch_data", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_fn_mapping", "process", ["fetch_data"], Repo)

      fetch_fn = fn _ -> {:ok, %{data: "fetched"}} end
      process_fn = fn input -> {:ok, Map.put(input, :processed, true)} end

      step_functions = %{
        fetch_data: fetch_fn,
        process: process_fn
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_fn_mapping", step_functions, Repo)

      assert definition.steps[:fetch_data] == fetch_fn
      assert definition.steps[:process] == process_fn
    end

    test "validates all steps have functions" do
      {:ok, _} = FlowBuilder.create_flow("test_missing_fn", Repo)
      {:ok, _} = FlowBuilder.add_step("test_missing_fn", "foo", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_missing_fn", "bar", ["foo"], Repo)

      # Only provide function for foo, not bar
      step_functions = %{
        foo: fn _ -> {:ok, %{}} end
      }

      # Should raise an error about missing function
      assert_raise RuntimeError, ~r/Missing function for step bar/, fn ->
        DynamicWorkflowLoader.load("test_missing_fn", step_functions, Repo)
      end
    end

    test "handles extra functions in step_functions" do
      {:ok, _} = FlowBuilder.create_flow("test_extra_fns", Repo)
      {:ok, _} = FlowBuilder.add_step("test_extra_fns", "step1", [], Repo)

      # Provide extra functions that aren't used
      step_functions = %{
        step1: fn _ -> {:ok, %{}} end,
        unused_step: fn _ -> {:ok, %{}} end,
        another_unused: fn _ -> {:ok, %{}} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_extra_fns", step_functions, Repo)

      # Should only have step1 in the definition
      assert map_size(definition.steps) == 1
      assert definition.steps[:step1] != nil
    end

    test "supports atom function names" do
      {:ok, _} = FlowBuilder.create_flow("test_atom_names", Repo)
      {:ok, _} = FlowBuilder.add_step("test_atom_names", "fetch_data", [], Repo)

      # step_functions uses atoms, database uses strings
      step_functions = %{
        fetch_data: fn _ -> {:ok, %{data: "test"}} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_atom_names", step_functions, Repo)

      assert definition.steps[:fetch_data] != nil
      assert is_function(definition.steps[:fetch_data])
    end
  end

  describe "WorkflowDefinition creation" do
    test "returns valid WorkflowDefinition struct" do
      {:ok, _} = FlowBuilder.create_flow("test_wf_struct", Repo)
      {:ok, _} = FlowBuilder.add_step("test_wf_struct", "step1", [], Repo)

      step_functions = %{step1: fn _ -> {:ok, %{}} end}

      {:ok, definition} = DynamicWorkflowLoader.load("test_wf_struct", step_functions, Repo)

      assert %WorkflowDefinition{} = definition
      assert is_map(definition.steps)
      assert is_map(definition.dependencies)
      assert is_list(definition.root_steps)
      assert is_binary(definition.slug)
      assert is_map(definition.step_metadata)
    end

    test "steps field maps atoms to functions" do
      {:ok, _} = FlowBuilder.create_flow("test_steps_field", Repo)
      {:ok, _} = FlowBuilder.add_step("test_steps_field", "fetch", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_steps_field", "process", ["fetch"], Repo)

      step_functions = %{
        fetch: fn _ -> {:ok, %{}} end,
        process: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_steps_field", step_functions, Repo)

      assert is_function(definition.steps[:fetch])
      assert is_function(definition.steps[:process])
    end

    test "dependencies field matches database" do
      {:ok, _} = FlowBuilder.create_flow("test_deps_field", Repo)
      {:ok, _} = FlowBuilder.add_step("test_deps_field", "a", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_deps_field", "b", ["a"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_deps_field", "c", ["a", "b"], Repo)

      step_functions = %{
        a: fn _ -> {:ok, %{}} end,
        b: fn input -> {:ok, input} end,
        c: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_deps_field", step_functions, Repo)

      assert definition.dependencies[:a] == []
      assert definition.dependencies[:b] == [:a]
      assert Enum.sort(definition.dependencies[:c]) == [:a, :b]
    end

    test "root_steps identified correctly" do
      {:ok, _} = FlowBuilder.create_flow("test_root_identification", Repo)
      {:ok, _} = FlowBuilder.add_step("test_root_identification", "root1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_root_identification", "root2", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_root_identification", "child", ["root1"], Repo)

      step_functions = %{
        root1: fn _ -> {:ok, %{}} end,
        root2: fn _ -> {:ok, %{}} end,
        child: fn input -> {:ok, input} end
      }

      {:ok, definition} =
        DynamicWorkflowLoader.load("test_root_identification", step_functions, Repo)

      assert Enum.sort(definition.root_steps) == [:root1, :root2]
    end

    test "slug is workflow_slug from database" do
      {:ok, _} = FlowBuilder.create_flow("test_slug_preservation", Repo)
      {:ok, _} = FlowBuilder.add_step("test_slug_preservation", "step1", [], Repo)

      step_functions = %{step1: fn _ -> {:ok, %{}} end}

      {:ok, definition} = DynamicWorkflowLoader.load("test_slug_preservation", step_functions, Repo)

      assert definition.slug == "test_slug_preservation"
    end

    test "preserves step metadata" do
      {:ok, _} = FlowBuilder.create_flow("test_metadata", Repo, max_attempts: 5, timeout: 120)

      {:ok, _} =
        FlowBuilder.add_step("test_metadata", "step1", [], Repo,
          step_type: "map",
          initial_tasks: 50,
          max_attempts: 10,
          timeout: 300
        )

      step_functions = %{step1: fn _ -> {:ok, %{}} end}

      {:ok, definition} = DynamicWorkflowLoader.load("test_metadata", step_functions, Repo)

      metadata = definition.step_metadata[:step1]
      assert metadata.initial_tasks == 50
      assert metadata.max_attempts == 10
      assert metadata.timeout == 300
    end
  end

  describe "Error handling" do
    test "workflow not found" do
      step_functions = %{step1: fn _ -> {:ok, %{}} end}
      result = DynamicWorkflowLoader.load("nonexistent_workflow", step_functions, Repo)

      assert {:error, {:workflow_not_found, "nonexistent_workflow"}} = result
    end

    test "missing step function raises clear error" do
      {:ok, _} = FlowBuilder.create_flow("test_missing_function", Repo)
      {:ok, _} = FlowBuilder.add_step("test_missing_function", "some_step", [], Repo)

      step_functions = %{}

      assert_raise RuntimeError, ~r/Missing function for step some_step/, fn ->
        DynamicWorkflowLoader.load("test_missing_function", step_functions, Repo)
      end
    end

    test "database constraints prevent invalid dependencies" do
      # Database constraints prevent invalid dependencies from being inserted
      {:ok, _} = FlowBuilder.create_flow("test_invalid_dep_validation", Repo)
      {:ok, _} = FlowBuilder.add_step("test_invalid_dep_validation", "step1", [], Repo)

      # Attempt to manually insert invalid dependency (should fail due to FK constraints)
      result =
        Repo.query(
          """
          INSERT INTO workflow_step_dependencies_def (workflow_slug, step_slug, dep_slug)
          VALUES ('test_invalid_dep_validation', 'step1', 'nonexistent_step')
          """,
          []
        )

      # Should fail due to foreign key constraint
      assert {:error, _} = result

      step_functions = %{step1: fn _ -> {:ok, %{}} end}

      # Load should succeed since no invalid dependencies were inserted
      result = DynamicWorkflowLoader.load("test_invalid_dep_validation", step_functions, Repo)

      assert {:ok, %Pgflow.DAG.WorkflowDefinition{}} = result
    end
  end

  describe "Comparison with static workflows" do
    test "loaded workflow structure matches static workflow structure" do
      {:ok, _} = FlowBuilder.create_flow("test_structure_match", Repo)
      {:ok, _} = FlowBuilder.add_step("test_structure_match", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_structure_match", "step2", ["step1"], Repo)

      step_functions = %{
        step1: fn _ -> {:ok, %{}} end,
        step2: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_structure_match", step_functions, Repo)

      # Should have same structure as WorkflowDefinition from static workflow
      assert %WorkflowDefinition{} = definition
      assert is_map(definition.steps)
      assert is_map(definition.dependencies)
      assert is_list(definition.root_steps)
      assert definition.slug != nil
      assert definition.step_metadata != nil
    end

    test "same execution semantics as static workflows" do
      {:ok, _} = FlowBuilder.create_flow("test_semantics", Repo)
      {:ok, _} = FlowBuilder.add_step("test_semantics", "root", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_semantics", "child1", ["root"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_semantics", "child2", ["root"], Repo)

      step_functions = %{
        root: fn _ -> {:ok, %{}} end,
        child1: fn input -> {:ok, input} end,
        child2: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_semantics", step_functions, Repo)

      # Same DAG validation rules apply
      assert definition.root_steps == [:root]
      assert definition.dependencies[:child1] == [:root]
      assert definition.dependencies[:child2] == [:root]
    end
  end

  describe "Complex workflow scenarios" do
    test "loads ETL workflow" do
      {:ok, _} = FlowBuilder.create_flow("test_etl", Repo)
      {:ok, _} = FlowBuilder.add_step("test_etl", "extract", [], Repo)
      {:ok, _} = FlowBuilder.add_step("test_etl", "transform", ["extract"], Repo)
      {:ok, _} = FlowBuilder.add_step("test_etl", "load", ["transform"], Repo)

      step_functions = %{
        extract: fn _ -> {:ok, %{data: [1, 2, 3]}} end,
        transform: fn input -> {:ok, Map.put(input, :transformed, true)} end,
        load: fn input -> {:ok, Map.put(input, :loaded, true)} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_etl", step_functions, Repo)

      assert definition.root_steps == [:extract]
      assert definition.dependencies[:transform] == [:extract]
      assert definition.dependencies[:load] == [:transform]
    end

    test "loads parallel processing workflow" do
      {:ok, _} = FlowBuilder.create_flow("test_parallel_processing", Repo)
      {:ok, _} = FlowBuilder.add_step("test_parallel_processing", "start", [], Repo)

      # Create 10 parallel workers
      Enum.each(1..10, fn i ->
        step_slug = "worker_#{i}"
        {:ok, _} = FlowBuilder.add_step("test_parallel_processing", step_slug, ["start"], Repo)
      end)

      {:ok, _} =
        FlowBuilder.add_step(
          "test_parallel_processing",
          "gather",
          Enum.map(1..10, &"worker_#{&1}"),
          Repo
        )

      # Create step functions
      step_functions =
        %{
          start: fn _ -> {:ok, %{}} end,
          gather: fn input -> {:ok, input} end
        }
        |> Map.merge(
          Enum.reduce(1..10, %{}, fn i, acc ->
            Map.put(acc, String.to_atom("worker_#{i}"), fn input -> {:ok, input} end)
          end)
        )

      {:ok, definition} =
        DynamicWorkflowLoader.load("test_parallel_processing", step_functions, Repo)

      assert definition.root_steps == [:start]
      assert length(definition.dependencies[:gather]) == 10
    end

    test "loads map step workflow" do
      {:ok, _} = FlowBuilder.create_flow("test_map_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("test_map_workflow", "fetch", [], Repo)

      {:ok, _} =
        FlowBuilder.add_step("test_map_workflow", "process_batch", ["fetch"], Repo,
          step_type: "map",
          initial_tasks: 100
        )

      {:ok, _} = FlowBuilder.add_step("test_map_workflow", "aggregate", ["process_batch"], Repo)

      step_functions = %{
        fetch: fn _ -> {:ok, %{items: Enum.to_list(1..100)}} end,
        process_batch: fn input -> {:ok, input} end,
        aggregate: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_map_workflow", step_functions, Repo)

      process_metadata = definition.step_metadata[:process_batch]
      assert process_metadata.initial_tasks == 100
    end

    test "loads workflow with timeouts and retries" do
      {:ok, _} =
        FlowBuilder.create_flow("test_timeouts_retries", Repo, max_attempts: 5, timeout: 300)

      {:ok, _} =
        FlowBuilder.add_step("test_timeouts_retries", "step1", [], Repo,
          max_attempts: 10,
          timeout: 600
        )

      {:ok, _} = FlowBuilder.add_step("test_timeouts_retries", "step2", ["step1"], Repo)

      step_functions = %{
        step1: fn _ -> {:ok, %{}} end,
        step2: fn input -> {:ok, input} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("test_timeouts_retries", step_functions, Repo)

      step1_meta = definition.step_metadata[:step1]
      assert step1_meta.max_attempts == 10
      assert step1_meta.timeout == 600

      # step2 should inherit workflow defaults
      step2_meta = definition.step_metadata[:step2]
      assert step2_meta.max_attempts == 5
      assert step2_meta.timeout == 300
    end

    test "loads large workflow (100+ steps)" do
      {:ok, _} = FlowBuilder.create_flow("test_large_workflow", Repo)

      # Create chain of 100 steps
      Enum.each(1..100, fn i ->
        step_name = "step_#{i}"
        deps = if i == 1, do: [], else: ["step_#{i - 1}"]
        {:ok, _} = FlowBuilder.add_step("test_large_workflow", step_name, deps, Repo)
      end)

      # Create step functions
      step_functions =
        Enum.reduce(1..100, %{}, fn i, acc ->
          Map.put(acc, String.to_atom("step_#{i}"), fn input -> {:ok, input} end)
        end)

      {:ok, definition} = DynamicWorkflowLoader.load("test_large_workflow", step_functions, Repo)

      assert map_size(definition.steps) == 100
      assert definition.root_steps == [:step_1]
    end
  end

  describe "AI-generated workflows" do
    test "supports AI-generated dynamic workflows" do
      # Simulate AI generating a workflow
      {:ok, _} = FlowBuilder.create_flow("ai_generated_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("ai_generated_workflow", "analyze_input", [], Repo)

      {:ok, _} =
        FlowBuilder.add_step("ai_generated_workflow", "process_data", ["analyze_input"], Repo)

      {:ok, _} =
        FlowBuilder.add_step("ai_generated_workflow", "generate_output", ["process_data"], Repo)

      step_functions = %{
        analyze_input: fn _ -> {:ok, %{analyzed: true}} end,
        process_data: fn input -> {:ok, Map.put(input, :processed, true)} end,
        generate_output: fn input -> {:ok, Map.put(input, :output, "generated")} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("ai_generated_workflow", step_functions, Repo)

      assert definition.slug == "ai_generated_workflow"
      assert map_size(definition.steps) == 3
    end

    test "validates AI-generated definitions" do
      # AI might generate invalid workflow
      {:ok, _} = FlowBuilder.create_flow("invalid_ai_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("invalid_ai_workflow", "step1", [], Repo)

      # Manually insert circular dependency
      {:ok, _} = FlowBuilder.add_step("invalid_ai_workflow", "step2", ["step1"], Repo)

      Repo.query(
        """
        INSERT INTO workflow_step_dependencies_def (workflow_slug, step_slug, dep_slug)
        VALUES ('invalid_ai_workflow', 'step1', 'step2')
        """,
        []
      )

      step_functions = %{
        step1: fn _ -> {:ok, %{}} end,
        step2: fn input -> {:ok, input} end
      }

      # Should detect cycle
      result = DynamicWorkflowLoader.load("invalid_ai_workflow", step_functions, Repo)

      assert {:error, {:cycle_detected, _}} = result
    end
  end

  describe "Caching and optimization" do
    test "loads workflow fresh each time (no caching between calls)" do
      {:ok, _} = FlowBuilder.create_flow("test_no_cache", Repo)
      {:ok, _} = FlowBuilder.add_step("test_no_cache", "step1", [], Repo)

      step_functions = %{step1: fn _ -> {:ok, %{}} end}

      # Load twice
      {:ok, definition1} = DynamicWorkflowLoader.load("test_no_cache", step_functions, Repo)
      {:ok, definition2} = DynamicWorkflowLoader.load("test_no_cache", step_functions, Repo)

      # Should be separate struct instances (not cached)
      refute definition1 == definition2
    end

    test "efficient dependency graph construction" do
      {:ok, _} = FlowBuilder.create_flow("test_efficiency", Repo)

      # Create moderately complex DAG
      Enum.each(1..50, fn i ->
        deps = if i == 1, do: [], else: ["step_#{i - 1}"]
        {:ok, _} = FlowBuilder.add_step("test_efficiency", "step_#{i}", deps, Repo)
      end)

      step_functions =
        Enum.reduce(1..50, %{}, fn i, acc ->
          Map.put(acc, String.to_atom("step_#{i}"), fn input -> {:ok, input} end)
        end)

      # Should load quickly (no exponential algorithms)
      start_time = System.monotonic_time(:millisecond)
      {:ok, definition} = DynamicWorkflowLoader.load("test_efficiency", step_functions, Repo)
      end_time = System.monotonic_time(:millisecond)

      assert map_size(definition.steps) == 50
      # Should load in reasonable time (< 1 second for 50 steps)
      assert end_time - start_time < 1000
    end
  end
end
