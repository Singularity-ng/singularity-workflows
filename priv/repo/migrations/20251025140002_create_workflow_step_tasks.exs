defmodule Pgflow.Repo.Migrations.CreateWorkflowStepTasks do
  @moduledoc """
  Creates workflow_step_tasks table for tracking individual task executions.

  Matches pgflow's step_tasks table design - the execution layer for DAG workflows.
  Each step can have multiple tasks (e.g., map steps with arrays).
  """
  use Ecto.Migration

  def up do
    create table(:workflow_step_tasks, primary_key: false) do
      # Composite primary key: (run_id, step_slug, task_index)
      add :run_id, references(:workflow_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :step_slug, :string, null: false
      add :task_index, :integer, null: false, default: 0
      add :workflow_slug, :string, null: false

      # Task execution status
      add :status, :string, null: false, default: "queued"

      # Task data
      add :input, :map
      add :output, :map

      # Error handling
      add :error_message, :text
      add :attempts_count, :integer, default: 0
      add :max_attempts, :integer, default: 3

      # Worker coordination
      add :claimed_by, :string
      add :claimed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :failed_at, :utc_datetime_usec
    end

    # Composite primary key
    create unique_index(:workflow_step_tasks, [:run_id, :step_slug, :task_index],
      name: :workflow_step_tasks_pkey
    )

    # Foreign key to step_states
    create index(:workflow_step_tasks, [:run_id, :step_slug],
      name: :workflow_step_tasks_step_fkey_idx
    )

    # Indexes for common queries
    create index(:workflow_step_tasks, [:run_id])
    create index(:workflow_step_tasks, [:status])
    create index(:workflow_step_tasks, [:workflow_slug])

    # Critical index for polling queued tasks
    create index(:workflow_step_tasks, [:run_id, :status, :task_index],
      where: "status = 'queued'",
      name: :workflow_step_tasks_queued_idx
    )

    # Index for worker claims
    create index(:workflow_step_tasks, [:claimed_by, :claimed_at],
      where: "status = 'started'",
      name: :workflow_step_tasks_claimed_idx
    )

    # Index for task ordering (ensures deterministic execution)
    create index(:workflow_step_tasks, [:run_id, :step_slug, :task_index])

    execute """
    COMMENT ON TABLE workflow_step_tasks IS
    'Tracks individual task executions within workflow steps - execution layer for DAG'
    """

    execute """
    COMMENT ON COLUMN workflow_step_tasks.status IS
    'Task status: queued | started | completed | failed'
    """

    execute """
    COMMENT ON COLUMN workflow_step_tasks.task_index IS
    'Task position within step (0 for single steps, 0..N for map steps)'
    """

    execute """
    COMMENT ON COLUMN workflow_step_tasks.claimed_by IS
    'Worker/instance ID that claimed this task'
    """

    execute """
    COMMENT ON COLUMN workflow_step_tasks.claimed_at IS
    'Timestamp when task was claimed - used for timeout detection'
    """
  end

  def down do
    drop table(:workflow_step_tasks)
  end
end
