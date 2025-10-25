defmodule Pgflow.Repo.Migrations.ChangeWorkflowRunsIdToUuid do
  use Ecto.Migration

  def change do
    # Drop existing primary key constraint
    execute "ALTER TABLE workflow_runs DROP CONSTRAINT IF EXISTS workflow_runs_pkey"

    # Change the column type
    execute "ALTER TABLE workflow_runs ALTER COLUMN id TYPE uuid USING id::uuid"

    # Add primary key constraint back
    execute "ALTER TABLE workflow_runs ADD CONSTRAINT workflow_runs_pkey PRIMARY KEY (id)"
  end
end
