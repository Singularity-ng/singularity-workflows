defmodule Pgflow.WorkflowRun do
  @moduledoc """
  Ecto schema for workflow_runs table.

  Tracks workflow execution instances - one record per workflow invocation.
  Matches pgflow's runs table design.

  ## State Transition Diagram

  ```mermaid
  stateDiagram-v2
      [*] --> started: Create run
      started --> completed: remaining_steps = 0
      started --> failed: Step fails fatally
      completed --> [*]
      failed --> [*]

      note right of started
          remaining_steps counter
          decrements as steps complete
      end note

      note right of completed
          Sets output map
          Sets completed_at timestamp
      end note

      note right of failed
          Sets error_message
          Sets failed_at timestamp
      end note
  ```

  ## Fields

  - `workflow_slug` - Workflow module name (e.g., "MyApp.Workflows.ProcessOrder")
  - `status` - Execution status: "started", "completed", "failed"
  - `input` - Input parameters passed to workflow
  - `output` - Final workflow output (set when completed)
  - `remaining_steps` - Counter: decremented as steps complete
  - `error_message` - Error description if status is "failed"

  ## Lifecycle Example

  ```mermaid
  sequenceDiagram
      participant Client
      participant Run as WorkflowRun
      participant Steps as StepStates

      Client->>Run: insert(workflow_slug, input, remaining_steps=3)
      activate Run
      Note over Run: status="started"<br/>remaining_steps=3

      Steps->>Run: Step 1 completes
      Note over Run: remaining_steps=2

      Steps->>Run: Step 2 completes
      Note over Run: remaining_steps=1

      Steps->>Run: Step 3 completes
      Note over Run: remaining_steps=0<br/>status="completed"

      Run->>Client: output map
      deactivate Run
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
    field(:workflow_slug, :string)
    field(:status, :string, default: "started")
    field(:input, :map, default: %{})
    field(:output, :map)
    field(:remaining_steps, :integer, default: 0)
    field(:error_message, :string)

    timestamps(type: :utc_datetime_usec)
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)
    field(:failed_at, :utc_datetime_usec)

    has_many(:step_states, Pgflow.StepState, foreign_key: :run_id)
    has_many(:step_tasks, Pgflow.StepTask, foreign_key: :run_id)
  end

  @doc """
  Changeset for creating a workflow run.

  ## Examples

      iex> changeset = Pgflow.WorkflowRun.changeset(%Pgflow.WorkflowRun{}, %{
      ...>   workflow_slug: "MyApp.ProcessOrder",
      ...>   input: %{"order_id" => 123, "user_id" => 456},
      ...>   remaining_steps: 5
      ...> })
      iex> changeset.valid?
      true

      # Invalid status
      iex> changeset = Pgflow.WorkflowRun.changeset(%Pgflow.WorkflowRun{}, %{
      ...>   workflow_slug: "MyWorkflow",
      ...>   status: "pending"  # Invalid - must be started/completed/failed
      ...> })
      iex> changeset.valid?
      false
      iex> changeset.errors[:status]
      {"is invalid", [validation: :inclusion, enum: ["started", "completed", "failed"]]}
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
    |> validate_required([:workflow_slug])
    |> validate_inclusion(:status, ["started", "completed", "failed"])
    |> validate_number(:remaining_steps, greater_than_or_equal_to: 0)
  end

  @doc """
  Marks a run as completed.

  ## Examples

      iex> run = Repo.get!(Pgflow.WorkflowRun, run_id)
      iex> changeset = Pgflow.WorkflowRun.mark_completed(run, %{
      ...>   "result" => "success",
      ...>   "processed_items" => 42,
      ...>   "duration_ms" => 1234
      ...> })
      iex> changeset.changes.status
      "completed"
      iex> changeset.changes.output
      %{"result" => "success", "processed_items" => 42, "duration_ms" => 1234}
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

  ## Examples

      iex> run = Repo.get!(Pgflow.WorkflowRun, run_id)
      iex> changeset = Pgflow.WorkflowRun.mark_failed(run, "Step :payment failed: Invalid card number")
      iex> changeset.changes.status
      "failed"
      iex> changeset.changes.error_message
      "Step :payment failed: Invalid card number"
      iex> is_nil(changeset.changes.failed_at)
      false
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
