defmodule Pgflow.WorkflowRun do
  @moduledoc """
  Ecto schema for workflow_runs table.

  Tracks workflow execution instances - one record per workflow invocation.
  Matches pgflow's runs table design.

  ## Fields

  - `workflow_slug` - Workflow module name (e.g., "MyApp.Workflows.ProcessOrder")
  - `status` - Execution status: "started", "completed", "failed"
  - `input` - Input parameters passed to workflow
  - `output` - Final workflow output (set when completed)
  - `remaining_steps` - Counter: decremented as steps complete
  - `error_message` - Error description if status is "failed"

  ## Status Transitions

  ```
  started → completed (all steps done)
  started → failed (any step fails fatally)
  ```

  ## Usage

      # Create a new run
      %Pgflow.WorkflowRun{}
      |> Pgflow.WorkflowRun.changeset(%{
        workflow_slug: "MyApp.Workflows.Example",
        input: %{"user_id" => 123},
        remaining_steps: 5
      })
      |> Repo.insert()

      # Query active runs
      from(r in Pgflow.WorkflowRun, where: r.status == "started")
      |> Repo.all()
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          workflow_slug: String.t() | nil,
          status: String.t() | nil,
          input: map() | nil,
          output: map() | nil,
          remaining_steps: integer() | nil,
          error_message: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          failed_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workflow_runs" do
    field :workflow_slug, :string
    field :status, :string, default: "started"
    field :input, :map, default: %{}
    field :output, :map
    field :remaining_steps, :integer, default: 0
    field :error_message, :string

    timestamps(type: :utc_datetime_usec)
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :failed_at, :utc_datetime_usec

    has_many :step_states, Pgflow.StepState, foreign_key: :run_id
    has_many :step_tasks, Pgflow.StepTask, foreign_key: :run_id
  end

  @doc """
  Changeset for creating a workflow run.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :workflow_slug,
      :status,
      :input,
      :output,
      :remaining_steps,
      :error_message,
      :started_at,
      :completed_at,
      :failed_at
    ])
    |> validate_required([:workflow_slug, :status, :input])
    |> validate_inclusion(:status, ["started", "completed", "failed"])
    |> validate_number(:remaining_steps, greater_than_or_equal_to: 0)
  end

  @doc """
  Marks a run as completed.
  """
  @spec mark_completed(t(), map()) :: Ecto.Changeset.t()
  def mark_completed(run, output) do
    run
    |> change(%{
      status: "completed",
      output: output,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Marks a run as failed.
  """
  @spec mark_failed(t(), String.t()) :: Ecto.Changeset.t()
  def mark_failed(run, error_message) do
    run
    |> change(%{
      status: "failed",
      error_message: error_message,
      failed_at: DateTime.utc_now()
    })
  end
end
