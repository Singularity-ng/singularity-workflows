defmodule QuantumFlow.Repo.Migrations.AddIdempotencyKeyToStepTasks do
  @moduledoc """
  Adds idempotency_key column to workflow_step_tasks table to prevent duplicate task execution.

  ## Problem
  When tasks are retried or re-enqueued, they can execute multiple times because there's
  no unique constraint preventing duplicate execution. This leads to:
  - Duplicate work being performed
  - Inconsistent state
  - Unreliable test results

  ## Solution
  Add a computed idempotency key based on (workflow_slug, step_slug, run_id, task_index).
  This guarantees exactly-once execution per logical task.

  ## Implementation
  1. Add idempotency_key column (VARCHAR(64))
  2. Populate existing rows with MD5 hash of composite key
  3. Create UNIQUE index on idempotency_key
  4. Add NOT NULL constraint

  ## Idempotency Key Format
  MD5(workflow_slug || '::' || step_slug || '::' || run_id || '::' || task_index)

  Example: MD5('my-workflow::step1::123e4567-e89b-12d3-a456-426614174000::0')
  Result: '5d41402abc4b2a76b9719d911017c592'
  """
  use Ecto.Migration

  def up do
    # Step 1: Add idempotency_key column (nullable initially)
    alter table(:workflow_step_tasks) do
      add :idempotency_key, :string, size: 64
    end

    # Step 2: Populate existing rows with computed idempotency key
    execute """
    UPDATE workflow_step_tasks
    SET idempotency_key = MD5(
      workflow_slug || '::' ||
      step_slug || '::' ||
      run_id::text || '::' ||
      task_index::text
    )
    """

    # Step 3: Add NOT NULL constraint (all rows now have values)
    alter table(:workflow_step_tasks) do
      modify :idempotency_key, :string, null: false, size: 64
    end

    # Step 4: Create UNIQUE index for idempotency enforcement
    create unique_index(:workflow_step_tasks, [:idempotency_key],
      name: :workflow_step_tasks_idempotency_key_idx
    )

    execute """
    COMMENT ON COLUMN workflow_step_tasks.idempotency_key IS
    'MD5 hash of (workflow_slug, step_slug, run_id, task_index) - ensures exactly-once execution per task'
    """
  end

  def down do
    # Remove UNIQUE index
    drop unique_index(:workflow_step_tasks, [:idempotency_key],
      name: :workflow_step_tasks_idempotency_key_idx
    )

    # Remove column
    alter table(:workflow_step_tasks) do
      remove :idempotency_key
    end
  end
end
