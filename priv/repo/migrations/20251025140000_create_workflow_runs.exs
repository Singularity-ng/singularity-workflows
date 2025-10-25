defmodule Pgflow.Repo.Migrations.CreateWorkflowRuns do
  @moduledoc """
  Creates workflow_runs table for tracking workflow execution instances.

  Matches pgflow's runs table design - one record per workflow execution.
  """
  use Ecto.Migration

  def up do
    create table(:workflow_runs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :workflow_slug, :string, null: false
      add :status, :string, null: false, default: "started"
      add :input, :map, null: false, default: %{}
      add :output, :map
      add :remaining_steps, :integer, null: false, default: 0
      add :error_message, :text
      add :created_at, :utc_datetime_usec, null: false, default: fragment("now()")

      timestamps(type: :utc_datetime_usec)
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :failed_at, :utc_datetime_usec
    end

    create index(:workflow_runs, [:workflow_slug])
    create index(:workflow_runs, [:status])
    create index(:workflow_runs, [:inserted_at])
    create index(:workflow_runs, [:workflow_slug, :status])

    # Partial index for active runs (performance optimization)
    create index(:workflow_runs, [:id],
      where: "status = 'started'",
      name: :workflow_runs_active_idx
    )

    execute """
    COMMENT ON TABLE workflow_runs IS
    'Tracks workflow execution instances (pgflow-compatible design)'
    """

    execute """
    COMMENT ON COLUMN workflow_runs.workflow_slug IS
    'Workflow module name (e.g., MyApp.Workflows.ProcessOrder)'
    """

    execute """
    COMMENT ON COLUMN workflow_runs.status IS
    'Execution status: started | completed | failed'
    """

    execute """
    COMMENT ON COLUMN workflow_runs.remaining_steps IS
    'Counter: decremented as steps complete, reaches 0 when run is done'
    """
  end

  def down do
    drop table(:workflow_runs)
  end
end
