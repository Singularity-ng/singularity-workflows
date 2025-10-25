defmodule Pgflow.Repo.Migrations.AddCreatedAtToWorkflowRuns do
  use Ecto.Migration

  def change do
    alter table(:workflow_runs) do
      add :created_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end
  end
end
