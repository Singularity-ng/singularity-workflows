defmodule Pgflow.StepState do
  @moduledoc """
  Ecto schema for workflow_step_states table.

  Tracks step progress within a workflow run - the coordination layer for DAG execution.
  Matches pgflow's step_states table design.

  ## Counter-Based Coordination

  The key innovation from pgflow:

  - `remaining_deps` - How many dependency steps haven't completed yet
  - `remaining_tasks` - How many tasks in this step are still executing
  - `initial_tasks` - Total task count (set when step starts)

  ## Status Transitions

  ```
  created (remaining_deps > 0) → ... → created (remaining_deps = 0) → started
  started (remaining_tasks > 0) → ... → started (remaining_tasks = 0) → completed
  started → failed (on error)
  ```

  ## Usage

      # Create step states for a run
      for step <- workflow_steps do
        %Pgflow.StepState{}
        |> Pgflow.StepState.changeset(%{
          run_id: run.id,
          workflow_slug: workflow_slug,
          step_slug: step.slug,
          remaining_deps: length(step.depends_on),
          initial_tasks: 1  # Single task for most steps
        })
        |> Repo.insert()
      end

      # Find ready steps (all dependencies satisfied)
      from(s in Pgflow.StepState,
        where: s.run_id == ^run_id,
        where: s.status == "created",
        where: s.remaining_deps == 0
      )
      |> Repo.all()
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          run_id: Ecto.UUID.t() | nil,
          step_slug: String.t() | nil,
          workflow_slug: String.t() | nil,
          status: String.t() | nil,
          remaining_deps: integer() | nil,
          remaining_tasks: integer() | nil,
          initial_tasks: integer() | nil,
          error_message: String.t() | nil,
          attempts_count: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          failed_at: DateTime.t() | nil
        }

  @primary_key false
  @foreign_key_type :binary_id

  schema "workflow_step_states" do
    field :run_id, :binary_id
    field :step_slug, :string
    field :workflow_slug, :string

    field :status, :string, default: "created"
    field :remaining_deps, :integer, default: 0
    field :remaining_tasks, :integer
    field :initial_tasks, :integer

    field :error_message, :string
    field :attempts_count, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :failed_at, :utc_datetime_usec

    belongs_to :run, Pgflow.WorkflowRun, define_field: false, foreign_key: :run_id
    has_many :tasks, Pgflow.StepTask, foreign_key: :step_slug, references: :step_slug
  end

  @doc """
  Changeset for creating a step state.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(step_state, attrs) do
    step_state
    |> cast(attrs, [
      :run_id,
      :step_slug,
      :workflow_slug,
      :status,
      :remaining_deps,
      :remaining_tasks,
      :initial_tasks,
      :error_message,
      :attempts_count,
      :started_at,
      :completed_at,
      :failed_at
    ])
    |> validate_required([:run_id, :step_slug, :workflow_slug, :status])
    |> validate_inclusion(:status, ["created", "started", "completed", "failed"])
    |> validate_number(:remaining_deps, greater_than_or_equal_to: 0)
    |> unique_constraint([:run_id, :step_slug], name: :workflow_step_states_pkey)
  end

  @doc """
  Marks a step as started.
  """
  @spec mark_started(t(), integer()) :: Ecto.Changeset.t()
  def mark_started(step_state, initial_tasks) do
    step_state
    |> change(%{
      status: "started",
      initial_tasks: initial_tasks,
      remaining_tasks: initial_tasks,
      started_at: DateTime.utc_now()
    })
  end

  @doc """
  Marks a step as completed.
  """
  @spec mark_completed(t()) :: Ecto.Changeset.t()
  def mark_completed(step_state) do
    step_state
    |> change(%{
      status: "completed",
      remaining_tasks: 0,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Marks a step as failed.
  """
  @spec mark_failed(t(), String.t()) :: Ecto.Changeset.t()
  def mark_failed(step_state, error_message) do
    step_state
    |> change(%{
      status: "failed",
      error_message: error_message,
      failed_at: DateTime.utc_now()
    })
  end

  @doc """
  Decrements the remaining_deps counter.
  """
  @spec decrement_remaining_deps(t()) :: Ecto.Changeset.t()
  def decrement_remaining_deps(step_state) do
    new_count = max(0, (step_state.remaining_deps || 0) - 1)

    step_state
    |> change(%{remaining_deps: new_count})
  end

  @doc """
  Decrements the remaining_tasks counter.
  """
  @spec decrement_remaining_tasks(t()) :: Ecto.Changeset.t()
  def decrement_remaining_tasks(step_state) do
    new_count = max(0, (step_state.remaining_tasks || 0) - 1)

    step_state
    |> change(%{remaining_tasks: new_count})
  end
end
