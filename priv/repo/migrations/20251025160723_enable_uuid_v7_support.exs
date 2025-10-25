defmodule Pgflow.Repo.Migrations.EnableUuidV7Support do
  use Ecto.Migration

  def change do
    # Enable UUID extension for v7 support
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""

    # Update workflow_runs to use UUIDv7
    alter table(:workflow_runs) do
      modify :id, :uuid, primary_key: true, default: fragment("uuid_generate_v7()")
    end

    # Update other tables that use UUIDs to also use v7
    alter table(:workflow_step_states) do
      modify :id, :uuid, primary_key: true, default: fragment("uuid_generate_v7()")
    end

    alter table(:workflow_step_tasks) do
      modify :id, :uuid, primary_key: true, default: fragment("uuid_generate_v7()")
    end

    alter table(:workflow_step_dependencies) do
      modify :id, :uuid, primary_key: true, default: fragment("uuid_generate_v7()")
    end
  end
end
