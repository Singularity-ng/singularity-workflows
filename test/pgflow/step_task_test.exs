defmodule Pgflow.StepTaskTest do
  use ExUnit.Case, async: true

  alias Pgflow.StepTask

  @moduledoc """
  Chicago-style TDD: State-based testing for StepTask schema.

  Focuses on task lifecycle: queued → claimed → started → completed/failed → requeued
  Tests verify final state after operations, including retry logic.
  """

  describe "changeset/2 - valid data" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        run_id: Ecto.UUID.generate(),
        step_slug: "process_payment",
        workflow_slug: "PaymentWorkflow"
      }

      changeset = StepTask.changeset(%StepTask{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :run_id) != nil
      assert get_change(changeset, :step_slug) == "process_payment"
      assert get_change(changeset, :workflow_slug) == "PaymentWorkflow"
      # task_index and status use default values
    end

    test "accepts valid status: queued" do
      attrs = valid_attrs(%{status: "queued"})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      assert changeset.valid?
    end

    test "accepts valid status: started" do
      attrs = valid_attrs(%{status: "started"})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      assert changeset.valid?
    end

    test "accepts valid status: completed" do
      attrs = valid_attrs(%{status: "completed"})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      assert changeset.valid?
    end

    test "accepts valid status: failed" do
      attrs = valid_attrs(%{status: "failed"})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      assert changeset.valid?
    end

    test "accepts task_index 0 (single task or first map task)" do
      attrs = valid_attrs(%{task_index: 0})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      assert changeset.valid?
    end

    test "accepts positive task_index (map task elements)" do
      attrs = valid_attrs(%{task_index: 5})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :task_index) == 5
    end

    test "accepts optional input map" do
      attrs = valid_attrs(%{input: %{"user_id" => 123, "amount" => 100.50}})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :input) == %{"user_id" => 123, "amount" => 100.50}
    end

    test "accepts optional output map" do
      attrs = valid_attrs(%{output: %{"receipt_id" => "REC-123"}})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      assert changeset.valid?
    end

    test "accepts optional error_message" do
      attrs = valid_attrs(%{error_message: "Connection timeout"})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      assert changeset.valid?
    end

    test "accepts custom max_attempts" do
      attrs = valid_attrs(%{max_attempts: 5})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :max_attempts) == 5
    end
  end

  describe "changeset/2 - invalid data" do
    test "rejects missing run_id" do
      attrs = %{
        step_slug: "test",
        workflow_slug: "Test",
        status: "queued"
      }

      changeset = StepTask.changeset(%StepTask{}, attrs)

      refute changeset.valid?
      assert %{run_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects missing step_slug" do
      attrs = %{
        run_id: Ecto.UUID.generate(),
        workflow_slug: "Test",
        status: "queued"
      }

      changeset = StepTask.changeset(%StepTask{}, attrs)

      refute changeset.valid?
      assert %{step_slug: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects missing workflow_slug" do
      attrs = %{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        status: "queued"
      }

      changeset = StepTask.changeset(%StepTask{}, attrs)

      refute changeset.valid?
      assert %{workflow_slug: ["can't be blank"]} = errors_on(changeset)
    end

    test "uses default status when not provided" do
      attrs = %{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test"
      }

      changeset = StepTask.changeset(%StepTask{}, attrs)

      # Status has default value, so changeset is valid
      assert changeset.valid?
      assert changeset.data.status == "queued"
    end

    test "rejects invalid status value" do
      attrs = valid_attrs(%{status: "invalid_status"})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects negative task_index" do
      attrs = valid_attrs(%{task_index: -1})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      refute changeset.valid?
      assert %{task_index: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "rejects negative attempts_count" do
      attrs = valid_attrs(%{attempts_count: -1})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      refute changeset.valid?
      assert %{attempts_count: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "rejects zero or negative max_attempts" do
      attrs = valid_attrs(%{max_attempts: 0})
      changeset = StepTask.changeset(%StepTask{}, attrs)

      refute changeset.valid?
      assert %{max_attempts: ["must be greater than 0"]} = errors_on(changeset)
    end
  end

  describe "claim/2 - worker claims task" do
    test "transitions task to started status" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "queued",
        attempts_count: 0
      }

      changeset = StepTask.claim(task, "worker-123")

      assert get_change(changeset, :status) == "started"
    end

    test "sets claimed_by to worker_id" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "queued"
      }

      changeset = StepTask.claim(task, "worker-abc")

      assert get_change(changeset, :claimed_by) == "worker-abc"
    end

    test "sets claimed_at timestamp" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "queued"
      }

      changeset = StepTask.claim(task, "worker-1")
      claimed_at = get_change(changeset, :claimed_at)

      assert claimed_at != nil
      assert %DateTime{} = claimed_at
      assert_in_delta DateTime.to_unix(claimed_at), DateTime.to_unix(DateTime.utc_now()), 2
    end

    test "sets started_at timestamp" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "queued"
      }

      changeset = StepTask.claim(task, "worker-1")
      started_at = get_change(changeset, :started_at)

      assert started_at != nil
      assert %DateTime{} = started_at
    end

    test "increments attempts_count" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "queued",
        attempts_count: 0
      }

      changeset = StepTask.claim(task, "worker-1")

      assert get_change(changeset, :attempts_count) == 1
    end

    test "increments attempts_count on retry" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "queued",
        attempts_count: 2
      }

      changeset = StepTask.claim(task, "worker-retry")

      assert get_change(changeset, :attempts_count) == 3
    end

    test "handles nil attempts_count gracefully" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "queued",
        attempts_count: nil
      }

      changeset = StepTask.claim(task, "worker-1")

      assert get_change(changeset, :attempts_count) == 1
    end
  end

  describe "mark_completed/2" do
    test "transitions task to completed status" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started"
      }

      changeset = StepTask.mark_completed(task, %{"result" => "success"})

      assert get_change(changeset, :status) == "completed"
    end

    test "sets output map" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started"
      }

      output = %{"items_processed" => 42, "elapsed_ms" => 1234}
      changeset = StepTask.mark_completed(task, output)

      assert get_change(changeset, :output) == output
    end

    test "sets completed_at timestamp" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started"
      }

      changeset = StepTask.mark_completed(task, %{})
      completed_at = get_change(changeset, :completed_at)

      assert completed_at != nil
      assert %DateTime{} = completed_at
      assert_in_delta DateTime.to_unix(completed_at), DateTime.to_unix(DateTime.utc_now()), 2
    end

    test "preserves existing task data" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "important_task",
        workflow_slug: "CriticalFlow",
        status: "started",
        input: %{"key" => "value"}
      }

      changeset = StepTask.mark_completed(task, %{"result" => "ok"})

      # Original data preserved
      assert changeset.data.step_slug == "important_task"
      assert changeset.data.input == %{"key" => "value"}
    end
  end

  describe "mark_failed/2" do
    test "transitions task to failed status" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started"
      }

      changeset = StepTask.mark_failed(task, "Network timeout")

      assert get_change(changeset, :status) == "failed"
    end

    test "sets error_message" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started"
      }

      error_msg = "Database connection lost: timeout after 30s"
      changeset = StepTask.mark_failed(task, error_msg)

      assert get_change(changeset, :error_message) == error_msg
    end

    test "sets failed_at timestamp" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "started"
      }

      changeset = StepTask.mark_failed(task, "Error occurred")
      failed_at = get_change(changeset, :failed_at)

      assert failed_at != nil
      assert %DateTime{} = failed_at
      assert_in_delta DateTime.to_unix(failed_at), DateTime.to_unix(DateTime.utc_now()), 2
    end
  end

  describe "requeue/1 - retry logic" do
    test "transitions task back to queued status" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "failed",
        claimed_by: "worker-1",
        claimed_at: DateTime.utc_now()
      }

      changeset = StepTask.requeue(task)

      assert get_change(changeset, :status) == "queued"
    end

    test "clears claimed_by" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "failed",
        claimed_by: "worker-123"
      }

      changeset = StepTask.requeue(task)

      assert get_change(changeset, :claimed_by) == nil
    end

    test "clears claimed_at" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "failed",
        claimed_at: DateTime.utc_now()
      }

      changeset = StepTask.requeue(task)

      assert get_change(changeset, :claimed_at) == nil
    end

    test "preserves attempts_count (used by can_retry?)" do
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        workflow_slug: "Test",
        status: "failed",
        attempts_count: 2,
        claimed_by: "worker-1"
      }

      changeset = StepTask.requeue(task)

      # attempts_count should NOT be changed (it's incremented on next claim)
      assert get_change(changeset, :attempts_count) == nil
      assert changeset.data.attempts_count == 2
    end
  end

  describe "can_retry?/1 - retry eligibility" do
    test "returns true when attempts below max_attempts" do
      task = %StepTask{attempts_count: 2, max_attempts: 3}

      assert StepTask.can_retry?(task) == true
    end

    test "returns false when attempts equal max_attempts" do
      task = %StepTask{attempts_count: 3, max_attempts: 3}

      assert StepTask.can_retry?(task) == false
    end

    test "returns false when attempts exceed max_attempts" do
      task = %StepTask{attempts_count: 5, max_attempts: 3}

      assert StepTask.can_retry?(task) == false
    end

    test "returns true when attempts_count is nil (first attempt)" do
      task = %StepTask{attempts_count: nil, max_attempts: 3}

      assert StepTask.can_retry?(task) == true
    end

    test "returns true when max_attempts is nil (defaults to 3)" do
      task = %StepTask{attempts_count: 2, max_attempts: nil}

      assert StepTask.can_retry?(task) == true
    end

    test "returns false when both nil and would exceed default" do
      task = %StepTask{attempts_count: nil, max_attempts: nil}

      # nil attempts_count is treated as 0, nil max_attempts as 3
      assert StepTask.can_retry?(task) == true
    end

    test "boundary: exactly 1 attempt remaining" do
      task = %StepTask{attempts_count: 2, max_attempts: 3}

      assert StepTask.can_retry?(task) == true
    end

    test "boundary: no attempts remaining" do
      task = %StepTask{attempts_count: 3, max_attempts: 3}

      assert StepTask.can_retry?(task) == false
    end
  end

  describe "schema defaults" do
    test "status defaults to 'queued'" do
      task = %StepTask{}
      assert task.status == "queued"
    end

    test "task_index defaults to 0" do
      task = %StepTask{}
      assert task.task_index == 0
    end

    test "attempts_count defaults to 0" do
      task = %StepTask{}
      assert task.attempts_count == 0
    end

    test "max_attempts defaults to 3" do
      task = %StepTask{}
      assert task.max_attempts == 3
    end

    test "input is nil by default" do
      task = %StepTask{}
      assert task.input == nil
    end

    test "output is nil by default" do
      task = %StepTask{}
      assert task.output == nil
    end

    test "claimed_by is nil by default" do
      task = %StepTask{}
      assert task.claimed_by == nil
    end
  end

  describe "associations" do
    test "belongs_to :run association defined" do
      associations = StepTask.__schema__(:associations)
      assert :run in associations
    end

    test "belongs_to :step_state association defined" do
      associations = StepTask.__schema__(:associations)
      assert :step_state in associations
    end

    test "run belongs_to uses correct foreign_key" do
      assoc = StepTask.__schema__(:association, :run)
      assert assoc.owner_key == :run_id
      assert assoc.related_key == :id
    end

    test "step_state belongs_to uses correct keys" do
      assoc = StepTask.__schema__(:association, :step_state)
      assert assoc.owner_key == :step_slug
      assert assoc.related_key == :step_slug
    end
  end

  describe "task lifecycle scenarios" do
    test "successful single-attempt task" do
      # Task starts queued
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "simple_task",
        workflow_slug: "Test",
        status: "queued",
        attempts_count: 0,
        max_attempts: 3
      }

      # Worker claims task
      claimed = task |> StepTask.claim("worker-1") |> apply_changes()
      assert claimed.status == "started"
      assert claimed.attempts_count == 1
      assert claimed.claimed_by == "worker-1"

      # Task completes successfully
      completed = claimed |> StepTask.mark_completed(%{"result" => "ok"}) |> apply_changes()
      assert completed.status == "completed"
      assert completed.output == %{"result" => "ok"}
    end

    test "task fails and retries successfully" do
      # Task starts queued
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "retry_task",
        workflow_slug: "Test",
        status: "queued",
        attempts_count: 0,
        max_attempts: 3
      }

      # First attempt fails
      claimed1 = task |> StepTask.claim("worker-1") |> apply_changes()
      assert claimed1.attempts_count == 1
      assert StepTask.can_retry?(claimed1) == true

      failed1 = claimed1 |> StepTask.mark_failed("Timeout") |> apply_changes()
      assert failed1.status == "failed"

      # Requeue for retry
      requeued = failed1 |> StepTask.requeue() |> apply_changes()
      assert requeued.status == "queued"
      assert requeued.claimed_by == nil
      # Preserved for next claim
      assert requeued.attempts_count == 1

      # Second attempt succeeds
      claimed2 = requeued |> StepTask.claim("worker-2") |> apply_changes()
      assert claimed2.attempts_count == 2

      completed = claimed2 |> StepTask.mark_completed(%{"retry_success" => true}) |> apply_changes()
      assert completed.status == "completed"
    end

    test "task exhausts retries and stays failed" do
      # Task with 2 attempts already
      task = %StepTask{
        run_id: Ecto.UUID.generate(),
        step_slug: "exhausted_task",
        workflow_slug: "Test",
        status: "queued",
        attempts_count: 2,
        max_attempts: 3
      }

      # Third attempt fails
      claimed = task |> StepTask.claim("worker-1") |> apply_changes()
      assert claimed.attempts_count == 3

      failed = claimed |> StepTask.mark_failed("Permanent error") |> apply_changes()
      assert failed.status == "failed"

      # Can't retry - exhausted attempts
      assert StepTask.can_retry?(failed) == false
    end

    test "map step with multiple parallel tasks" do
      run_id = Ecto.UUID.generate()
      step_slug = "map_items"
      workflow_slug = "MapWorkflow"

      # Create 3 tasks for map step
      tasks =
        for i <- 0..2 do
          %StepTask{
            run_id: run_id,
            step_slug: step_slug,
            task_index: i,
            workflow_slug: workflow_slug,
            status: "queued",
            input: %{"item_index" => i}
          }
        end

      # All tasks get claimed and completed independently
      completed_tasks =
        Enum.map(tasks, fn task ->
          task
          |> StepTask.claim("worker-#{task.task_index}")
          |> apply_changes()
          |> StepTask.mark_completed(%{"processed" => true})
          |> apply_changes()
        end)

      # Verify all completed
      assert Enum.all?(completed_tasks, fn t -> t.status == "completed" end)
      assert Enum.all?(completed_tasks, fn t -> t.task_index in 0..2 end)
    end
  end

  # Helper functions
  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        run_id: Ecto.UUID.generate(),
        step_slug: "test_step",
        workflow_slug: "TestWorkflow",
        status: "queued"
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
