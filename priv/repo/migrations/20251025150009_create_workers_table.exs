defmodule Pgflow.Repo.Migrations.CreateWorkersTable do
  @moduledoc """
  Creates workers table for worker heartbeat tracking.

  Matches pgflow's worker registration and heartbeat system. Workers register
  when they start polling and update last_heartbeat_at periodically.

  Used for monitoring and debugging worker activity.
  """
  use Ecto.Migration

  def change do
    create table(:workflow_workers, primary_key: false) do
      add :worker_id, :uuid, primary_key: true
      add :queue_name, :text, null: false
      add :function_name, :text, null: false
      add :started_at, :utc_datetime, null: false, default: fragment("NOW()")
      add :deprecated_at, :utc_datetime
      add :last_heartbeat_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create index(:workflow_workers, [:queue_name])
    create index(:workflow_workers, [:last_heartbeat_at])

    # Update step_tasks to reference workers
    alter table(:workflow_step_tasks) do
      add :last_worker_id, references(:workflow_workers, column: :worker_id, type: :uuid, on_delete: :nilify_all)
    end

    create index(:workflow_step_tasks, [:last_worker_id], where: "status = 'started'")
  end
end
