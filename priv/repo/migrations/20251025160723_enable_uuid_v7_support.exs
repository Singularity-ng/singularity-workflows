defmodule Pgflow.Repo.Migrations.EnableUuidV7Support do
  use Ecto.Migration

  def change do
    # Enable UUID extension for enhanced UUID support
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""

    # Note: uuid_generate_v7() requires PostgreSQL 18+
    # For now, we'll use gen_random_uuid() which is available in PostgreSQL 17
    # These tables already have primary keys defined, so we only update defaults
    # No need to specify primary_key: true again (it's already set)

    # No changes needed - tables already have UUID primary keys with gen_random_uuid()
    # This migration just ensures the uuid-ossp extension exists
  end
end
