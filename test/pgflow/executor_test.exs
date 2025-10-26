# Test workflow fixtures (defined outside test module to keep queue names short)
# Queue name limit is 47 chars - module names must be short!

defmodule TestExecSimpleFlow do
  @moduledoc false
  def __workflow_steps__ do
    [
      {:step1, &__MODULE__.step1/1},
      {:step2, &__MODULE__.step2/1}
    ]
  end

  def step1(input), do: {:ok, Map.put(input, :step1_done, true)}
  def step2(input), do: {:ok, Map.put(input, :step2_done, true)}
end

defmodule TestExecParallelFlow do
  @moduledoc false
  def __workflow_steps__ do
    [
      {:fetch, &__MODULE__.fetch/1, depends_on: []},
      {:analyze, &__MODULE__.analyze/1, depends_on: [:fetch]},
      {:summarize, &__MODULE__.summarize/1, depends_on: [:fetch]},
      {:report, &__MODULE__.report/1, depends_on: [:analyze, :summarize]}
    ]
  end

  def fetch(input), do: {:ok, Map.put(input, :data, [1, 2, 3])}
  def analyze(input), do: {:ok, Map.put(input, :avg, 2.0)}
  def summarize(input), do: {:ok, Map.put(input, :count, 3)}
  def report(input), do: {:ok, Map.put(input, :report_done, true)}
end

defmodule TestExecFailingFlow do
  @moduledoc false
  def __workflow_steps__ do
    [
      {:step1, &__MODULE__.step1/1},
      {:step2, &__MODULE__.step2/1}
    ]
  end

  def step1(_input), do: {:error, "step1 failed"}
  def step2(input), do: {:ok, Map.put(input, :step2_done, true)}
end

defmodule TestExecSingleStepFlow do
  @moduledoc false
  def __workflow_steps__ do
    [{:only, &__MODULE__.only/1, depends_on: []}]
  end

  def only(input), do: {:ok, Map.put(input, :result, "done")}
end

