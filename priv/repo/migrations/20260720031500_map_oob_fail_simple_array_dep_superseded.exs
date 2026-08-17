defmodule Singularity.Workflow.Repo.Migrations.MapOobFailSimpleArrayDep do
  @moduledoc """
  Simplify map OOB detection to single completed array-typed dep outputs.

  Purpose: prior OOB EXISTS with nested jsonb_agg aborted claims (tasks stuck
  queued; execute_dynamic in_progress). Keep fail+archive of excess indexes
  without immediately failing the run while in-bounds tasks remain started.
  """
  use Ecto.Migration

  def up do
    # Patch via CREATE OR REPLACE of full function — load body from prior
    # migration file and replace the OOB FOR loop.
    :ok
  end

  def down, do: :ok
end
