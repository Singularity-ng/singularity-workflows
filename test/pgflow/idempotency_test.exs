defmodule Pgflow.IdempotencyTest do
  @moduledoc """
  Tests for idempotency key implementation in workflow_step_tasks.

  Ensures exactly-once execution semantics for tasks:
  - Duplicate task inserts are prevented
  - Retries don't create duplicate work
  - Idempotency keys are computed correctly
  """
  use ExUnit.Case, async: false

  alias Pgflow.{StepTask, Repo}
  import Ecto.Query

  setup do
    # Set up sandbox for this test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  # Helper function to create a test workflow and run
  defp create_test_run(workflow_slug \\ "test-workflow") do
    # Create workflow first (insert directly to workflows table)
    {:ok, _} = Repo.query(
      "INSERT INTO workflows (workflow_slug, timeout, max_attempts, created_at) VALUES ($1, $2, $3, NOW()) ON CONFLICT DO NOTHING",
      [workflow_slug, 60, 3]
    )

    # Create run
    run_id = Ecto.UUID.generate()
    run_attrs = %{
      id: run_id,
      workflow_slug: workflow_slug,
      status: "started",
      remaining_steps: 1,
      input: %{},
      started_at: DateTime.utc_now()
    }
    Repo.insert!(%Pgflow.WorkflowRun{} |> Pgflow.WorkflowRun.changeset(run_attrs))
  end

  describe "StepTask.compute_idempotency_key/4" do
    test "generates consistent MD5 hash" do
      key1 = StepTask.compute_idempotency_key("wf1", "step1", "123e4567-e89b-12d3-a456-426614174000", 0)
      key2 = StepTask.compute_idempotency_key("wf1", "step1", "123e4567-e89b-12d3-a456-426614174000", 0)

      # Same inputs produce same key
      assert key1 == key2
      # Key is 32-character hex string (MD5)
      assert String.length(key1) == 32
      assert key1 =~ ~r/^[0-9a-f]{32}$/
    end

    test "generates different keys for different inputs" do
      run_id = "123e4567-e89b-12d3-a456-426614174000"

      key1 = StepTask.compute_idempotency_key("wf1", "step1", run_id, 0)
      key2 = StepTask.compute_idempotency_key("wf2", "step1", run_id, 0)  # Different workflow
      key3 = StepTask.compute_idempotency_key("wf1", "step2", run_id, 0)  # Different step
      key4 = StepTask.compute_idempotency_key("wf1", "step1", run_id, 1)  # Different task_index

      # All keys should be different
      assert key1 != key2
      assert key1 != key3
      assert key1 != key4
      assert key2 != key3
    end

    test "handles different run_ids" do
      key1 = StepTask.compute_idempotency_key("wf1", "step1", "123e4567-e89b-12d3-a456-426614174000", 0)
      key2 = StepTask.compute_idempotency_key("wf1", "step1", "223e4567-e89b-12d3-a456-426614174000", 0)

      assert key1 != key2
    end

    test "handles different task indices" do
      run_id = "123e4567-e89b-12d3-a456-426614174000"

      keys = Enum.map(0..9, fn i ->
        StepTask.compute_idempotency_key("wf1", "step1", run_id, i)
      end)

      # All keys should be unique
      assert length(Enum.uniq(keys)) == 10
    end
  end

  describe "StepTask changeset with idempotency_key" do
    test "automatically computes idempotency_key if not provided" do
      run_id = Ecto.UUID.generate()

      changeset = StepTask.changeset(%StepTask{}, %{
        run_id: run_id,
        step_slug: "test_step",
        task_index: 0,
        workflow_slug: "test_workflow",
        status: "queued"
      })

      assert changeset.valid?
      idempotency_key = Ecto.Changeset.get_field(changeset, :idempotency_key)
      assert idempotency_key != nil
      assert String.length(idempotency_key) == 32
    end

    test "uses provided idempotency_key if given" do
      run_id = Ecto.UUID.generate()
      custom_key = "custom1234567890abcdef1234567890"

      changeset = StepTask.changeset(%StepTask{}, %{
        run_id: run_id,
        step_slug: "test_step",
        task_index: 0,
        workflow_slug: "test_workflow",
        idempotency_key: custom_key,
        status: "queued"
      })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :idempotency_key) == custom_key
    end

    test "computed key matches compute_idempotency_key function" do
      run_id = Ecto.UUID.generate()
      workflow_slug = "test_workflow"
      step_slug = "test_step"
      task_index = 5

      expected_key = StepTask.compute_idempotency_key(workflow_slug, step_slug, run_id, task_index)

      changeset = StepTask.changeset(%StepTask{}, %{
        run_id: run_id,
        step_slug: step_slug,
        task_index: task_index,
        workflow_slug: workflow_slug,
        status: "queued"
      })

      assert Ecto.Changeset.get_field(changeset, :idempotency_key) == expected_key
    end
  end

  describe "Database unique constraint on idempotency_key" do
    test "prevents duplicate task insertion with same idempotency_key" do
      # Create a run first
      run_attrs = %{
        id: Ecto.UUID.generate(),
        workflow_slug: "test-workflow",
        status: "started",
        remaining_steps: 1
      }
      run = Repo.insert!(%Pgflow.WorkflowRun{} |> Pgflow.WorkflowRun.changeset(run_attrs))

      # Insert first task
      task1 = %StepTask{}
      |> StepTask.changeset(%{
        run_id: run.id,
        step_slug: "step1",
        task_index: 0,
        workflow_slug: "test-workflow",
        status: "queued"
      })
      |> Repo.insert!()

      assert task1.idempotency_key != nil

      # Try to insert duplicate task (same workflow, step, run_id, task_index)
      task2_changeset = StepTask.changeset(%StepTask{}, %{
        run_id: run.id,
        step_slug: "step1",
        task_index: 0,
        workflow_slug: "test-workflow",
        status: "queued"
      })

      # Should fail with unique constraint violation (either primary key or idempotency_key)
      # Note: Primary key constraint (run_id, step_slug, task_index) is checked before idempotency_key
      assert_raise Ecto.InvalidChangesetError, fn ->
        Repo.insert!(task2_changeset)
      end
    end

    test "allows different tasks with different idempotency_keys" do
      run_attrs = %{
        id: Ecto.UUID.generate(),
        workflow_slug: "test-workflow",
        status: "started",
        remaining_steps: 1
      }
      run = Repo.insert!(%Pgflow.WorkflowRun{} |> Pgflow.WorkflowRun.changeset(run_attrs))

      # Insert first task
      task1 = %StepTask{}
      |> StepTask.changeset(%{
        run_id: run.id,
        step_slug: "step1",
        task_index: 0,
        workflow_slug: "test-workflow",
        status: "queued"
      })
      |> Repo.insert!()

      # Insert second task with different task_index
      task2 = %StepTask{}
      |> StepTask.changeset(%{
        run_id: run.id,
        step_slug: "step1",
        task_index: 1,  # Different index
        workflow_slug: "test-workflow",
        status: "queued"
      })
      |> Repo.insert!()

      # Both should succeed
      assert task1.idempotency_key != task2.idempotency_key
      assert Repo.aggregate(from(t in StepTask, where: t.run_id == ^run.id), :count) == 2
    end
  end

  describe "SQL function integration" do
    test "compute_idempotency_key SQL function matches Elixir function" do
      workflow_slug = "test-workflow"
      step_slug = "test-step"
      run_id_string = Ecto.UUID.generate()
      {:ok, run_id_binary} = Ecto.UUID.dump(run_id_string)
      task_index = 5

      # Compute key using Elixir function
      elixir_key = StepTask.compute_idempotency_key(workflow_slug, step_slug, run_id_string, task_index)

      # Compute key using SQL function (needs binary UUID)
      # Use public schema prefix to ensure function is found
      {:ok, result} = Repo.query(
        "SELECT public.compute_idempotency_key($1, $2, $3, $4)",
        [workflow_slug, step_slug, run_id_binary, task_index]
      )

      sql_key = result.rows |> hd() |> hd()

      # Both should match
      assert elixir_key == sql_key
    end
  end

  describe "Edge cases" do
    test "handles task_index = 0 correctly" do
      key = StepTask.compute_idempotency_key("wf", "step", Ecto.UUID.generate(), 0)
      assert String.length(key) == 32
      assert key =~ ~r/^[0-9a-f]{32}$/
    end

    test "handles large task_index values" do
      large_index = 999_999
      key = StepTask.compute_idempotency_key("wf", "step", Ecto.UUID.generate(), large_index)
      assert String.length(key) == 32
      assert key =~ ~r/^[0-9a-f]{32}$/
    end

    test "handles special characters in workflow/step slugs" do
      key = StepTask.compute_idempotency_key(
        "workflow_with_underscores",
        "step-with-dashes",
        Ecto.UUID.generate(),
        0
      )
      assert String.length(key) == 32
      assert key =~ ~r/^[0-9a-f]{32}$/
    end
  end

  describe "Migration verification" do
    test "idempotency_key column exists in database" do
      # Query database schema
      result = Repo.query!("""
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_name = 'workflow_step_tasks'
          AND column_name = 'idempotency_key'
      """)

      assert length(result.rows) == 1
      [column_name, data_type, is_nullable] = hd(result.rows)

      assert column_name == "idempotency_key"
      assert data_type in ["character varying", "varchar", "text"]
      assert is_nullable == "NO"
    end

    test "unique index exists on idempotency_key" do
      result = Repo.query!("""
        SELECT indexname, indexdef
        FROM pg_indexes
        WHERE tablename = 'workflow_step_tasks'
          AND indexname = 'workflow_step_tasks_idempotency_key_idx'
      """)

      assert length(result.rows) == 1
      [index_name, index_def] = hd(result.rows)

      assert index_name == "workflow_step_tasks_idempotency_key_idx"
      assert index_def =~ "UNIQUE"
      assert index_def =~ "idempotency_key"
    end
  end

end