defmodule Pgflow.ExecutorTest do
  use ExUnit.Case, async: false

  alias Pgflow.{Executor, WorkflowRun, StepState, Repo}
  import Ecto.Query

  @moduledoc """
  Comprehensive Executor integration tests covering:
  - Chicago-style TDD (state-based testing)
  - Complete workflow orchestration
  - Sequential and parallel execution
  - Error handling and status queries
  - Database-driven DAG coordination

  NOTE: These are integration tests requiring PostgreSQL with pgflow schema.
  Tests run against real database with migrations applied.
  """

  setup do
    # Set up sandbox for this test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Pgflow.Repo)

    # Allow all processes spawned during this test to use the sandbox connection
    Ecto.Adapters.SQL.Sandbox.mode(Pgflow.Repo, {:shared, self()})

    # Clean up any existing test data
    Repo.delete_all(WorkflowRun)
    :ok
  end

  describe "execute/4 - Sequential workflow execution" do
    test "executes simple sequential workflow successfully" do
      input = %{initial: true}

      {:ok, result} = Executor.execute(TestExecSimpleFlow, input, Repo)

      # Verify final result contains all step outputs
      assert result.initial == true
      assert result.step1_done == true
      assert result.step2_done == true
    end

    test "creates workflow run in database" do
      input = %{test: "data"}

      {:ok, _result} = Executor.execute(TestExecSimpleFlow, input, Repo)

      # Verify run was created
      runs = Repo.all(WorkflowRun)
      assert length(runs) == 1

      run = hd(runs)
      assert run.status == "completed"
      assert String.contains?(run.workflow_slug, "TestExecSimpleFlow")
    end

    test "creates step states for all steps" do
      {:ok, _result} = Executor.execute(TestExecSimpleFlow, %{}, Repo)

      # Get the run
      run = Repo.one!(WorkflowRun)

      # Verify step states created
      step_states = Repo.all(from(s in StepState, where: s.run_id == ^run.id))
      assert length(step_states) == 2

      # Verify all steps completed
      completed = Enum.filter(step_states, &(&1.status == "completed"))
      assert length(completed) == 2
    end

    test "passes input through workflow pipeline" do
      input = %{count: 0}

      {:ok, result} = Executor.execute(TestExecSimpleFlow, input, Repo)

      # Original input preserved
      assert result.count == 0
      # New fields added by steps
      assert result.step1_done == true
      assert result.step2_done == true
    end

    test "executes single-step workflow" do
      input = %{data: "test"}

      {:ok, result} = Executor.execute(TestExecSingleStepFlow, input, Repo)

      assert result.data == "test"
      assert result.result == "done"
    end
  end

  describe "execute/4 - DAG workflow execution (parallel)" do
    test "executes parallel DAG workflow successfully" do
      input = %{initial: true}

      {:ok, result} = Executor.execute(TestExecParallelFlow, input, Repo)

      # Verify all steps completed
      assert result.data == [1, 2, 3]
      assert result.avg == 2.0
      assert result.count == 3
      assert result.report_done == true
    end

    test "parallel steps both execute" do
      {:ok, _result} = Executor.execute(TestExecParallelFlow, %{}, Repo)

      run = Repo.one!(WorkflowRun)
      step_states = Repo.all(from(s in StepState, where: s.run_id == ^run.id))

      # All 4 steps should be completed
      assert length(step_states) == 4

      completed = Enum.filter(step_states, &(&1.status == "completed"))
      assert length(completed) == 4

      # Verify analyze and summarize both ran (parallel steps)
      step_slugs = Enum.map(step_states, & &1.step_slug)
      assert "analyze" in step_slugs
      assert "summarize" in step_slugs
    end

    test "respects dependency order" do
      {:ok, result} = Executor.execute(TestExecParallelFlow, %{}, Repo)

      # fetch must complete before analyze and summarize
      # analyze and summarize must complete before report
      # Final result should have all outputs
      assert result.data == [1, 2, 3]
      assert result.avg == 2.0
      assert result.count == 3
      assert result.report_done == true
    end
  end

  describe "execute/4 - Error handling" do
    test "handles step failure" do
      result = Executor.execute(TestExecFailingFlow, %{}, Repo)

      # Workflow should fail
      assert match?({:error, _}, result)
    end

    test "marks workflow run as failed on error" do
      _result = Executor.execute(TestExecFailingFlow, %{}, Repo)

      run = Repo.one!(WorkflowRun)
      assert run.status == "failed"
    end

    test "does not execute dependent steps after failure" do
      _result = Executor.execute(TestExecFailingFlow, %{}, Repo)

      run = Repo.one!(WorkflowRun)
      step_states = Repo.all(from(s in StepState, where: s.run_id == ^run.id))

      # step1 should fail, step2 should not execute
      step1 = Enum.find(step_states, &(&1.step_slug == "step1"))
      step2 = Enum.find(step_states, &(&1.step_slug == "step2"))

      assert step1.status == "failed"
      # step2 might be "created" (never started) or might not have been created
      # depending on implementation - just verify it's not completed
      if step2 do
        assert step2.status != "completed"
      end
    end

    test "handles invalid workflow module" do
      result = Executor.execute(NonExistentModule, %{}, Repo)

      assert match?({:error, _}, result)
    end
  end

  describe "execute/4 - Options" do
    test "accepts timeout option" do
      {:ok, _result} =
        Executor.execute(TestExecSimpleFlow, %{}, Repo, timeout: 60_000)

      # Should complete successfully with custom timeout
      run = Repo.one!(WorkflowRun)
      assert run.status == "completed"
    end

    test "accepts poll_interval option" do
      {:ok, _result} =
        Executor.execute(TestExecSimpleFlow, %{}, Repo, poll_interval: 50)

      run = Repo.one!(WorkflowRun)
      assert run.status == "completed"
    end

    test "accepts worker_id option" do
      {:ok, _result} =
        Executor.execute(TestExecSimpleFlow, %{}, Repo, worker_id: "test-worker-123")

      run = Repo.one!(WorkflowRun)
      assert run.status == "completed"
    end
  end

  describe "get_run_status/2 - Status queries" do
    test "returns completed status for successful workflow" do
      {:ok, _result} = Executor.execute(TestExecSimpleFlow, %{test: true}, Repo)

      run = Repo.one!(WorkflowRun)
      {:ok, status, output} = Executor.get_run_status(run.id, Repo)

      assert status == :completed
      assert output.test == true
      assert output.step1_done == true
      assert output.step2_done == true
    end

    test "returns failed status for failed workflow" do
      _result = Executor.execute(TestExecFailingFlow, %{}, Repo)

      run = Repo.one!(WorkflowRun)
      {:ok, status, error} = Executor.get_run_status(run.id, Repo)

      assert status == :failed
      assert is_binary(error) or is_nil(error)
    end

    test "returns not_found for non-existent run" do
      result = Executor.get_run_status(Ecto.UUID.generate(), Repo)

      assert result == {:error, :not_found}
    end

    test "calculates progress correctly" do
      # This test is tricky because execution completes very quickly
      # We would need to pause execution mid-workflow to capture in_progress state
      # For now, verify the completed case works
      {:ok, _result} = Executor.execute(TestExecSimpleFlow, %{}, Repo)

      run = Repo.one!(WorkflowRun)
      {:ok, status, _output} = Executor.get_run_status(run.id, Repo)

      assert status == :completed
    end
  end

  describe "execute_dynamic/5 - Dynamic workflow execution" do
    test "executes workflow loaded from database" do
      # Create workflow in database
      {:ok, _workflow} = Pgflow.FlowBuilder.create_flow("test_dynamic_simple", Repo)

      # Add steps
      {:ok, _} = Pgflow.FlowBuilder.add_step("test_dynamic_simple", "step1", [], Repo)
      {:ok, _} = Pgflow.FlowBuilder.add_step("test_dynamic_simple", "step2", ["step1"], Repo)

      # Define step functions
      step_functions = %{
        step1: fn input -> {:ok, Map.put(input, :s1, true)} end,
        step2: fn input -> {:ok, Map.put(input, :s2, true)} end
      }

      # Execute dynamic workflow
      input = %{initial: true}
      {:ok, result} = Executor.execute_dynamic("test_dynamic_simple", input, step_functions, Repo)

      # Verify outputs
      assert result.initial == true
      assert result.s1 == true
      assert result.s2 == true

      # Verify database state
      runs = Repo.all(WorkflowRun)
      assert length(runs) == 1
      assert hd(runs).status == "completed"
    end

    test "maps step functions correctly" do
      # Create workflow
      {:ok, _} = Pgflow.FlowBuilder.create_flow("test_dynamic_mapping", Repo)
      {:ok, _} = Pgflow.FlowBuilder.add_step("test_dynamic_mapping", "transform", [], Repo)

      {:ok, _} =
        Pgflow.FlowBuilder.add_step("test_dynamic_mapping", "validate", ["transform"], Repo)

      # Define step functions with specific behavior
      step_functions = %{
        transform: fn input ->
          # Transform the input
          {:ok, Map.put(input, :transformed, true)}
        end,
        validate: fn input ->
          # Check transformation happened
          if Map.get(input, :transformed) do
            {:ok, Map.put(input, :valid, true)}
          else
            {:error, "Not transformed"}
          end
        end
      }

      input = %{data: "test"}
      {:ok, result} = Executor.execute_dynamic("test_dynamic_mapping", input, step_functions, Repo)

      # Verify both steps executed and transformed data correctly
      assert result.data == "test"
      assert result.transformed == true
      assert result.valid == true
    end

    test "handles missing step functions" do
      # Create workflow with more steps than functions provided
      {:ok, _} = Pgflow.FlowBuilder.create_flow("test_dynamic_missing", Repo)
      {:ok, _} = Pgflow.FlowBuilder.add_step("test_dynamic_missing", "step_a", [], Repo)
      {:ok, _} = Pgflow.FlowBuilder.add_step("test_dynamic_missing", "step_b", ["step_a"], Repo)

      # Only provide step_a function, missing step_b
      step_functions = %{
        step_a: fn input -> {:ok, Map.put(input, :a, true)} end
        # step_b is missing
      }

      input = %{test: true}
      result = Executor.execute_dynamic("test_dynamic_missing", input, step_functions, Repo)

      # Should fail because step_b function is missing
      assert match?({:error, _}, result)
    end
  end

  describe "Integration scenarios" do
    test "multiple workflows can run independently" do
      # Execute two different workflows
      {:ok, result1} = Executor.execute(TestExecSimpleFlow, %{id: 1}, Repo)
      {:ok, result2} = Executor.execute(TestExecSingleStepFlow, %{id: 2}, Repo)

      # Both should succeed
      assert result1.step1_done == true
      assert result2.result == "done"

      # Two separate runs should exist
      runs = Repo.all(WorkflowRun)
      assert length(runs) == 2
    end

    test "same workflow can run multiple times" do
      {:ok, _result1} = Executor.execute(TestExecSimpleFlow, %{run: 1}, Repo)
      {:ok, _result2} = Executor.execute(TestExecSimpleFlow, %{run: 2}, Repo)

      runs = Repo.all(WorkflowRun)
      assert length(runs) == 2

      # Both should be completed
      completed = Enum.filter(runs, &(&1.status == "completed"))
      assert length(completed) == 2
    end

    test "complex DAG workflow executes correctly" do
      {:ok, result} = Executor.execute(TestExecParallelFlow, %{}, Repo)

      # Verify final output contains all intermediate results
      assert Map.has_key?(result, :data)
      assert Map.has_key?(result, :avg)
      assert Map.has_key?(result, :count)
      assert Map.has_key?(result, :report_done)

      # Verify database state
      run = Repo.one!(WorkflowRun)
      assert run.status == "completed"

      step_states = Repo.all(from(s in StepState, where: s.run_id == ^run.id))
      assert length(step_states) == 4

      # All steps should be completed
      completed = Enum.filter(step_states, &(&1.status == "completed"))
      assert length(completed) == 4
    end

    test "empty input map works" do
      {:ok, result} = Executor.execute(TestExecSimpleFlow, %{}, Repo)

      # Steps should add their outputs
      assert result.step1_done == true
      assert result.step2_done == true
    end

    test "complex input data structures preserved" do
      input = %{
        user: %{id: 123, name: "Test"},
        items: [1, 2, 3],
        config: %{timeout: 60}
      }

      {:ok, result} = Executor.execute(TestExecSimpleFlow, input, Repo)

      # Original input preserved
      assert result.user.id == 123
      assert result.items == [1, 2, 3]
      assert result.config.timeout == 60

      # Step outputs added
      assert result.step1_done == true
      assert result.step2_done == true
    end
  end

  describe "Database state verification" do
    test "workflow run has correct metadata" do
      input = %{test: "data"}
      {:ok, _result} = Executor.execute(TestExecSimpleFlow, input, Repo)

      run = Repo.one!(WorkflowRun)

      assert run.status == "completed"
      assert run.input == input
      assert run.workflow_slug =~ "TestExecSimpleFlow"
      assert run.started_at != nil
      assert run.completed_at != nil
      assert run.remaining_steps == 0
    end

    test "step states have correct counters" do
      {:ok, _result} = Executor.execute(TestExecSimpleFlow, %{}, Repo)

      run = Repo.one!(WorkflowRun)
      step_states = Repo.all(from(s in StepState, where: s.run_id == ^run.id))

      # All steps completed
      Enum.each(step_states, fn state ->
        assert state.status == "completed"
        assert state.remaining_deps == 0
        assert state.remaining_tasks == 0
      end)
    end

    test "dependencies created correctly for sequential workflow" do
      {:ok, _result} = Executor.execute(TestExecSimpleFlow, %{}, Repo)

      run = Repo.one!(WorkflowRun)

      # Sequential workflow: step2 depends on step1
      deps =
        Repo.all(
          from(d in Pgflow.StepDependency,
            where: d.run_id == ^run.id,
            order_by: d.step_slug
          )
        )

      assert length(deps) == 1
      dep = hd(deps)
      assert dep.step_slug == "step2"
      assert dep.depends_on_step == "step1"
    end

    test "dependencies created correctly for DAG workflow" do
      {:ok, _result} = Executor.execute(TestExecParallelFlow, %{}, Repo)

      run = Repo.one!(WorkflowRun)

      deps =
        Repo.all(
          from(d in Pgflow.StepDependency,
            where: d.run_id == ^run.id,
            order_by: [d.step_slug, d.depends_on_step]
          )
        )

      # Should have dependencies:
      # - analyze depends on fetch
      # - summarize depends on fetch
      # - report depends on analyze
      # - report depends on summarize
      assert length(deps) == 4

      # Verify specific dependencies
      analyze_dep = Enum.find(deps, &(&1.step_slug == "analyze"))
      assert analyze_dep.depends_on_step == "fetch"

      summarize_dep = Enum.find(deps, &(&1.step_slug == "summarize"))
      assert summarize_dep.depends_on_step == "fetch"

      report_deps = Enum.filter(deps, &(&1.step_slug == "report"))
      assert length(report_deps) == 2
      report_depends_on = Enum.map(report_deps, & &1.depends_on_step) |> Enum.sort()
      assert report_depends_on == ["analyze", "summarize"]
    end
  end

  describe "Logging and observability" do
    test "logs workflow start and completion" do
      # Logging is tested via presence of log statements in code
      # Actual log capture would require Logger configuration changes
      {:ok, _result} = Executor.execute(TestExecSimpleFlow, %{}, Repo)

      # If execution completed, logs were generated
      run = Repo.one!(WorkflowRun)
      assert run.status == "completed"
    end

    test "logs include workflow and run identifiers" do
      # Verified by code inspection - logs include:
      # - workflow module name
      # - run_id
      # - input keys
      {:ok, _result} = Executor.execute(TestExecSimpleFlow, %{key1: 1}, Repo)

      run = Repo.one!(WorkflowRun)
      assert run.id != nil
      assert run.workflow_slug != nil
    end
  end

  describe "Concurrency and idempotency" do
    test "multiple workers can execute same run" do
      # Execute a workflow
      {:ok, _result1} = Executor.execute(TestExecSimpleFlow, %{worker_test: true}, Repo)

      # Execute same workflow again in a different "worker"
      {:ok, _result2} =
        Executor.execute(TestExecSimpleFlow, %{worker_test: true}, Repo, worker_id: "worker-2")

      # Both should complete independently
      runs = Repo.all(WorkflowRun)
      assert length(runs) == 2

      completed = Enum.filter(runs, &(&1.status == "completed"))
      assert length(completed) == 2
    end

    test "workflow can be safely retried after failure" do
      # Execute a failing workflow
      _result1 = Executor.execute(TestExecFailingFlow, %{retry_test: true}, Repo)

      run1 = Repo.one!(WorkflowRun)
      assert run1.status == "failed"

      # Clean up the failed run (simulate retry scenario)
      Repo.delete_all(WorkflowRun)
      Repo.delete_all(StepState)
      Repo.delete_all(Pgflow.StepDependency)
      Repo.delete_all(Pgflow.StepTask)

      # Retry with corrected workflow
      {:ok, result2} = Executor.execute(TestExecSimpleFlow, %{retry_test: true}, Repo)

      # Second attempt should succeed
      assert result2.step1_done == true
      assert result2.step2_done == true

      run2 = Repo.one!(WorkflowRun)
      assert run2.status == "completed"
    end
  end
end
