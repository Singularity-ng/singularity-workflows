defmodule QuantumFlow.Repo.Migrations.EnableUuidV7Support do
  @moduledoc """
  Placeholder migration for UUID v7 support.

  Originally tried to enable uuid-ossp extension, but:
  - PostgreSQL 18+ has uuidv7() built-in (no extension needed)
  - PostgreSQL 13+ has gen_random_uuid() built-in (no extension needed)

  See migration 20251025210000_add_smart_uuid_generation.exs for the
  actual UUID v7 implementation with automatic fallback.
  """
  use Ecto.Migration

  def change do
    # No-op migration
    # UUID functions are now built-in to PostgreSQL 13+ and 18+
    # Smart UUID generation added in later migration
  end
end
