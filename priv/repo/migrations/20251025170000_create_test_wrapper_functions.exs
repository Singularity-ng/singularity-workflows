defmodule Pgflow.Repo.Migrations.CreateTestWrapperFunctions do
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
    # Wrapper for complete_task that returns boolean instead of void
    execute("""
    CREATE OR REPLACE FUNCTION test_complete_task(
      p_run_id UUID,
      p_step_slug TEXT,
      p_task_index INTEGER,
      p_output JSONB DEFAULT NULL
    )
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
    BEGIN
      -- Call the actual complete_task function
      PERFORM complete_task(p_run_id, p_step_slug, p_task_index, p_output);

      -- Return true to indicate successful execution
      RETURN true;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION test_complete_task(UUID, TEXT, INTEGER, JSONB) IS
    'Test wrapper for complete_task that returns boolean for Postgrex compatibility.
     DO NOT USE IN PRODUCTION - use complete_task directly instead.';
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS test_complete_task(UUID, TEXT, INTEGER, JSONB)")
  end
end
