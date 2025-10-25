defmodule Pgflow.Repo.Migrations.AddMessageIdToStepTasks do
  use Ecto.Migration

  def change do
    alter table(:workflow_step_tasks) do
      add :message_id, :bigint
      # pgmq message ID for coordination
    end

    create index(:workflow_step_tasks, [:message_id])
  end
end
