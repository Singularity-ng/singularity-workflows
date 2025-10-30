defmodule QuantumFlow.Repo.Migrations.AddSmartUuidGeneration do
  @moduledoc """
  Creates a smart UUID generation function that uses the best available method.

  - PostgreSQL 18+: Uses uuidv7() (time-ordered, built-in)
  - PostgreSQL 13-17: Falls back to gen_random_uuid() (random v4)

  This ensures quantum_flow works on both old and new PostgreSQL versions.
  """
  use Ecto.Migration

  def up do
    # Create a smart UUID generation function that auto-detects capabilities
    execute """
    CREATE OR REPLACE FUNCTION generate_uuid()
    RETURNS uuid
    LANGUAGE plpgsql
    AS $$
    BEGIN
      -- Try to use uuidv7() if available (PostgreSQL 18+)
      BEGIN
        RETURN uuidv7();
      EXCEPTION
        WHEN undefined_function THEN
          -- Fall back to gen_random_uuid() (PostgreSQL 13+)
          RETURN gen_random_uuid();
      END;
    END;
    $$;
    """

    execute """
    COMMENT ON FUNCTION generate_uuid() IS
    'Smart UUID generation: uses uuidv7() on PostgreSQL 18+, gen_random_uuid() on older versions';
    """

    # Update workflow_runs to use the smart function
    execute """
    ALTER TABLE workflow_runs
    ALTER COLUMN id SET DEFAULT generate_uuid();
    """
  end

  def down do
    # Restore original default
    execute """
    ALTER TABLE workflow_runs
    ALTER COLUMN id SET DEFAULT gen_random_uuid();
    """

    execute "DROP FUNCTION IF EXISTS generate_uuid();"
  end
end
