defmodule Pgflow.WorkflowRunTest do
  use ExUnit.Case, async: true

  alias Pgflow.WorkflowRun

  @moduledoc """
  Chicago-style TDD: State-based testing for WorkflowRun schema.

  Tests focus on the final state of the struct/changeset after operations,
  not on implementation details or interactions.
  """

  describe "changeset/2 - valid data" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        workflow_slug: "MyApp.Workflows.Example",
        input: %{"user_id" => 123}
      }

      changeset = WorkflowRun.changeset(%WorkflowRun{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :workflow_slug) == "MyApp.Workflows.Example"
      assert get_change(changeset, :input) == %{"user_id" => 123}
      # Status and remaining_steps use defaults if not provided
    end

    test "accepts valid status: started" do
      attrs = %{workflow_slug: "Test", status: "started", input: %{}}
      changeset = WorkflowRun.changeset(%WorkflowRun{}, attrs)

      assert changeset.valid?
    end

    test "accepts valid status: completed" do
      attrs = %{workflow_slug: "Test", status: "completed", input: %{}}
      changeset = WorkflowRun.changeset(%WorkflowRun{}, attrs)

      assert changeset.valid?
    end

    test "accepts valid status: failed" do
      attrs = %{workflow_slug: "Test", status: "failed", input: %{}}
      changeset = WorkflowRun.changeset(%WorkflowRun{}, attrs)

      assert changeset.valid?
    end

    test "accepts optional output field" do
      attrs = %{
        workflow_slug: "Test",
        status: "completed",
        input: %{},
        output: %{"result" => "success"}
      }

      changeset = WorkflowRun.changeset(%WorkflowRun{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :output) == %{"result" => "success"}
    end

    test "accepts optional error_message field" do
      attrs = %{
        workflow_slug: "Test",
        status: "failed",
        input: %{},
        error_message: "Step X failed: timeout"
      }

      changeset = WorkflowRun.changeset(%WorkflowRun{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :error_message) == "Step X failed: timeout"
    end

    test "accepts zero remaining_steps" do
      attrs = %{
        workflow_slug: "Test",
        status: "completed",
        input: %{},
        remaining_steps: 0
      }

      changeset = WorkflowRun.changeset(%WorkflowRun{}, attrs)

      assert changeset.valid?
    end

    test "accepts positive remaining_steps" do
      attrs = %{
        workflow_slug: "Test",
        status: "started",
        input: %{},
        remaining_steps: 10
      }

      changeset = WorkflowRun.changeset(%WorkflowRun{}, attrs)

      assert changeset.valid?
    end
  end

  describe "changeset/2 - invalid data" do
    test "rejects missing workflow_slug" do
      attrs = %{status: "started", input: %{}}
      changeset = WorkflowRun.changeset(%WorkflowRun{}, attrs)

      refute changeset.valid?
      assert %{workflow_slug: ["can't be blank"]} = errors_on(changeset)
    end

    test "uses default status when not provided" do
      attrs = %{workflow_slug: "Test", input: %{}}
      changeset = WorkflowRun.changeset(%WorkflowRun{}, attrs)

      # Status has default, so changeset is valid
      assert changeset.valid?
      assert changeset.data.status == "started"
    end

    test "uses default input when not provided" do
      attrs = %{workflow_slug: "Test", status: "started"}
      changeset = WorkflowRun.changeset(%WorkflowRun{}, attrs)

      # Input has default empty map, so changeset is valid
      assert changeset.valid?
      assert changeset.data.input == %{}
    end

    test "rejects invalid status value" do
      attrs = %{workflow_slug: "Test", status: "invalid_status", input: %{}}
      changeset = WorkflowRun.changeset(%WorkflowRun{}, attrs)

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects negative remaining_steps" do
      attrs = %{
        workflow_slug: "Test",
        status: "started",
        input: %{},
        remaining_steps: -1
      }

      changeset = WorkflowRun.changeset(%WorkflowRun{}, attrs)

      refute changeset.valid?
      assert %{remaining_steps: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end
  end

  describe "mark_completed/2" do
    test "transitions run to completed status with output" do
      run = %WorkflowRun{
        id: Ecto.UUID.generate(),
        workflow_slug: "Test",
        status: "started",
        input: %{"user_id" => 123},
        remaining_steps: 0
      }

      output = %{"result" => "success", "items_processed" => 42}
      changeset = WorkflowRun.mark_completed(run, output)

      assert changeset.valid?
      assert get_change(changeset, :status) == "completed"
      assert get_change(changeset, :output) == output

      completed_at = get_change(changeset, :completed_at)
      assert completed_at != nil
      assert_in_delta DateTime.to_unix(completed_at), DateTime.to_unix(DateTime.utc_now()), 2
    end

    test "sets completed_at timestamp" do
      run = %WorkflowRun{
        workflow_slug: "Test",
        status: "started",
        input: %{}
      }

      changeset = WorkflowRun.mark_completed(run, %{})
      completed_at = get_change(changeset, :completed_at)

      assert completed_at != nil
      assert %DateTime{} = completed_at
    end

    test "preserves existing run data" do
      run = %WorkflowRun{
        id: Ecto.UUID.generate(),
        workflow_slug: "ImportantWorkflow",
        status: "started",
        input: %{"key" => "value"},
        remaining_steps: 0
      }

      changeset = WorkflowRun.mark_completed(run, %{"result" => "ok"})

      # Changeset should only include changes, not existing data
      assert get_change(changeset, :workflow_slug) == nil
      assert get_change(changeset, :input) == nil

      # But data field should still have original values
      assert changeset.data.workflow_slug == "ImportantWorkflow"
      assert changeset.data.input == %{"key" => "value"}
    end
  end

  describe "mark_failed/2" do
    test "transitions run to failed status with error message" do
      run = %WorkflowRun{
        workflow_slug: "Test",
        status: "started",
        input: %{}
      }

      error_msg = "Step 'process_payment' failed: insufficient funds"
      changeset = WorkflowRun.mark_failed(run, error_msg)

      assert changeset.valid?
      assert get_change(changeset, :status) == "failed"
      assert get_change(changeset, :error_message) == error_msg
    end

    test "sets failed_at timestamp" do
      run = %WorkflowRun{
        workflow_slug: "Test",
        status: "started",
        input: %{}
      }

      changeset = WorkflowRun.mark_failed(run, "Error occurred")
      failed_at = get_change(changeset, :failed_at)

      assert failed_at != nil
      assert %DateTime{} = failed_at
      assert_in_delta DateTime.to_unix(failed_at), DateTime.to_unix(DateTime.utc_now()), 2
    end

    test "preserves existing run data" do
      run = %WorkflowRun{
        id: Ecto.UUID.generate(),
        workflow_slug: "CriticalWorkflow",
        status: "started",
        input: %{"transaction_id" => "tx_123"}
      }

      changeset = WorkflowRun.mark_failed(run, "Database timeout")

      # Original data preserved
      assert changeset.data.workflow_slug == "CriticalWorkflow"
      assert changeset.data.input == %{"transaction_id" => "tx_123"}
    end
  end

  describe "schema defaults" do
    test "status defaults to 'started'" do
      run = %WorkflowRun{}
      assert run.status == "started"
    end

    test "input defaults to empty map" do
      run = %WorkflowRun{}
      assert run.input == %{}
    end

    test "remaining_steps defaults to 0" do
      run = %WorkflowRun{}
      assert run.remaining_steps == 0
    end

    test "output is nil by default" do
      run = %WorkflowRun{}
      assert run.output == nil
    end

    test "error_message is nil by default" do
      run = %WorkflowRun{}
      assert run.error_message == nil
    end
  end

  describe "type spec compliance" do
    test "id is binary_id (UUID)" do
      run = %WorkflowRun{id: Ecto.UUID.generate()}
      assert is_binary(run.id)
      # UUID format
      assert String.length(run.id) == 36
    end

    test "workflow_slug is string" do
      run = %WorkflowRun{workflow_slug: "MyApp.Workflow"}
      assert is_binary(run.workflow_slug)
    end

    test "status is string" do
      run = %WorkflowRun{status: "started"}
      assert is_binary(run.status)
    end

    test "input is map" do
      run = %WorkflowRun{input: %{"key" => "value"}}
      assert is_map(run.input)
    end

    test "output is map or nil" do
      run1 = %WorkflowRun{output: nil}
      assert run1.output == nil

      run2 = %WorkflowRun{output: %{"result" => "ok"}}
      assert is_map(run2.output)
    end

    test "remaining_steps is integer" do
      run = %WorkflowRun{remaining_steps: 5}
      assert is_integer(run.remaining_steps)
    end
  end

  describe "associations" do
    test "has_many :step_states association defined" do
      associations = WorkflowRun.__schema__(:associations)
      assert :step_states in associations
    end

    test "has_many :step_tasks association defined" do
      associations = WorkflowRun.__schema__(:associations)
      assert :step_tasks in associations
    end

    test "step_states uses correct foreign_key" do
      assoc = WorkflowRun.__schema__(:association, :step_states)
      assert assoc.owner_key == :id
      assert assoc.related_key == :run_id
    end

    test "step_tasks uses correct foreign_key" do
      assoc = WorkflowRun.__schema__(:association, :step_tasks)
      assert assoc.owner_key == :id
      assert assoc.related_key == :run_id
    end
  end

  # Helper to extract changeset errors into a map
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
end
