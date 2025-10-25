defmodule Pgflow.StepDependency do
  @moduledoc """
  Ecto schema for workflow_step_dependencies table.

  Explicitly tracks step dependency relationships for accurate cascading completion.
  Populated when a workflow run starts based on `depends_on` declarations.

  ## Purpose

  This table enables the complete_task() PostgreSQL function to know exactly
  which steps depend on which other steps, allowing accurate dependency resolution.

  ## Common Dependency Patterns

  ```mermaid
  graph TB
      subgraph "Linear Chain"
          A1[Step A] --> B1[Step B]
          B1 --> C1[Step C]
      end

      subgraph "Diamond (Fan-out + Fan-in)"
          A2[Step A] --> B2[Step B]
          A2 --> C2[Step C]
          B2 --> D2[Step D]
          C2 --> D2
      end

      subgraph "Fan-out (Parallel Execution)"
          A3[Step A] --> B3[Step B]
          A3 --> C3[Step C]
          A3 --> D3[Step D]
      end

      subgraph "Fan-in (Merge Point)"
          A4[Step A] --> D4[Step D]
          B4[Step B] --> D4
          C4[Step C] --> D4
      end

      style A1 fill:#90EE90
      style A2 fill:#90EE90
      style A3 fill:#90EE90
      style D4 fill:#FFB6C1
  ```

  ## Dependency Resolution Flow

  ```mermaid
  sequenceDiagram
      participant Parent as Parent Step
      participant Deps as StepDependency
      participant Child as Child Step

      Note over Parent: Task completes
      Parent->>Parent: mark_completed()

      Parent->>Deps: find_dependents(run_id, "parent_step")
      activate Deps
      Note over Deps: Query: WHERE depends_on_step = "parent_step"
      Deps-->>Parent: ["child_step_1", "child_step_2"]
      deactivate Deps

      par Notify all dependent steps
          Parent->>Child: decrement_remaining_deps()
          Note over Child: remaining_deps: 2 → 1
      end

      Note over Child: When remaining_deps = 0<br/>status: created → started
  ```

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
    field(:run_id, :binary_id)
    field(:step_slug, :string)
    field(:depends_on_step, :string)

    # Only inserted_at, no updated_at (immutable records)
    timestamps(type: :utc_datetime_usec, updated_at: false)

    belongs_to(:run, Pgflow.WorkflowRun, define_field: false, foreign_key: :run_id)
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

  Can be called with either a repo module or a function.

  Examples:

      # With repo module
      find_dependents(run_id, "fetch", MyApp.Repo)

      # With function
      find_dependents(run_id, "fetch", fn query -> MyApp.Repo.all(query) end)
  """
  @spec find_dependents(Ecto.UUID.t(), String.t(), module() | function()) :: [String.t()]
  def find_dependents(run_id, step_slug, repo_or_func) do
    import Ecto.Query

    query =
      from(d in __MODULE__,
        where: d.run_id == ^run_id,
        where: d.depends_on_step == ^step_slug,
        select: d.step_slug
      )

    case repo_or_func do
      repo when is_atom(repo) -> repo.all(query)
      func when is_function(func) -> func.(query)
    end
  end

  @doc """
  Finds all dependencies of the given step.

  Can be called with either a repo module or a function.

  Examples:

      # With repo module
      find_dependencies(run_id, "save", MyApp.Repo)

      # With function
      find_dependencies(run_id, "save", fn query -> MyApp.Repo.all(query) end)
  """
  @spec find_dependencies(Ecto.UUID.t(), String.t(), module() | function()) :: [String.t()]
  def find_dependencies(run_id, step_slug, repo_or_func) do
    import Ecto.Query

    query =
      from(d in __MODULE__,
        where: d.run_id == ^run_id,
        where: d.step_slug == ^step_slug,
        select: d.depends_on_step
      )

    case repo_or_func do
      repo when is_atom(repo) -> repo.all(query)
      func when is_function(func) -> func.(query)
    end
  end
end
