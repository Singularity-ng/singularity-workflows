defmodule QuantumFlow.Repo.Migrations.CreateWorkflowStepStates do
  @moduledoc """
  Creates workflow_step_states table for tracking step progress within a run.

  Matches QuantumFlow's step_states table design - the coordination layer for DAG execution.
  """
  use Ecto.Migration

  def up do
    create table(:workflow_step_states, primary_key: false) do
      # Composite primary key: (run_id, step_slug)
      add :run_id, references(:workflow_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :step_slug, :string, null: false
      add :workflow_slug, :string, null: false

      # Step execution status
      add :status, :string, null: false, default: "created"

      # Counter-based coordination (QuantumFlow's key innovation)
      add :remaining_deps, :integer, null: false, default: 0
      add :remaining_tasks, :integer
      add :initial_tasks, :integer

      # Error tracking
      add :error_message, :text
      add :attempts_count, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :failed_at, :utc_datetime_usec
    end

    # Composite primary key
    create unique_index(:workflow_step_states, [:run_id, :step_slug],
      name: :workflow_step_states_pkey
    )

    # Indexes for common queries
    create index(:workflow_step_states, [:run_id])
    create index(:workflow_step_states, [:status])
    create index(:workflow_step_states, [:workflow_slug])

    # Critical index for finding ready steps (remaining_deps = 0)
    create index(:workflow_step_states, [:run_id, :remaining_deps, :status],
      name: :workflow_step_states_ready_idx
    )

    # Partial index for active steps
    create index(:workflow_step_states, [:run_id, :step_slug],
      where: "status = 'started'",
      name: :workflow_step_states_active_idx
    )

    execute """
    COMMENT ON TABLE workflow_step_states IS
    'Tracks step progress within workflow runs - coordination layer for DAG execution'
    """

    execute """
    COMMENT ON COLUMN workflow_step_states.status IS
    'Step status: created | started | completed | failed'
    """

    execute """
    COMMENT ON COLUMN workflow_step_states.remaining_deps IS
    'Counter: how many dependency steps have not yet completed. When 0, step is ready to start.'
    """

    execute """
    COMMENT ON COLUMN workflow_step_states.remaining_tasks IS
    'Counter: how many tasks in this step are still executing. When 0, step is complete.'
    """

    execute """
    COMMENT ON COLUMN workflow_step_states.initial_tasks IS
    'Total number of tasks this step should execute. Set when step starts.'
    """
  end

  def down do
    drop table(:workflow_step_states)
  end
end
