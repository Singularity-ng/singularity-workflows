defmodule Pgflow.Repo.Migrations.EnableUuidV7Support do
  use Ecto.Migration

  def change do
    # Enable UUID extension for enhanced UUID support
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""

    # Note: uuid_generate_v7() requires PostgreSQL 18+
    # For now, we'll use gen_random_uuid() which is available in PostgreSQL 17
    # Update workflow_runs to use UUID (keeping existing gen_random_uuid for compatibility)
    alter table(:workflow_runs) do
      modify :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    end

    # Update other tables that use UUIDs
    alter table(:workflow_step_states) do
      modify :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    end

    alter table(:workflow_step_tasks) do
      modify :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    end

    alter table(:workflow_step_dependencies) do
      modify :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    end
  end
end
