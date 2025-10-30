defmodule QuantumFlow.Repo.Migrations.AddIsValidSlugFunction do
  @moduledoc """
  Adds is_valid_slug() utility function for slug validation.

  Used by create_flow() and add_step() to validate slugs match pattern:
  - Not null/empty
  - Max 128 characters
  - Pattern: ^[a-zA-Z_][a-zA-Z0-9_]*$
  - Not reserved words ('run')

  Matches QuantumFlow's validation logic.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION QuantumFlow.is_valid_slug(slug TEXT)
    RETURNS BOOLEAN
    LANGUAGE plpgsql
    IMMUTABLE
    SET search_path = ''
    AS $$
    BEGIN
      RETURN slug IS NOT NULL
        AND slug <> ''
        AND length(slug) <= 128
        AND slug ~ '^[a-zA-Z_][a-zA-Z0-9_]*$'
        AND slug NOT IN ('run'); -- reserved words
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION QuantumFlow.is_valid_slug(TEXT) IS
    'Validates slug format: not null, 1-128 chars, alphanumeric with underscores, no reserved words. Matches QuantumFlow implementation.'
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS QuantumFlow.is_valid_slug(TEXT)")
  end
end
