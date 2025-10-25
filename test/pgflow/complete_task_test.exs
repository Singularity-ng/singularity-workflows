defmodule Pgflow.CompleteTaskTest do
  use ExUnit.Case, async: false
  use Pgflow.SqlCase

  @moduledoc """
  Basic integration tests ported from pgflow SQL suite that exercise `complete_task`.

  These tests require a running Postgres with the pgflow schema/migrations applied.
  Set DATABASE_URL to point to the DB before running `mix test` to enable them.
  """

  test "complete_task marks task completed and updates dependent state" do
    case Pgflow.SqlCase.connect_or_skip() do
      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
        assert true

      conn ->
        id = Ecto.UUID.generate()
        workflow_slug = "test_flow"

        Postgrex.query!(conn, "INSERT INTO workflow_runs (id, workflow_slug, status, remaining_steps, created_at) VALUES ($1, $2, 'running', 2, now())", [id, workflow_slug])

        # Insert parent step metadata and state
        Postgrex.query!(conn, "INSERT INTO workflow_steps (workflow_slug, step_slug, step_type) VALUES ($1, $2, 'single')", [workflow_slug, "parent"])
        Postgrex.query!(conn, "INSERT INTO workflow_steps (workflow_slug, step_slug, step_type) VALUES ($1, $2, 'map')", [workflow_slug, "child"])

        Postgrex.query!(conn, "INSERT INTO workflow_step_states (run_id, step_slug, status, remaining_tasks, remaining_deps, initial_tasks) VALUES ($1, $2, 'created', 1, 0, NULL)", [id, "parent"]) 
        Postgrex.query!(conn, "INSERT INTO workflow_step_states (run_id, step_slug, status, remaining_tasks, remaining_deps, initial_tasks) VALUES ($1, $2, 'created', 0, 1, NULL)", [id, "child"]) 

        Postgrex.query!(conn, "INSERT INTO workflow_step_tasks (run_id, step_slug, task_index, status) VALUES ($1, $2, 0, 'started')", [id, "parent"]) 

        # Create dependency: child depends on parent
        Postgrex.query!(conn, "INSERT INTO workflow_step_dependencies (run_id, step_slug, depends_on_step) VALUES ($1, $2, $3)", [id, "child", "parent"]) 

        # Call complete_task with an array output so child initial_tasks will be set
        Postgrex.query!(conn, "SELECT complete_task($1::uuid, $2::text, $3::int, $4::jsonb)", [id, "parent", 0, Jason.encode!([1,2,3])])

        # Verify parent task status
        res = Postgrex.query!(conn, "SELECT status FROM workflow_step_tasks WHERE run_id=$1 AND step_slug=$2 AND task_index=0", [id, "parent"]) 
        assert res.rows == [["completed"]]

        # Verify child state initial_tasks set to array length (3)
        res2 = Postgrex.query!(conn, "SELECT initial_tasks FROM workflow_step_states WHERE run_id=$1 AND step_slug=$2", [id, "child"]) 
        assert res2.rows == [[3]]
  end
  end

  test "type violation (single -> map non-array) marks run failed" do
    case Pgflow.SqlCase.connect_or_skip() do
      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
        assert true

      conn ->
        id = Ecto.UUID.generate()
        workflow_slug = "test_flow"

        Postgrex.query!(conn, "INSERT INTO workflow_runs (id, workflow_slug, status, remaining_steps, created_at) VALUES ($1, $2, 'running', 1, now())", [id, workflow_slug])
        Postgrex.query!(conn, "INSERT INTO workflow_steps (workflow_slug, step_slug, step_type) VALUES ($1, $2, 'single')", [workflow_slug, "p"]) 
        Postgrex.query!(conn, "INSERT INTO workflow_steps (workflow_slug, step_slug, step_type) VALUES ($1, $2, 'map')", [workflow_slug, "c"]) 

        Postgrex.query!(conn, "INSERT INTO workflow_step_states (run_id, step_slug, status, remaining_tasks, remaining_deps, initial_tasks) VALUES ($1, $2, 'created', 1, 0, NULL)", [id, "p"]) 
        Postgrex.query!(conn, "INSERT INTO workflow_step_states (run_id, step_slug, status, remaining_tasks, remaining_deps, initial_tasks) VALUES ($1, $2, 'created', 0, 1, NULL)", [id, "c"]) 
        Postgrex.query!(conn, "INSERT INTO workflow_step_tasks (run_id, step_slug, task_index, status) VALUES ($1, $2, 0, 'started')", [id, "p"]) 
        Postgrex.query!(conn, "INSERT INTO workflow_step_dependencies (run_id, step_slug, depends_on_step) VALUES ($1, $2, $3)", [id, "c", "p"]) 

        # Non-array output (null) should trigger type-violation and mark run failed
        Postgrex.query!(conn, "SELECT complete_task($1::uuid, $2::text, $3::int, $4::jsonb)", [id, "p", 0, Jason.encode!(nil)])

        res = Postgrex.query!(conn, "SELECT status FROM workflow_runs WHERE id=$1", [id])
        assert res.rows == [["failed"]]
  end
  end
end
