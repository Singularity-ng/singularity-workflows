defmodule Pgflow.StepTask do
  @moduledoc """
  Ecto schema for workflow_step_tasks table.

  Tracks individual task executions within a step - the execution layer for DAG workflows.
  Matches pgflow's step_tasks table design.

  ## Task Lifecycle with Retry Logic

  ```mermaid
  %%{init: {'theme':'dark'}}%%
  stateDiagram-v2
      [*] --> queued: Create task
      queued --> started: claim(worker_id)<br/>attempts_count++
      started --> completed: mark_completed(output)
      started --> failed: mark_failed(error)
      failed --> queued: requeue()<br/>if can_retry?
      failed --> [*]: attempts >= max_attempts
      completed --> [*]

      note right of queued
          status: "queued"
          claimed_by: nil
      end note

      note right of started
          status: "started"
          claimed_by: worker_id
          claimed_at: timestamp
      end note

      note right of failed
          Retry logic:
          can_retry? checks
          attempts < max_attempts
      end note
  ```

  ## Task vs Step

  - A **step** is a logical unit in the workflow (e.g., "process_payment")
  - A **task** is a single execution unit within a step
  - Most steps have 1 task (task_index = 0)
  - Map steps can have multiple tasks (one per array element)

  ## Retry Flow Example

  ```mermaid
  %%{init: {'theme':'dark'}}%%
  sequenceDiagram
      participant Q as Task Queue
      participant W1 as Worker 1
      participant W2 as Worker 2
      participant Task

      Note over Task: status=queued<br/>attempts_count=0

      Q->>W1: claim()
      W1->>Task: claim("worker-1")
      Note over Task: status=started<br/>attempts_count=1<br/>claimed_by=worker-1

      W1->>Task: Execute...
      W1--xTask: Network timeout!
      W1->>Task: mark_failed("timeout")
      Note over Task: status=failed<br/>can_retry? true

      Task->>Q: requeue()
      Note over Task: status=queued<br/>claimed_by=nil

      Q->>W2: claim() (retry attempt)
      W2->>Task: claim("worker-2")
      Note over Task: status=started<br/>attempts_count=2

      W2->>Task: Execute...
      W2->>Task: mark_completed(output)
      Note over Task: status=completed
  ```

  ## Map Step Parallel Execution

  ```mermaid
  %%{init: {'theme':'dark'}}%%
  graph LR
      subgraph "Map Step: process_items"
          T0[Task 0<br/>index=0<br/>input: item[0]]
          T1[Task 1<br/>index=1<br/>input: item[1]]
          T2[Task 2<br/>index=2<br/>input: item[2]]
      end

      W1[Worker 1] -.claims.-> T0
      W2[Worker 2] -.claims.-> T1
      W3[Worker 3] -.claims.-> T2

      T0 --> R0[Output 0]
      T1 --> R1[Output 1]
      T2 --> R2[Output 2]
  ```

  ## Usage

      # Create a task for a step
      %Pgflow.StepTask{}
      |> Pgflow.StepTask.changeset(%{
        run_id: run.id,
        step_slug: "process_payment",
        task_index: 0,
        workflow_slug: workflow_slug,
        input: %{"amount" => 100}
      })
      |> Repo.insert()

      # Claim a queued task
      task
      |> Pgflow.StepTask.claim(worker_id)
      |> Repo.update()

      # Complete a task
      task
      |> Pgflow.StepTask.mark_completed(%{"receipt_id" => "12345"})
      |> Repo.update()
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          run_id: Ecto.UUID.t() | nil,
          step_slug: String.t() | nil,
          task_index: integer() | nil,
          workflow_slug: String.t() | nil,
          status: String.t() | nil,
          input: map() | nil,
          output: map() | nil,
          error_message: String.t() | nil,
          attempts_count: integer() | nil,
          max_attempts: integer() | nil,
          claimed_by: String.t() | nil,
          claimed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          failed_at: DateTime.t() | nil
        }

  @primary_key false
  @foreign_key_type :binary_id

  schema "workflow_step_tasks" do
    field(:run_id, :binary_id)
    field(:step_slug, :string)
    field(:task_index, :integer, default: 0)
    field(:workflow_slug, :string)

    field(:status, :string, default: "queued")
    field(:input, :map)
    field(:output, :map)

    field(:error_message, :string)
    field(:attempts_count, :integer, default: 0)
    field(:max_attempts, :integer, default: 3)

    field(:claimed_by, :string)
    field(:claimed_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)
    field(:failed_at, :utc_datetime_usec)

    belongs_to(:run, Pgflow.WorkflowRun, define_field: false, foreign_key: :run_id)

    belongs_to(:step_state, Pgflow.StepState,
      define_field: false,
      foreign_key: :step_slug,
      references: :step_slug
    )
  end

  @doc """
  Changeset for creating a step task.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(step_task, attrs) do
    step_task
    |> cast(attrs, [
      :run_id,
      :step_slug,
      :task_index,
      :workflow_slug,
      :status,
      :input,
      :output,
      :error_message,
      :attempts_count,
      :max_attempts,
      :claimed_by,
      :claimed_at,
      :started_at,
      :completed_at,
      :failed_at
    ])
    |> validate_required([:run_id, :step_slug, :workflow_slug, :status])
    |> validate_inclusion(:status, ["queued", "started", "completed", "failed"])
    |> validate_number(:task_index, greater_than_or_equal_to: 0)
    |> validate_number(:attempts_count, greater_than_or_equal_to: 0)
    |> validate_number(:max_attempts, greater_than: 0)
    |> unique_constraint([:run_id, :step_slug, :task_index], name: :workflow_step_tasks_pkey)
  end

  @doc """
  Claims a task for a worker.
  """
  @spec claim(t(), String.t()) :: Ecto.Changeset.t()
  def claim(step_task, worker_id) do
    step_task
    |> change(%{
      status: "started",
      claimed_by: worker_id,
      claimed_at: DateTime.utc_now(),
      started_at: DateTime.utc_now(),
      attempts_count: (step_task.attempts_count || 0) + 1
    })
  end

  @doc """
  Marks a task as completed.
  """
  @spec mark_completed(t(), map()) :: Ecto.Changeset.t()
  def mark_completed(step_task, output) do
    step_task
    |> change(%{
      status: "completed",
      output: output,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Marks a task as failed.
  """
  @spec mark_failed(t(), String.t()) :: Ecto.Changeset.t()
  def mark_failed(step_task, error_message) do
    step_task
    |> change(%{
      status: "failed",
      error_message: error_message,
      failed_at: DateTime.utc_now()
    })
  end

  @doc """
  Requeues a failed task for retry.
  """
  @spec requeue(t()) :: Ecto.Changeset.t()
  def requeue(step_task) do
    step_task
    |> change(%{
      status: "queued",
      claimed_by: nil,
      claimed_at: nil
    })
  end

  @doc """
  Checks if a task can be retried based on max_attempts.
  """
  @spec can_retry?(t()) :: boolean()
  def can_retry?(step_task) do
    (step_task.attempts_count || 0) < (step_task.max_attempts || 3)
  end
end
