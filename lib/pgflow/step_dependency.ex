defmodule Pgflow.StepDependency do
  @moduledoc """
  Ecto schema for workflow_step_dependencies table.

  Explicitly tracks step dependency relationships for accurate cascading completion.
  Populated when a workflow run starts based on `depends_on` declarations.

  ## Purpose

  This table enables the complete_task() PostgreSQL function to know exactly
  which steps depend on which other steps, allowing accurate dependency resolution.

  ## Usage

      # Record that "process_payment" depends on "validate_order"
      %Pgflow.StepDependency{}
      |> Pgflow.StepDependency.changeset(%{
        run_id: run.id,
        step_slug: "process_payment",
        depends_on_step: "validate_order"
      })
      |> Repo.insert()

      # Find all steps that depend on "validate_order"
      from(d in Pgflow.StepDependency,
        where: d.run_id == ^run_id,
        where: d.depends_on_step == "validate_order",
        select: d.step_slug
      )
      |> Repo.all()
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          run_id: Ecto.UUID.t() | nil,
          step_slug: String.t() | nil,
          depends_on_step: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key false
  @foreign_key_type :binary_id

  schema "workflow_step_dependencies" do
    field :run_id, :binary_id
    field :step_slug, :string
    field :depends_on_step, :string

    # Only inserted_at, no updated_at (immutable records)
    timestamps(type: :utc_datetime_usec, updated_at: false)

    belongs_to :run, Pgflow.WorkflowRun, define_field: false, foreign_key: :run_id
  end

  @doc """
  Changeset for creating a step dependency.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(step_dependency, attrs) do
    step_dependency
    |> cast(attrs, [:run_id, :step_slug, :depends_on_step])
    |> validate_required([:run_id, :step_slug, :depends_on_step])
    |> unique_constraint([:run_id, :step_slug, :depends_on_step],
      name: :workflow_step_dependencies_unique_idx
    )
  end

  @doc """
  Finds all steps that depend on the given step.
  """
  @spec find_dependents(Ecto.UUID.t(), String.t(), module()) :: [String.t()]
  def find_dependents(run_id, step_slug, repo) do
    import Ecto.Query

    from(d in __MODULE__,
      where: d.run_id == ^run_id,
      where: d.depends_on_step == ^step_slug,
      select: d.step_slug
    )
    |> repo.all()
  end

  @doc """
  Finds all dependencies of the given step.
  """
  @spec find_dependencies(Ecto.UUID.t(), String.t(), module()) :: [String.t()]
  def find_dependencies(run_id, step_slug, repo) do
    import Ecto.Query

    from(d in __MODULE__,
      where: d.run_id == ^run_id,
      where: d.step_slug == ^step_slug,
      select: d.depends_on_step
    )
    |> repo.all()
  end
end
