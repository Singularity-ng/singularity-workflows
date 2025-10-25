# Debug script to test complete_task function
# Run with: MIX_ENV=test mix run test_complete_task_debug.exs

# Start Repo
{:ok, _} = Application.ensure_all_started(:pgflow)

alias Pgflow.{Repo, WorkflowRun, StepState, StepTask}
alias Pgflow.DAG.{WorkflowDefinition, RunInitializer}
import Ecto.Query

# Simple test workflow
defmodule DebugSimpleFlow do
  def __workflow_steps__ do
    [
      {:step1, &__MODULE__.step1/1}
    ]
  end

  def step1(input) do
    {:ok, Map.put(input, :step1_done, true)}
  end
end

# Parse workflow
{:ok, definition} = WorkflowDefinition.parse(DebugSimpleFlow)

# Create run
{:ok, run_id} = RunInitializer.initialize_run(definition, %{test: true}, Repo)

IO.puts("Created run: #{run_id}")

# Get workflow run details
run = Repo.get!(WorkflowRun, run_id)
IO.puts("Run status: #{run.status}")
IO.puts("Run workflow_slug: #{run.workflow_slug}")

# Get step tasks
tasks = Repo.all(
  from t in StepTask,
  where: t.run_id == ^run_id,
  select: t
)

IO.puts("\nTasks created:")
for task <- tasks do
  IO.puts("  - step: #{task.step_slug}, status: #{task.status}, task_index: #{task.task_index}")
end

# Try to call complete_task directly
if length(tasks) > 0 do
  task = hd(tasks)

  IO.puts("\nAttempting to complete task: #{task.step_slug}[#{task.task_index}]")

  # First update task to 'started' status (complete_task requires this)
  from(t in StepTask,
    where: t.run_id == ^run_id and t.step_slug == ^task.step_slug and t.task_index == ^task.task_index
  )
  |> Repo.update_all(set: [status: "started", started_at: DateTime.utc_now()])

  # Now try complete_task
  output = %{step1_done: true}

  result = Repo.query(
    "SELECT complete_task($1::uuid, $2::text, $3::integer, $4::jsonb)",
    [run_id, task.step_slug, task.task_index, Jason.encode!(output)]
  )

  case result do
    {:ok, _} ->
      IO.puts("✓ complete_task succeeded")

      # Check final status
      updated_task = Repo.get!(StepTask, task.id)
      IO.puts("  Task status: #{updated_task.status}")
      IO.puts("  Task output: #{inspect(updated_task.output)}")

    {:error, %Postgrex.Error{} = error} ->
      IO.puts("✗ complete_task failed with SQL error:")
      IO.puts("  Code: #{inspect(error.postgres.code)}")
      IO.puts("  Message: #{error.postgres.message}")
      if error.postgres.detail, do: IO.puts("  Detail: #{error.postgres.detail}")
      if error.postgres.hint, do: IO.puts("  Hint: #{error.postgres.hint}")

    {:error, reason} ->
      IO.puts("✗ complete_task failed: #{inspect(reason)}")
  end
end

IO.puts("\nDone!")
