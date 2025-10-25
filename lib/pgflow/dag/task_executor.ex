defmodule Pgflow.DAG.TaskExecutor do
  @moduledoc """
  Executes workflow step tasks from the database.

  Implements the pgflow execution model:
  1. Poll for queued tasks
  2. Claim a task (mark as 'started')
  3. Execute the step function
  4. Call complete_task() PostgreSQL function
  5. Repeat until all tasks complete or fail

  ## Execution Loop

      TaskExecutor.execute_run(run_id, definition, repo)
        ↓
      Poll for queued tasks
        ↓
      Claim task (update status='started', set claimed_by)
        ↓
      Execute step function
        ↓
      Call complete_task(run_id, step_slug, task_index, output)
        ↓
      PostgreSQL cascades completion
        ↓
      Poll for next queued tasks (newly awakened steps)
        ↓
      Repeat until no more queued tasks

  ## Parallelism

  Multiple workers can run execute_run() concurrently for the same run_id.
  PostgreSQL handles coordination via row-level locking on task claims.

  ## Error Handling

  - Task failure: Mark as 'failed', retry if attempts_count < max_attempts
  - Task timeout: Mark as 'failed' with timeout error
  - Max attempts: Mark step as 'failed', propagate to run
  """

  require Logger

  alias Pgflow.DAG.WorkflowDefinition
  alias Pgflow.WorkflowRun

  @doc """
  Execute all tasks for a workflow run until completion or failure.

  Uses pgmq for task coordination (matches pgflow architecture):
  1. Poll messages from pgmq queue
  2. Call start_tasks() to claim tasks
  3. Execute step functions
  4. Call complete_task() or fail_task()

  Returns:
  - `{:ok, output}` - Run completed successfully
  - `{:ok, :in_progress}` - Run still in progress (when timeout occurs)
  - `{:error, reason}` - Run failed

  ## Examples

      # Execute with default settings (runs until completion)
      iex> {:ok, output} = TaskExecutor.execute_run(
      ...>   run_id,
      ...>   workflow_definition,
      ...>   MyApp.Repo
      ...> )
      iex> Map.keys(output)
      [:result, :processed_count, :duration_ms]

      # Execute with timeout (useful for long-running workflows)
      iex> {:ok, status} = TaskExecutor.execute_run(
      ...>   run_id,
      ...>   workflow_definition,
      ...>   MyApp.Repo,
      ...>   timeout: 30_000,  # 30 seconds
      ...>   poll_interval: 100  # Poll every 100ms
      ...> )
      iex> status
      :in_progress  # Workflow still running after timeout

  Multiple workers can execute the same run concurrently by passing different
  worker_id options. PostgreSQL handles coordination via row-level locking
  on task claims to prevent double-execution.
  """
  @spec execute_run(Ecto.UUID.t(), WorkflowDefinition.t(), module(), keyword()) ::
          {:ok, map()} | {:ok, :in_progress} | {:error, term()}
  def execute_run(run_id, definition, repo, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    # :infinity default (matches pgflow - runs until workflow completes)
    poll_interval_ms = Keyword.get(opts, :poll_interval, 200)
    # 200ms between polls
    worker_id = Keyword.get(opts, :worker_id, Ecto.UUID.generate())
    batch_size = Keyword.get(opts, :batch_size, 10)
    # Poll up to 10 messages at once (matches pgflow default)
    max_poll_seconds = Keyword.get(opts, :max_poll_seconds, 5)
    # Max time to wait for messages (matches pgflow default)

    start_time = System.monotonic_time(:millisecond)

    Logger.info("TaskExecutor: Starting execution loop with pgmq",
      run_id: run_id,
      worker_id: worker_id,
      batch_size: batch_size,
      workflow_slug: definition.slug
    )

    execute_loop(
      run_id,
      definition.slug,
      definition,
      repo,
      worker_id,
      start_time,
      timeout,
      poll_interval_ms,
      batch_size,
      max_poll_seconds
    )
  end

  # Main execution loop: poll pgmq → claim → execute → repeat
  defp execute_loop(
         run_id,
         workflow_slug,
         definition,
         repo,
         worker_id,
         start_time,
         timeout,
         poll_interval_ms,
         batch_size,
         max_poll_seconds
       ) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    cond do
      timeout != :infinity and elapsed > timeout ->
        Logger.warning("TaskExecutor: Timeout exceeded", run_id: run_id, elapsed_ms: elapsed)
        check_run_status(run_id, repo)

      true ->
        case poll_and_execute_batch(
               workflow_slug,
               definition,
               repo,
               worker_id,
               batch_size,
               max_poll_seconds,
               poll_interval_ms
             ) do
          {:ok, :tasks_executed, count} ->
            # Tasks completed, poll for next batch immediately
            Logger.debug("TaskExecutor: Executed #{count} tasks", run_id: run_id)

            execute_loop(
              run_id,
              workflow_slug,
              definition,
              repo,
              worker_id,
              start_time,
              timeout,
              poll_interval_ms,
              batch_size,
              max_poll_seconds
            )

          {:ok, :no_messages} ->
            # No messages available, check run status
            case check_run_status(run_id, repo) do
              {:ok, output} when is_map(output) ->
                # Run completed successfully
                {:ok, output}

              {:error, _} = error ->
                error

              {:ok, :in_progress} ->
                # Run still in progress, continue polling
                execute_loop(
                  run_id,
                  workflow_slug,
                  definition,
                  repo,
                  worker_id,
                  start_time,
                  timeout,
                  poll_interval_ms,
                  batch_size,
                  max_poll_seconds
                )
            end

          {:error, reason} ->
            Logger.error("TaskExecutor: Task execution failed",
              run_id: run_id,
              reason: inspect(reason)
            )

            {:error, reason}
        end
    end
  end

  # Poll pgmq for messages and execute tasks (matches pgflow architecture)
  defp poll_and_execute_batch(
         workflow_slug,
         definition,
         repo,
         worker_id,
         batch_size,
         max_poll_seconds,
         poll_interval_ms
       ) do
    # Phase 1: Poll pgmq for messages
    messages_result =
      repo.query(
        """
        SELECT *
        FROM pgflow.read_with_poll(
          queue_name => $1::text,
          vt => $2::integer,
          qty => $3::integer,
          max_poll_seconds => $4::integer,
          poll_interval_ms => $5::integer
        )
        """,
        [workflow_slug, 30, batch_size, max_poll_seconds, poll_interval_ms]
      )

    case messages_result do
      {:ok, %{rows: []}} ->
        # No messages available
        {:ok, :no_messages}

      {:ok, %{rows: message_rows}} ->
        # Extract message IDs
        msg_ids = Enum.map(message_rows, fn [msg_id | _rest] -> msg_id end)

        Logger.debug("TaskExecutor: Polled #{length(msg_ids)} messages from pgmq",
          workflow_slug: workflow_slug,
          msg_ids: msg_ids
        )

        # Phase 2: Call start_tasks() to claim tasks
        tasks_result =
          repo.query(
            """
            SELECT *
            FROM start_tasks(
              p_workflow_slug => $1::text,
              p_msg_ids => $2::bigint[],
              p_worker_id => $3::text
            )
            """,
            [workflow_slug, msg_ids, worker_id]
          )

        case tasks_result do
          {:ok, %{columns: columns, rows: task_rows}} ->
            # Convert rows to task records
            tasks =
              Enum.map(task_rows, fn row ->
                Enum.zip(columns, row) |> Map.new()
              end)

            Logger.debug("TaskExecutor: Claimed #{length(tasks)} tasks",
              workflow_slug: workflow_slug
            )

            # Phase 3: Execute tasks concurrently
            results =
              Task.async_stream(
                tasks,
                fn task -> execute_task_from_map(task, definition, repo) end,
                max_concurrency: batch_size,
                timeout: 60_000
              )
              |> Enum.to_list()

            # Check for failures
            failed =
              Enum.filter(results, fn
                {:ok, {:error, _}} -> true
                {:exit, _} -> true
                _ -> false
              end)

            if failed != [] do
              Logger.warning(
                "TaskExecutor: #{length(failed)}/#{length(tasks)} tasks failed in batch",
                workflow_slug: workflow_slug
              )
            end

            {:ok, :tasks_executed, length(tasks)}

          {:error, reason} ->
            Logger.error("TaskExecutor: Failed to start tasks",
              workflow_slug: workflow_slug,
              reason: inspect(reason)
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("TaskExecutor: Failed to poll pgmq",
          workflow_slug: workflow_slug,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Execute a single task from map (after start_tasks() call)
  defp execute_task_from_map(task_map, definition, repo) do
    run_id = task_map["run_id"]
    step_slug = task_map["step_slug"]
    task_index = task_map["task_index"]
    input = task_map["input"]

    step_slug_atom = String.to_existing_atom(step_slug)
    step_fn = WorkflowDefinition.get_step_function(definition, step_slug_atom)

    if step_fn == nil do
      Logger.error("TaskExecutor: Step function not found",
        step_slug: step_slug,
        run_id: run_id
      )

      {:error, {:step_not_found, step_slug}}
    end

    Logger.debug("TaskExecutor: Executing task",
      run_id: run_id,
      step_slug: step_slug,
      task_index: task_index
    )

    # Execute step function with timeout
    result =
      try do
        task_with_timeout = Task.async(fn -> step_fn.(input) end)

        case Task.yield(task_with_timeout, 30_000) do
          {:ok, {:ok, output}} ->
            {:ok, output}

          {:ok, {:error, reason}} ->
            {:error, reason}

          nil ->
            Task.shutdown(task_with_timeout, :brutal_kill)
            {:error, :timeout}
        end
      catch
        kind, error ->
          {:error, {:exception, {kind, error}}}
      end

    # Handle result
    case result do
      {:ok, output} ->
        complete_task_success(run_id, step_slug, task_index, output, repo)

      {:error, reason} ->
        complete_task_failure(run_id, step_slug, task_index, reason, repo)
    end
  end

  # Complete task successfully (using pgflow complete_task function)
  defp complete_task_success(run_id, step_slug, task_index, output, repo) do
    # Call PostgreSQL complete_task function
    result =
      repo.query(
        "SELECT complete_task($1::uuid, $2::text, $3::integer, $4::jsonb)",
        [run_id, step_slug, task_index, Jason.encode!(output)]
      )

    case result do
      {:ok, _} ->
        Logger.debug("TaskExecutor: Task completed successfully",
          run_id: run_id,
          step_slug: step_slug,
          task_index: task_index
        )

        {:ok, :task_executed}

      {:error, reason} ->
        Logger.error("TaskExecutor: Failed to complete task",
          run_id: run_id,
          step_slug: step_slug,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Complete task with failure (using pgflow fail_task function)
  defp complete_task_failure(run_id, step_slug, task_index, reason, repo) do
    error_message = inspect(reason)

    # Call PostgreSQL fail_task function
    result =
      repo.query(
        "SELECT pgflow.fail_task($1::uuid, $2::text, $3::integer, $4::text)",
        [run_id, step_slug, task_index, error_message]
      )

    case result do
      {:ok, _} ->
        Logger.warning("TaskExecutor: Task failed",
          run_id: run_id,
          step_slug: step_slug,
          task_index: task_index,
          reason: error_message
        )

        {:ok, :task_executed}

      {:error, db_reason} ->
        Logger.error("TaskExecutor: Failed to mark task as failed",
          run_id: run_id,
          step_slug: step_slug,
          reason: inspect(db_reason)
        )

        {:error, db_reason}
    end
  end

  # Check run status to determine if execution is complete
  defp check_run_status(run_id, repo) do
    run = repo.get!(WorkflowRun, run_id)

    case run.status do
      "completed" ->
        Logger.info("TaskExecutor: Run completed", run_id: run_id)
        {:ok, run.output || %{}}

      "failed" ->
        Logger.error("TaskExecutor: Run failed", run_id: run_id, error: run.error_message)
        {:error, {:run_failed, run.error_message}}

      "started" ->
        # Still in progress
        {:ok, :in_progress}
    end
  end
end
