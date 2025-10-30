defmodule QuantumFlow.Repo.Migrations.AddComputeIdempotencyKeyFunction do
  @moduledoc """
  Adds a SQL helper function to compute idempotency_key.

  This is useful for tests and manual SQL inserts where we need to compute
  the idempotency key on the database side.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION compute_idempotency_key(
      p_workflow_slug TEXT,
      p_step_slug TEXT,
      p_run_id UUID,
      p_task_index INTEGER
    )
    RETURNS VARCHAR(64)
    LANGUAGE SQL
    IMMUTABLE
    AS $$
      SELECT MD5(
        p_workflow_slug || '::' ||
        p_step_slug || '::' ||
        p_run_id::text || '::' ||
        p_task_index::text
      );
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION compute_idempotency_key(TEXT, TEXT, UUID, INTEGER) IS
    'Computes the idempotency key for a task. Used for manual inserts and testing.'
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS compute_idempotency_key(TEXT, TEXT, UUID, INTEGER)")
  end
end
