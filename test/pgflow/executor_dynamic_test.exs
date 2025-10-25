defmodule Pgflow.ExecutorDynamicTest do
  use ExUnit.Case, async: false

  alias Pgflow.{Executor, FlowBuilder, WorkflowRun, StepState, Repo}
  import Ecto.Query

  @moduledoc """
  Tests for execute_dynamic/5 - dynamic workflow execution.

  These tests were originally skipped in ExecutorTest but are now
  implemented with full FlowBuilder integration.
  """

  setup do
    # Clean up any existing test data
    Repo.delete_all(WorkflowRun)
    Repo.query!("DELETE FROM workflows")
    :ok
  end

  describe "execute_dynamic/5 - Basic execution" do
    test "executes workflow loaded from database" do
      # Create workflow dynamically
      {:ok, _} = FlowBuilder.create_flow("dynamic_test_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("dynamic_test_workflow", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("dynamic_test_workflow", "step2", ["step1"], Repo)

      # Define step functions
      step_functions = %{
        step1: fn input -> {:ok, Map.put(input, :step1_done, true)} end,
        step2: fn input -> {:ok, Map.put(input, :step2_done, true)} end
      }

      # Execute
      {:ok, result} = Executor.execute_dynamic(
        "dynamic_test_workflow",
        %{initial: true},
        step_functions,
        Repo
      )

      # Verify result
      assert result.initial == true
      assert result.step1_done == true
      assert result.step2_done == true
    end

    test "executes single-step dynamic workflow" do
      {:ok, _} = FlowBuilder.create_flow("single_step", Repo)
      {:ok, _} = FlowBuilder.add_step("single_step", "only", [], Repo)

      step_functions = %{
        only: fn input -> {:ok, Map.put(input, :executed, true)} end
      }

      {:ok, result} = Executor.execute_dynamic("single_step", %{}, step_functions, Repo)

      assert result.executed == true
    end

    test "executes parallel dynamic workflow" do
      {:ok, _} = FlowBuilder.create_flow("parallel_dynamic", Repo)
      {:ok, _} = FlowBuilder.add_step("parallel_dynamic", "fetch", [], Repo)
      {:ok, _} = FlowBuilder.add_step("parallel_dynamic", "analyze", ["fetch"], Repo)
      {:ok, _} = FlowBuilder.add_step("parallel_dynamic", "summarize", ["fetch"], Repo)
      {:ok, _} = FlowBuilder.add_step("parallel_dynamic", "report", ["analyze", "summarize"], Repo)

      step_functions = %{
        fetch: fn _input -> {:ok, %{data: [1, 2, 3]}} end,
        analyze: fn input -> {:ok, Map.put(input, :analyzed, true)} end,
        summarize: fn input -> {:ok, Map.put(input, :summarized, true)} end,
        report: fn input -> {:ok, Map.put(input, :reported, true)} end
      }

      {:ok, result} = Executor.execute_dynamic("parallel_dynamic", %{}, step_functions, Repo)

      assert result.data == [1, 2, 3]
      assert result.analyzed == true
      assert result.summarized == true
      assert result.reported == true
    end
  end

  describe "execute_dynamic/5 - Step function mapping" do
    test "maps step functions correctly" do
      {:ok, _} = FlowBuilder.create_flow("mapping_test", Repo)
      {:ok, _} = FlowBuilder.add_step("mapping_test", "transform", [], Repo)
      {:ok, _} = FlowBuilder.add_step("mapping_test", "validate", ["transform"], Repo)

      # Track function calls
      {:ok, agent} = Agent.start_link(fn -> [] end)

      step_functions = %{
        transform: fn input ->
          Agent.update(agent, fn calls -> [:transform | calls] end)
          {:ok, Map.put(input, :transformed, true)}
        end,
        validate: fn input ->
          Agent.update(agent, fn calls -> [:validate | calls] end)
          {:ok, Map.put(input, :validated, true)}
        end
      }

      {:ok, result} = Executor.execute_dynamic("mapping_test", %{}, step_functions, Repo)

      # Verify both functions were called
      calls = Agent.get(agent, & &1)
      assert :transform in calls
      assert :validate in calls

      # Verify results
      assert result.transformed == true
      assert result.validated == true
    end

    test "step functions receive correct input" do
      {:ok, _} = FlowBuilder.create_flow("input_test", Repo)
      {:ok, _} = FlowBuilder.add_step("input_test", "first", [], Repo)
      {:ok, _} = FlowBuilder.add_step("input_test", "second", ["first"], Repo)

      step_functions = %{
        first: fn input ->
          # Should receive initial input
          assert input.initial_value == "test"
          {:ok, Map.put(input, :first_output, "from_first")}
        end,
        second: fn input ->
          # Should receive output from first
          assert input.first_output == "from_first"
          {:ok, Map.put(input, :second_output, "from_second")}
        end
      }

      {:ok, result} = Executor.execute_dynamic(
        "input_test",
        %{initial_value: "test"},
        step_functions,
        Repo
      )

      assert result.initial_value == "test"
      assert result.first_output == "from_first"
      assert result.second_output == "from_second"
    end

    test "functions can access merged dependency outputs" do
      {:ok, _} = FlowBuilder.create_flow("merge_test", Repo)
      {:ok, _} = FlowBuilder.add_step("merge_test", "root", [], Repo)
      {:ok, _} = FlowBuilder.add_step("merge_test", "branch_a", ["root"], Repo)
      {:ok, _} = FlowBuilder.add_step("merge_test", "branch_b", ["root"], Repo)
      {:ok, _} = FlowBuilder.add_step("merge_test", "merge", ["branch_a", "branch_b"], Repo)

      step_functions = %{
        root: fn _input -> {:ok, %{root_data: "shared"}} end,
        branch_a: fn input -> {:ok, Map.put(input, :a_value, 1)} end,
        branch_b: fn input -> {:ok, Map.put(input, :b_value, 2)} end,
        merge: fn input ->
          # Should have outputs from both branches
          assert input.a_value == 1
          assert input.b_value == 2
          {:ok, Map.put(input, :merged, true)}
        end
      }

      {:ok, result} = Executor.execute_dynamic("merge_test", %{}, step_functions, Repo)

      assert result.a_value == 1
      assert result.b_value == 2
      assert result.merged == true
    end
  end

  describe "execute_dynamic/5 - Error handling" do
    test "handles missing step functions" do
      {:ok, _} = FlowBuilder.create_flow("missing_fn_test", Repo)
      {:ok, _} = FlowBuilder.add_step("missing_fn_test", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("missing_fn_test", "step2", ["step1"], Repo)

      # Only provide function for step1
      step_functions = %{
        step1: fn input -> {:ok, input} end
        # step2 is missing!
      }

      # Should fail during workflow loading
      result = Executor.execute_dynamic("missing_fn_test", %{}, step_functions, Repo)

      assert {:error, _reason} = result
    end

    test "handles step function errors" do
      {:ok, _} = FlowBuilder.create_flow("error_test", Repo)
      {:ok, _} = FlowBuilder.add_step("error_test", "failing_step", [], Repo)

      step_functions = %{
        failing_step: fn _input -> {:error, "intentional failure"} end
      }

      result = Executor.execute_dynamic("error_test", %{}, step_functions, Repo)

      assert {:error, _reason} = result

      # Verify workflow marked as failed
      run = Repo.one(WorkflowRun)
      assert run.status == "failed"
    end

    test "handles non-existent workflow" do
      step_functions = %{
        step1: fn input -> {:ok, input} end
      }

      result = Executor.execute_dynamic("nonexistent_workflow", %{}, step_functions, Repo)

      assert {:error, _reason} = result
    end

    test "handles step function exceptions" do
      {:ok, _} = FlowBuilder.create_flow("exception_test", Repo)
      {:ok, _} = FlowBuilder.add_step("exception_test", "crash", [], Repo)

      step_functions = %{
        crash: fn _input -> raise "intentional crash" end
      }

      result = Executor.execute_dynamic("exception_test", %{}, step_functions, Repo)

      assert {:error, _reason} = result
    end
  end

  describe "execute_dynamic/5 - Options" do
    test "accepts timeout option" do
      {:ok, _} = FlowBuilder.create_flow("timeout_test", Repo)
      {:ok, _} = FlowBuilder.add_step("timeout_test", "step", [], Repo)

      step_functions = %{
        step: fn input -> {:ok, Map.put(input, :done, true)} end
      }

      {:ok, _result} = Executor.execute_dynamic(
        "timeout_test",
        %{},
        step_functions,
        Repo,
        timeout: 60_000
      )

      run = Repo.one!(WorkflowRun)
      assert run.status == "completed"
    end

    test "accepts poll_interval option" do
      {:ok, _} = FlowBuilder.create_flow("poll_test", Repo)
      {:ok, _} = FlowBuilder.add_step("poll_test", "step", [], Repo)

      step_functions = %{
        step: fn input -> {:ok, input} end
      }

      {:ok, _result} = Executor.execute_dynamic(
        "poll_test",
        %{},
        step_functions,
        Repo,
        poll_interval: 50
      )

      run = Repo.one!(WorkflowRun)
      assert run.status == "completed"
    end

    test "accepts worker_id option" do
      {:ok, _} = FlowBuilder.create_flow("worker_test", Repo)
      {:ok, _} = FlowBuilder.add_step("worker_test", "step", [], Repo)

      step_functions = %{
        step: fn input -> {:ok, input} end
      }

      {:ok, _result} = Executor.execute_dynamic(
        "worker_test",
        %{},
        step_functions,
        Repo,
        worker_id: "test-worker-123"
      )

      run = Repo.one!(WorkflowRun)
      assert run.status == "completed"
    end
  end

  describe "execute_dynamic/5 - Database state" do
    test "creates workflow run in database" do
      {:ok, _} = FlowBuilder.create_flow("state_test", Repo)
      {:ok, _} = FlowBuilder.add_step("state_test", "step", [], Repo)

      step_functions = %{
        step: fn input -> {:ok, input} end
      }

      {:ok, _result} = Executor.execute_dynamic("state_test", %{test: true}, step_functions, Repo)

      run = Repo.one!(WorkflowRun)
      assert run.status == "completed"
      assert run.workflow_slug == "state_test"
      assert run.input == %{test: true}
    end

    test "creates step states for all steps" do
      {:ok, _} = FlowBuilder.create_flow("steps_test", Repo)
      {:ok, _} = FlowBuilder.add_step("steps_test", "step1", [], Repo)
      {:ok, _} = FlowBuilder.add_step("steps_test", "step2", ["step1"], Repo)
      {:ok, _} = FlowBuilder.add_step("steps_test", "step3", ["step2"], Repo)

      step_functions = %{
        step1: fn input -> {:ok, input} end,
        step2: fn input -> {:ok, input} end,
        step3: fn input -> {:ok, input} end
      }

      {:ok, _result} = Executor.execute_dynamic("steps_test", %{}, step_functions, Repo)

      run = Repo.one!(WorkflowRun)
      step_states = Repo.all(from(s in StepState, where: s.run_id == ^run.id))

      assert length(step_states) == 3
      assert Enum.all?(step_states, &(&1.status == "completed"))
    end

    test "saves final output to workflow run" do
      {:ok, _} = FlowBuilder.create_flow("output_test", Repo)
      {:ok, _} = FlowBuilder.add_step("output_test", "step", [], Repo)

      step_functions = %{
        step: fn _input -> {:ok, %{final: "result", count: 42}} end
      }

      {:ok, result} = Executor.execute_dynamic("output_test", %{}, step_functions, Repo)

      run = Repo.one!(WorkflowRun)
      assert run.output == result
      assert run.output.final == "result"
      assert run.output.count == 42
    end
  end

  describe "execute_dynamic/5 - Integration scenarios" do
    test "AI-generated workflow scenario" do
      # Simulate AI generating a custom workflow
      {:ok, _} = FlowBuilder.create_flow("ai_generated_analysis", Repo)
      {:ok, _} = FlowBuilder.add_step("ai_generated_analysis", "fetch_data", [], Repo)
      {:ok, _} = FlowBuilder.add_step("ai_generated_analysis", "preprocess", ["fetch_data"], Repo)
      {:ok, _} = FlowBuilder.add_step("ai_generated_analysis", "analyze", ["preprocess"], Repo)
      {:ok, _} = FlowBuilder.add_step("ai_generated_analysis", "generate_report", ["analyze"], Repo)

      step_functions = %{
        fetch_data: fn _input -> {:ok, %{data: [1, 2, 3, 4, 5]}} end,
        preprocess: fn input -> {:ok, Map.put(input, :preprocessed, true)} end,
        analyze: fn input ->
          data = Map.get(input, :data)
          avg = Enum.sum(data) / length(data)
          {:ok, Map.put(input, :average, avg)}
        end,
        generate_report: fn input ->
          report = "Analysis complete. Average: #{input.average}"
          {:ok, Map.put(input, :report, report)}
        end
      }

      {:ok, result} = Executor.execute_dynamic(
        "ai_generated_analysis",
        %{},
        step_functions,
        Repo
      )

      assert result.preprocessed == true
      assert result.average == 3.0
      assert result.report =~ "Average: 3.0"
    end

    test "dynamic workflow with map step" do
      {:ok, _} = FlowBuilder.create_flow("dynamic_map", Repo)
      {:ok, _} = FlowBuilder.add_step("dynamic_map", "prepare", [], Repo)
      {:ok, _} = FlowBuilder.add_step("dynamic_map", "process", ["prepare"], Repo,
        step_type: "map",
        initial_tasks: 5
      )
      {:ok, _} = FlowBuilder.add_step("dynamic_map", "collect", ["process"], Repo)

      step_functions = %{
        prepare: fn _input -> {:ok, %{items: [1, 2, 3, 4, 5]}} end,
        process: fn input ->
          item = Map.get(input, "item")
          {:ok, %{processed: item * 2}}
        end,
        collect: fn input -> {:ok, Map.put(input, :collection_done, true)} end
      }

      {:ok, result} = Executor.execute_dynamic("dynamic_map", %{}, step_functions, Repo)

      assert result.collection_done == true
    end

    test "multiple executions of same dynamic workflow" do
      {:ok, _} = FlowBuilder.create_flow("reusable_workflow", Repo)
      {:ok, _} = FlowBuilder.add_step("reusable_workflow", "process", [], Repo)

      step_functions = %{
        process: fn input -> {:ok, Map.update(input, :count, 1, &(&1 + 1))} end
      }

      # Run same workflow multiple times with different inputs
      {:ok, result1} = Executor.execute_dynamic(
        "reusable_workflow",
        %{count: 0},
        step_functions,
        Repo
      )

      {:ok, result2} = Executor.execute_dynamic(
        "reusable_workflow",
        %{count: 10},
        step_functions,
        Repo
      )

      {:ok, result3} = Executor.execute_dynamic(
        "reusable_workflow",
        %{count: 100},
        step_functions,
        Repo
      )

      assert result1.count == 1
      assert result2.count == 11
      assert result3.count == 101

      # Verify 3 separate runs
      runs = Repo.all(WorkflowRun)
      assert length(runs) == 3
      assert Enum.all?(runs, &(&1.status == "completed"))
    end
  end
end
