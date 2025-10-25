defmodule Pgflow.StepStateTest do
  use ExUnit.Case, async: true

  alias Pgflow.StepState

  @moduledoc """
  Chicago-style TDD: State-based testing for StepState schema.

  Focus on counter-based coordination logic - the heart of pgflow's DAG execution.
  Tests verify final state after operations, not implementation details.
  """

  describe "changeset/2 - valid data" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        run_id: Ecto.UUID.generate(),
        step_slug: "fetch_data",
        workflow_slug: "MyApp.DataWorkflow"
      }

      changeset = StepState.changeset(%StepState{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :run_id) != nil
      assert get_change(changeset, :step_slug) == "fetch_data"
      assert get_change(changeset, :workflow_slug) == "MyApp.DataWorkflow"
      # Status uses default value
    end

    test "accepts valid status: created" do
      attrs = valid_attrs(%{status: "created"})
      changeset = StepState.changeset(%StepState{}, attrs)

      assert changeset.valid?
    end

    test "accepts valid status: started" do
      attrs = valid_attrs(%{status: "started"})
      changeset = StepState.changeset(%StepState{}, attrs)

      assert changeset.valid?
    end

    test "accepts valid status: completed" do
      attrs = valid_attrs(%{status: "completed"})
      changeset = StepState.changeset(%StepState{}, attrs)

      assert changeset.valid?
    end

    test "accepts valid status: failed" do
      attrs = valid_attrs(%{status: "failed"})
      changeset = StepState.changeset(%StepState{}, attrs)

      assert changeset.valid?
    end

    test "accepts optional remaining_deps" do
      attrs = valid_attrs(%{remaining_deps: 3})
      changeset = StepState.changeset(%StepState{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :remaining_deps) == 3
    end

    test "accepts optional remaining_tasks" do
      attrs = valid_attrs(%{remaining_tasks: 5})
      changeset = StepState.changeset(%StepState{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :remaining_tasks) == 5
    end

    test "accepts optional initial_tasks" do
      attrs = valid_attrs(%{initial_tasks: 10})
      changeset = StepState.changeset(%StepState{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :initial_tasks) == 10
    end

    test "accepts zero remaining_deps" do
      attrs = valid_attrs(%{remaining_deps: 0})
      changeset = StepState.changeset(%StepState{}, attrs)

      assert changeset.valid?
    end
  end

  describe "changeset/2 - invalid data" do
    test "rejects missing run_id" do
      attrs = %{
        step_slug: "test",
        workflow_slug: "Test",
        status: "created"
      }

      changeset = StepState.changeset(%StepState{}, attrs)

      refute changeset.valid?
      assert %{run_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects missing step_slug" do
      attrs = %{
        run_id: Ecto.UUID.generate(),
        workflow_slug: "Test",
        status: "created"
      }

      changeset = StepState.changeset(%StepState{}, attrs)

      refute changeset.valid?
      assert %{step_slug: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects missing workflow_slug" do
      attrs = %{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        status: "created"
      }

      changeset = StepState.changeset(%StepState{}, attrs)

      refute changeset.valid?
      assert %{workflow_slug: ["can't be blank"]} = errors_on(changeset)
    end

    test "uses default status when not provided" do
      attrs = %{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test"
      }

      changeset = StepState.changeset(%StepState{}, attrs)

      # Status has default value, so changeset is valid
      assert changeset.valid?
      # Default status is "created"
      assert changeset.data.status == "created"
    end

    test "rejects invalid status value" do
      attrs = valid_attrs(%{status: "invalid_status"})
      changeset = StepState.changeset(%StepState{}, attrs)

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects negative remaining_deps" do
      attrs = valid_attrs(%{remaining_deps: -1})
      changeset = StepState.changeset(%StepState{}, attrs)

      refute changeset.valid?
      assert %{remaining_deps: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end
  end

  describe "mark_started/2 - critical coordination logic" do
    test "transitions step to started status" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "process_data",
        workflow_slug: "Test",
        status: "created",
        remaining_deps: 0
      }

      changeset = StepState.mark_started(step_state, 5)

      assert changeset.valid?
      assert get_change(changeset, :status) == "started"
    end

    test "sets initial_tasks from parameter" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "map_step",
        workflow_slug: "Test",
        status: "created"
      }

      changeset = StepState.mark_started(step_state, 42)

      assert get_change(changeset, :initial_tasks) == 42
    end

    test "sets remaining_tasks equal to initial_tasks" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "created"
      }

      changeset = StepState.mark_started(step_state, 7)

      assert get_change(changeset, :initial_tasks) == 7
      assert get_change(changeset, :remaining_tasks) == 7
    end

    test "sets started_at timestamp" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "created"
      }

      changeset = StepState.mark_started(step_state, 1)
      started_at = get_change(changeset, :started_at)

      assert started_at != nil
      assert %DateTime{} = started_at
      assert_in_delta DateTime.to_unix(started_at), DateTime.to_unix(DateTime.utc_now()), 2
    end

    test "works with single task step" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "single_task",
        workflow_slug: "Test",
        status: "created"
      }

      changeset = StepState.mark_started(step_state, 1)

      assert get_change(changeset, :initial_tasks) == 1
      assert get_change(changeset, :remaining_tasks) == 1
    end

    test "works with map step (multiple tasks)" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "map_items",
        workflow_slug: "Test",
        status: "created"
      }

      changeset = StepState.mark_started(step_state, 100)

      assert get_change(changeset, :initial_tasks) == 100
      assert get_change(changeset, :remaining_tasks) == 100
    end
  end

  describe "mark_completed/1" do
    test "transitions step to completed status" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started",
        remaining_tasks: 0
      }

      changeset = StepState.mark_completed(step_state)

      assert changeset.valid?
      assert get_change(changeset, :status) == "completed"
    end

    test "sets remaining_tasks to zero" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started",
        remaining_tasks: 5
      }

      changeset = StepState.mark_completed(step_state)

      assert get_change(changeset, :remaining_tasks) == 0
    end

    test "sets completed_at timestamp" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started"
      }

      changeset = StepState.mark_completed(step_state)
      completed_at = get_change(changeset, :completed_at)

      assert completed_at != nil
      assert %DateTime{} = completed_at
      assert_in_delta DateTime.to_unix(completed_at), DateTime.to_unix(DateTime.utc_now()), 2
    end
  end

  describe "mark_failed/2" do
    test "transitions step to failed status" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started"
      }

      changeset = StepState.mark_failed(step_state, "Database timeout")

      assert changeset.valid?
      assert get_change(changeset, :status) == "failed"
    end

    test "sets error_message" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started"
      }

      error_msg = "Task execution failed: network error"
      changeset = StepState.mark_failed(step_state, error_msg)

      assert get_change(changeset, :error_message) == error_msg
    end

    test "sets failed_at timestamp" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started"
      }

      changeset = StepState.mark_failed(step_state, "Error")
      failed_at = get_change(changeset, :failed_at)

      assert failed_at != nil
      assert %DateTime{} = failed_at
      assert_in_delta DateTime.to_unix(failed_at), DateTime.to_unix(DateTime.utc_now()), 2
    end
  end

  describe "decrement_remaining_deps/1 - critical counter logic" do
    test "decrements remaining_deps by 1" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "created",
        remaining_deps: 3
      }

      changeset = StepState.decrement_remaining_deps(step_state)

      assert get_change(changeset, :remaining_deps) == 2
    end

    test "does not go below zero" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "created",
        remaining_deps: 0
      }

      changeset = StepState.decrement_remaining_deps(step_state)

      # When already 0, changeset records 0 (clamped)
      assert apply_changes(changeset).remaining_deps == 0
      # Applying changes should still result in 0
      assert apply_changes(changeset).remaining_deps == 0
    end

    test "handles nil remaining_deps gracefully" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "created",
        remaining_deps: nil
      }

      changeset = StepState.decrement_remaining_deps(step_state)

      # Should treat nil as 0 and not go negative
      assert get_change(changeset, :remaining_deps) == 0
    end

    test "transition from 1 to 0 makes step ready to start" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "ready_step",
        workflow_slug: "Test",
        status: "created",
        remaining_deps: 1
      }

      changeset = StepState.decrement_remaining_deps(step_state)

      # When remaining_deps reaches 0, step becomes ready
      assert get_change(changeset, :remaining_deps) == 0
    end
  end

  describe "decrement_remaining_tasks/1 - critical counter logic" do
    test "decrements remaining_tasks by 1" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started",
        initial_tasks: 5,
        remaining_tasks: 5
      }

      changeset = StepState.decrement_remaining_tasks(step_state)

      assert get_change(changeset, :remaining_tasks) == 4
    end

    test "does not go below zero" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started",
        remaining_tasks: 0
      }

      changeset = StepState.decrement_remaining_tasks(step_state)

      # When already 0, value stays 0 (clamped)
      # Use apply_changes to see final result since get_change returns nil when value doesn't change
      assert apply_changes(changeset).remaining_tasks == 0
    end

    test "handles nil remaining_tasks gracefully" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started",
        remaining_tasks: nil
      }

      changeset = StepState.decrement_remaining_tasks(step_state)

      # Should treat nil as 0 and not go negative
      assert apply_changes(changeset).remaining_tasks == 0
    end

    test "transition from 1 to 0 makes step ready to complete" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "finishing_step",
        workflow_slug: "Test",
        status: "started",
        initial_tasks: 10,
        remaining_tasks: 1
      }

      changeset = StepState.decrement_remaining_tasks(step_state)

      # When remaining_tasks reaches 0, step is ready to be marked completed
      assert get_change(changeset, :remaining_tasks) == 0
    end

    test "multiple decrements work correctly" do
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started",
        remaining_tasks: 3
      }

      # Simulate 3 task completions
      changeset1 = StepState.decrement_remaining_tasks(step_state)
      step_state = Ecto.Changeset.apply_changes(changeset1)

      changeset2 = StepState.decrement_remaining_tasks(step_state)
      step_state = Ecto.Changeset.apply_changes(changeset2)

      changeset3 = StepState.decrement_remaining_tasks(step_state)

      assert get_change(changeset3, :remaining_tasks) == 0
    end
  end

  describe "schema defaults" do
    test "status defaults to 'created'" do
      step_state = %StepState{}
      assert step_state.status == "created"
    end

    test "remaining_deps defaults to 0" do
      step_state = %StepState{}
      assert step_state.remaining_deps == 0
    end

    test "attempts_count defaults to 0" do
      step_state = %StepState{}
      assert step_state.attempts_count == 0
    end

    test "remaining_tasks is nil by default" do
      step_state = %StepState{}
      assert step_state.remaining_tasks == nil
    end

    test "initial_tasks is nil by default" do
      step_state = %StepState{}
      assert step_state.initial_tasks == nil
    end
  end

  describe "associations" do
    test "belongs_to :run association defined" do
      associations = StepState.__schema__(:associations)
      assert :run in associations
    end

    test "has_many :tasks association defined" do
      associations = StepState.__schema__(:associations)
      assert :tasks in associations
    end

    test "run belongs_to uses correct foreign_key" do
      assoc = StepState.__schema__(:association, :run)
      assert assoc.owner_key == :run_id
      assert assoc.related_key == :id
    end

    test "tasks has_many uses correct keys" do
      assoc = StepState.__schema__(:association, :tasks)
      assert assoc.owner_key == :step_slug
      assert assoc.related_key == :step_slug
    end
  end

  describe "state transition scenarios" do
    test "typical single-task step lifecycle" do
      # Step starts created with no dependencies
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "single_task_step",
        workflow_slug: "Test",
        status: "created",
        remaining_deps: 0
      }

      # Start the step with 1 task
      started = step_state |> StepState.mark_started(1) |> apply_changes()
      assert started.status == "started"
      assert started.remaining_tasks == 1
      assert started.initial_tasks == 1

      # Complete the task
      completed = started |> StepState.decrement_remaining_tasks() |> apply_changes()
      assert completed.remaining_tasks == 0

      # Mark step completed
      final = completed |> StepState.mark_completed() |> apply_changes()
      assert final.status == "completed"
      assert final.remaining_tasks == 0
    end

    test "map step with multiple tasks lifecycle" do
      # Map step starts with dependencies
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "map_step",
        workflow_slug: "Test",
        status: "created",
        remaining_deps: 1
      }

      # Dependency completes
      deps_satisfied = step_state |> StepState.decrement_remaining_deps() |> apply_changes()
      assert deps_satisfied.remaining_deps == 0

      # Start with multiple tasks (e.g., processing 3 items)
      started = deps_satisfied |> StepState.mark_started(3) |> apply_changes()
      assert started.status == "started"
      assert started.remaining_tasks == 3

      # Complete tasks one by one
      after_task1 = started |> StepState.decrement_remaining_tasks() |> apply_changes()
      assert after_task1.remaining_tasks == 2

      after_task2 = after_task1 |> StepState.decrement_remaining_tasks() |> apply_changes()
      assert after_task2.remaining_tasks == 1

      after_task3 = after_task2 |> StepState.decrement_remaining_tasks() |> apply_changes()
      assert after_task3.remaining_tasks == 0

      # Mark completed
      final = after_task3 |> StepState.mark_completed() |> apply_changes()
      assert final.status == "completed"
    end

    test "step with multiple dependencies" do
      # Step waiting on 3 parent steps
      step_state = %StepState{
        run_id: Ecto.UUID.generate(),
        step_slug: "merge_step",
        workflow_slug: "Test",
        status: "created",
        remaining_deps: 3
      }

      # First parent completes
      after_dep1 = step_state |> StepState.decrement_remaining_deps() |> apply_changes()
      assert after_dep1.remaining_deps == 2
      assert after_dep1.status == "created"  # Still waiting

      # Second parent completes
      after_dep2 = after_dep1 |> StepState.decrement_remaining_deps() |> apply_changes()
      assert after_dep2.remaining_deps == 1
      assert after_dep2.status == "created"  # Still waiting

      # Third parent completes - now ready to start
      after_dep3 = after_dep2 |> StepState.decrement_remaining_deps() |> apply_changes()
      assert after_dep3.remaining_deps == 0
      # Status is still "created" but now eligible to transition to "started"
    end
  end

  # Helper functions
  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        run_id: Ecto.UUID.generate(),
        step_slug: "test_step",
        workflow_slug: "TestWorkflow",
        status: "created"
      },
      overrides
    )
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp get_change(changeset, field) do
    Ecto.Changeset.get_change(changeset, field)
  end

  defp apply_changes(changeset) do
    Ecto.Changeset.apply_changes(changeset)
  end
end
