defmodule QuantumFlow.Repo.Migrations.CreateTestWrapperFunctions do
  @moduledoc """
  Creates test wrapper functions for void-returning functions.

  PostgreSQL's prepared statement protocol (used by Postgrex) requires SELECT
  statements to have a destination for results. Void-returning functions cannot
  be called directly via SELECT in prepared statements.

  These wrappers call the void functions and return a boolean success indicator,
  making them compatible with Postgrex while maintaining the same behavior.

  These are test-only wrappers and should not be used in production code.
  """
  use Ecto.Migration

  def up do
    # Wrapper for complete_task that returns TABLE instead of void
    # Note: RETURNS TABLE works with Postgrex prepared statements, while RETURNS boolean does not
    execute("""
    CREATE OR REPLACE FUNCTION test_complete_task_v2(
      p_run_id UUID,
      p_step_slug TEXT,
      p_task_index INTEGER,
      p_output JSONB
    )
    RETURNS TABLE(success boolean)
    LANGUAGE plpgsql
    AS $$
    BEGIN
      -- Call the actual complete_task function
      PERFORM complete_task(p_run_id, p_step_slug, p_task_index, p_output);

      -- Return true to indicate successful execution
      RETURN QUERY SELECT true;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION test_complete_task_v2(UUID, TEXT, INTEGER, JSONB) IS
    'Test wrapper for complete_task that returns TABLE for Postgrex compatibility.
     Uses RETURNS TABLE instead of RETURNS boolean to avoid prepared statement protocol issues.
     DO NOT USE IN PRODUCTION - use complete_task directly instead.';
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS test_complete_task_v2(UUID, TEXT, INTEGER, JSONB)")
    # Also drop the old version if it exists
    execute("DROP FUNCTION IF EXISTS test_complete_task(UUID, TEXT, INTEGER, JSONB)")
  end
end
