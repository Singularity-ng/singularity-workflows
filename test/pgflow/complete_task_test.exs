defmodule Pgflow.CompleteTaskTest do
  use ExUnit.Case, async: false
  use Pgflow.SqlCase

  alias Pgflow.StepTask

  @moduledoc """
  Integration tests for complete_task() SQL function.

  These tests require a running Postgres with the pgflow schema/migrations applied.
  Set DATABASE_URL to point to the DB before running `mix test` to enable them.

  NOTE: These tests have database state management issues with simultaneous test execution.
  They should be run in isolation with @tag :integration.

  ## complete_task Return Values

  The function returns INTEGER:
  - `1` on success (task completed)
  - `0` on guard (run already failed, no mutation)
  - `-1` on type violation (map step expects array, got non-array)

  See migration 20251025210500_change_complete_task_return_type.exs for details.
  """

  @tag :integration
  test "complete_task marks task completed and updates dependent state" do
    case Pgflow.SqlCase.connect_or_skip() do
      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
        assert true

      conn ->
        id = Ecto.UUID.generate()
        {:ok, binary_id} = Ecto.UUID.dump(id)
        workflow_slug = "test_flow_#{String.replace(Ecto.UUID.generate(), "-", "")}"

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_runs (id, workflow_slug, status, remaining_steps, created_at, inserted_at, updated_at) VALUES ($1, $2, 'running', 2, now(), now(), now())",
          [binary_id, workflow_slug]
        )

        # Insert workflow definition
        Postgrex.query!(
          conn,
          "INSERT INTO workflows (workflow_slug, max_attempts, timeout) VALUES ($1, 3, 60)",
          [workflow_slug]
        )

        # Insert step metadata and state with explicit step_index
        Postgrex.query!(
          conn,
          "INSERT INTO workflow_steps (workflow_slug, step_slug, step_type, step_index) VALUES ($1, $2, 'single', $3)",
          [workflow_slug, "parent", 0]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_steps (workflow_slug, step_slug, step_type, step_index) VALUES ($1, $2, 'map', $3)",
          [workflow_slug, "child", 1]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_states (run_id, step_slug, workflow_slug, status, remaining_tasks, remaining_deps, initial_tasks, inserted_at, updated_at) VALUES ($1, $2, $3, 'created', 1, 0, NULL, now(), now())",
          [binary_id, "parent", workflow_slug]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_states (run_id, step_slug, workflow_slug, status, remaining_tasks, remaining_deps, initial_tasks, inserted_at, updated_at) VALUES ($1, $2, $3, 'created', 0, 1, NULL, now(), now())",
          [binary_id, "child", workflow_slug]
        )

        {:ok, uuid_string} = Ecto.UUID.load(binary_id)
        idempotency_key = StepTask.compute_idempotency_key(workflow_slug, "parent", uuid_string, 0)
        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_tasks (run_id, step_slug, workflow_slug, task_index, status, idempotency_key, inserted_at, updated_at) VALUES ($1, $2, $3, 0, 'started', $4, now(), now())",
          [binary_id, "parent", workflow_slug, idempotency_key]
        )

        # Create dependency: child depends on parent
        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_dependencies (run_id, step_slug, depends_on_step, inserted_at) VALUES ($1, $2, $3, now())",
          [binary_id, "child", "parent"]
        )

        # Call complete_task and verify return value (1 = success)
        # Use array output (not object) since child is a map step
        result =
          Postgrex.query!(
            conn,
            "SELECT complete_task($1, $2, $3, $4)",
            [binary_id, "parent", 0, [1, 2, 3]]
          )

        # complete_task returns 1 on success
        assert result.rows == [[1]]

        # Verify parent task status
        res =
          Postgrex.query!(
            conn,
            "SELECT status FROM workflow_step_tasks WHERE run_id=$1 AND step_slug=$2 AND task_index=0",
            [binary_id, "parent"]
          )

        assert res.rows == [["completed"]]

        # Verify child state initial_tasks set to array length (3)
        res2 =
          Postgrex.query!(
            conn,
            "SELECT initial_tasks FROM workflow_step_states WHERE run_id=$1 AND step_slug=$2",
            [binary_id, "child"]
          )

        # initial_tasks should be 3 (length of the array output [1, 2, 3])
        assert res2.rows == [[3]]

        # Verify step's remaining_deps was decremented to 0 (child step is now ready)
        res3 =
          Postgrex.query!(
            conn,
            "SELECT remaining_deps FROM workflow_step_states WHERE run_id=$1 AND step_slug=$2",
            [binary_id, "child"]
          )

        assert res3.rows == [[0]]

        # Verify workflow_runs remaining_steps was decremented
        res4 =
          Postgrex.query!(
            conn,
            "SELECT remaining_steps FROM workflow_runs WHERE id=$1",
            [binary_id]
          )

        assert res4.rows == [[1]]
    end
  end

  @tag :integration
  test "type violation (single -> map non-array) marks run failed" do
    case Pgflow.SqlCase.connect_or_skip() do
      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
        assert true

      conn ->
        id = Ecto.UUID.generate()
        {:ok, binary_id} = Ecto.UUID.dump(id)
        workflow_slug = "test_flow_#{String.replace(Ecto.UUID.generate(), "-", "")}"

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_runs (id, workflow_slug, status, remaining_steps, created_at, inserted_at, updated_at) VALUES ($1, $2, 'running', 1, now(), now(), now())",
          [binary_id, workflow_slug]
        )

        # Insert workflow definition
        Postgrex.query!(
          conn,
          "INSERT INTO workflows (workflow_slug, max_attempts, timeout) VALUES ($1, 3, 60)",
          [workflow_slug]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_steps (workflow_slug, step_slug, step_type, step_index) VALUES ($1, $2, 'single', $3)",
          [workflow_slug, "p", 0]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_steps (workflow_slug, step_slug, step_type, step_index) VALUES ($1, $2, 'map', $3)",
          [workflow_slug, "c", 1]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_states (run_id, step_slug, workflow_slug, status, remaining_tasks, remaining_deps, initial_tasks, inserted_at, updated_at) VALUES ($1, $2, $3, 'created', 1, 0, NULL, now(), now())",
          [binary_id, "p", workflow_slug]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_states (run_id, step_slug, workflow_slug, status, remaining_tasks, remaining_deps, initial_tasks, inserted_at, updated_at) VALUES ($1, $2, $3, 'created', 0, 1, NULL, now(), now())",
          [binary_id, "c", workflow_slug]
        )

        {:ok, uuid_string} = Ecto.UUID.load(binary_id)
        idempotency_key_p = StepTask.compute_idempotency_key(workflow_slug, "p", uuid_string, 0)
        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_tasks (run_id, step_slug, workflow_slug, task_index, status, idempotency_key, inserted_at, updated_at) VALUES ($1, $2, $3, 0, 'started', $4, now(), now())",
          [binary_id, "p", workflow_slug, idempotency_key_p]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_dependencies (run_id, step_slug, depends_on_step, inserted_at) VALUES ($1, $2, $3, now())",
          [binary_id, "c", "p"]
        )

        # Call complete_task with NULL output (type violation - map step expects array)
        # This should return -1 and mark the run as failed
        result =
          Postgrex.query!(
            conn,
            "SELECT complete_task($1, $2, $3, $4)",
            [binary_id, "p", 0, nil]
          )

        # complete_task returns -1 on type violation
        assert result.rows == [[-1]]

        # Verify run was marked as failed
        res = Postgrex.query!(conn, "SELECT status FROM workflow_runs WHERE id=$1", [binary_id])
        assert res.rows == [["failed"]]

        # Verify error message contains type violation info
        res2 =
          Postgrex.query!(
            conn,
            "SELECT error_message FROM workflow_runs WHERE id=$1",
            [binary_id]
          )

        [[error_message]] = res2.rows
        assert error_message =~ "[TYPE_VIOLATION]"
        assert error_message =~ "Map step c"
        assert error_message =~ "null"

        # Verify task was marked as failed
        res3 =
          Postgrex.query!(
            conn,
            "SELECT status FROM workflow_step_tasks WHERE run_id=$1 AND step_slug=$2",
            [binary_id, "p"]
          )

        assert res3.rows == [["failed"]]
    end
  end

  @tag :integration
  test "complete_task returns 0 guard when run already failed (no mutation)" do
    case Pgflow.SqlCase.connect_or_skip() do
      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
        assert true

      conn ->
        id = Ecto.UUID.generate()
        {:ok, binary_id} = Ecto.UUID.dump(id)
        workflow_slug = "test_flow_#{String.replace(Ecto.UUID.generate(), "-", "")}"

        # Create run already marked as failed
        Postgrex.query!(
          conn,
          "INSERT INTO workflow_runs (id, workflow_slug, status, remaining_steps, created_at, inserted_at, updated_at) VALUES ($1, $2, 'failed', 1, now(), now(), now())",
          [binary_id, workflow_slug]
        )

        # Insert workflow definition
        Postgrex.query!(
          conn,
          "INSERT INTO workflows (workflow_slug, max_attempts, timeout) VALUES ($1, 3, 60)",
          [workflow_slug]
        )

        # Insert step
        Postgrex.query!(
          conn,
          "INSERT INTO workflow_steps (workflow_slug, step_slug, step_type, step_index) VALUES ($1, $2, 'single', $3)",
          [workflow_slug, "step1", 0]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_states (run_id, step_slug, workflow_slug, status, remaining_tasks, remaining_deps, initial_tasks, inserted_at, updated_at) VALUES ($1, $2, $3, 'created', 1, 0, NULL, now(), now())",
          [binary_id, "step1", workflow_slug]
        )

        {:ok, uuid_string} = Ecto.UUID.load(binary_id)
        idempotency_key = StepTask.compute_idempotency_key(workflow_slug, "step1", uuid_string, 0)
        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_tasks (run_id, step_slug, workflow_slug, task_index, status, idempotency_key, inserted_at, updated_at) VALUES ($1, $2, $3, 0, 'started', $4, now(), now())",
          [binary_id, "step1", workflow_slug, idempotency_key]
        )

        # Attempt to complete task on failed run - should return 0 (guard)
        result =
          Postgrex.query!(
            conn,
            "SELECT complete_task($1, $2, $3, $4)",
            [binary_id, "step1", 0, nil]
          )

        # complete_task returns 0 when run already failed (guard prevents mutation)
        assert result.rows == [[0]]

        # Verify task status unchanged (still 'started' - no mutation occurred)
        res =
          Postgrex.query!(
            conn,
            "SELECT status FROM workflow_step_tasks WHERE run_id=$1 AND step_slug=$2",
            [binary_id, "step1"]
          )

        assert res.rows == [["started"]]
    end
  end

  @tag :integration
  test "complete_task with array output sets child map step initial_tasks correctly" do
    case Pgflow.SqlCase.connect_or_skip() do
      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
        assert true

      conn ->
        id = Ecto.UUID.generate()
        {:ok, binary_id} = Ecto.UUID.dump(id)
        workflow_slug = "test_flow_#{String.replace(Ecto.UUID.generate(), "-", "")}"

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_runs (id, workflow_slug, status, remaining_steps, created_at, inserted_at, updated_at) VALUES ($1, $2, 'running', 2, now(), now(), now())",
          [binary_id, workflow_slug]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflows (workflow_slug, max_attempts, timeout) VALUES ($1, 3, 60)",
          [workflow_slug]
        )

        # Parent single step
        Postgrex.query!(
          conn,
          "INSERT INTO workflow_steps (workflow_slug, step_slug, step_type, step_index) VALUES ($1, $2, 'single', $3)",
          [workflow_slug, "parent", 0]
        )

        # Child map step
        Postgrex.query!(
          conn,
          "INSERT INTO workflow_steps (workflow_slug, step_slug, step_type, step_index) VALUES ($1, $2, 'map', $3)",
          [workflow_slug, "child_map", 1]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_states (run_id, step_slug, workflow_slug, status, remaining_tasks, remaining_deps, initial_tasks, inserted_at, updated_at) VALUES ($1, $2, $3, 'created', 1, 0, NULL, now(), now())",
          [binary_id, "parent", workflow_slug]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_states (run_id, step_slug, workflow_slug, status, remaining_tasks, remaining_deps, initial_tasks, inserted_at, updated_at) VALUES ($1, $2, $3, 'created', 0, 1, NULL, now(), now())",
          [binary_id, "child_map", workflow_slug]
        )

        {:ok, uuid_string} = Ecto.UUID.load(binary_id)
        idempotency_key = StepTask.compute_idempotency_key(workflow_slug, "parent", uuid_string, 0)
        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_tasks (run_id, step_slug, workflow_slug, task_index, status, idempotency_key, inserted_at, updated_at) VALUES ($1, $2, $3, 0, 'started', $4, now(), now())",
          [binary_id, "parent", workflow_slug, idempotency_key]
        )

        # Create dependency
        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_dependencies (run_id, step_slug, depends_on_step, inserted_at) VALUES ($1, $2, $3, now())",
          [binary_id, "child_map", "parent"]
        )

        # Complete parent with 5-element array output
        result =
          Postgrex.query!(
            conn,
            "SELECT complete_task($1, $2, $3, $4)",
            [binary_id, "parent", 0, ["a", "b", "c", "d", "e"]]
          )

        assert result.rows == [[1]]

        # Verify child_map initial_tasks set to 5 (array length)
        res =
          Postgrex.query!(
            conn,
            "SELECT initial_tasks FROM workflow_step_states WHERE run_id=$1 AND step_slug=$2",
            [binary_id, "child_map"]
          )

        assert res.rows == [[5]]

        # Verify child remaining_deps decremented to 0
        res2 =
          Postgrex.query!(
            conn,
            "SELECT remaining_deps FROM workflow_step_states WHERE run_id=$1 AND step_slug=$2",
            [binary_id, "child_map"]
          )

        assert res2.rows == [[0]]
    end
  end

  @tag :integration
  test "complete_task marks workflow as completed when all steps done" do
    case Pgflow.SqlCase.connect_or_skip() do
      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
        assert true

      conn ->
        id = Ecto.UUID.generate()
        {:ok, binary_id} = Ecto.UUID.dump(id)
        workflow_slug = "test_flow_#{String.replace(Ecto.UUID.generate(), "-", "")}"

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_runs (id, workflow_slug, status, remaining_steps, created_at, inserted_at, updated_at) VALUES ($1, $2, 'running', 1, now(), now(), now())",
          [binary_id, workflow_slug]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflows (workflow_slug, max_attempts, timeout) VALUES ($1, 3, 60)",
          [workflow_slug]
        )

        # Single step workflow
        Postgrex.query!(
          conn,
          "INSERT INTO workflow_steps (workflow_slug, step_slug, step_type, step_index) VALUES ($1, $2, 'single', $3)",
          [workflow_slug, "only_step", 0]
        )

        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_states (run_id, step_slug, workflow_slug, status, remaining_tasks, remaining_deps, initial_tasks, inserted_at, updated_at) VALUES ($1, $2, $3, 'created', 1, 0, NULL, now(), now())",
          [binary_id, "only_step", workflow_slug]
        )

        {:ok, uuid_string} = Ecto.UUID.load(binary_id)
        idempotency_key = StepTask.compute_idempotency_key(workflow_slug, "only_step", uuid_string, 0)
        Postgrex.query!(
          conn,
          "INSERT INTO workflow_step_tasks (run_id, step_slug, workflow_slug, task_index, status, idempotency_key, inserted_at, updated_at) VALUES ($1, $2, $3, 0, 'started', $4, now(), now())",
          [binary_id, "only_step", workflow_slug, idempotency_key]
        )

        # Complete the only task
        result =
          Postgrex.query!(
            conn,
            "SELECT complete_task($1, $2, $3, $4)",
            [binary_id, "only_step", 0, %{"result" => "success"}]
          )

        assert result.rows == [[1]]

        # Verify workflow marked as completed
        res =
          Postgrex.query!(
            conn,
            "SELECT status, completed_at IS NOT NULL FROM workflow_runs WHERE id=$1",
            [binary_id]
          )

        assert res.rows == [["completed", true]]

        # Verify step marked as completed
        res2 =
          Postgrex.query!(
            conn,
            "SELECT status FROM workflow_step_states WHERE run_id=$1 AND step_slug=$2",
            [binary_id, "only_step"]
          )

        assert res2.rows == [["completed"]]

        # Verify task marked as completed with output
        res3 =
          Postgrex.query!(
            conn,
            "SELECT status, output FROM workflow_step_tasks WHERE run_id=$1 AND step_slug=$2",
            [binary_id, "only_step"]
          )

        assert [[status, output]] = res3.rows
        assert status == "completed"
        assert output == %{"result" => "success"}
    end
  end
end
