defmodule Singularity.Workflow.DAG.TaskExecutor do
  @moduledoc """
  Executes workflow step tasks from the database.

  Implements the QuantumFlow execution model:
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

  alias Singularity.Workflow.DAG.WorkflowDefinition
  alias Singularity.Workflow.WorkflowRun

  @doc """
  Execute all tasks for a workflow run until completion or failure.

  Uses pgmq for task coordination (matches QuantumFlow architecture):
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
    # :infinity default (matches Singularity.Workflow - runs until workflow completes)
    poll_interval_ms = Keyword.get(opts, :poll_interval, 200)
    # 200ms between polls
    worker_id = Keyword.get(opts, :worker_id, Ecto.UUID.generate())
    batch_size = Keyword.get(opts, :batch_size, 10)
    # Poll up to 10 messages at once (matches QuantumFlow default)
    max_poll_seconds = Keyword.get(opts, :max_poll_seconds, 5)
    # Max time to wait for messages (matches QuantumFlow default)
    task_timeout_ms = Keyword.get(opts, :task_timeout_ms, 30_000)
    # Task execution timeout in milliseconds (default: 30 seconds)

    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting execution loop",
      run_id: run_id,
      worker_id: worker_id,
      batch_size: batch_size,
      workflow_slug: definition.slug,
      task_timeout_ms: task_timeout_ms,
      coordination: "pgmq"
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
      max_poll_seconds,
      task_timeout_ms
    )
  end

  # Main execution loop: poll pgmq → claim → execute → repeat
  @spec execute_loop(
          Ecto.UUID.t(),
          String.t(),
          WorkflowDefinition.t(),
          module(),
          String.t(),
          integer(),
          integer() | :infinity,
          integer(),
          integer(),
          integer(),
          integer()
        ) :: {:ok, map()} | {:ok, :in_progress} | {:error, term()}
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
         max_poll_seconds,
         task_timeout_ms
       ) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    cond do
      timeout != :infinity and elapsed > timeout ->
        Logger.warning("Timeout exceeded",
          run_id: run_id,
          elapsed_ms: elapsed,
          timeout_ms: timeout
        )

        check_run_status(run_id, repo)

      true ->
        case poll_and_execute_batch(
               workflow_slug,
               definition,
               repo,
               worker_id,
               batch_size,
               max_poll_seconds,
               poll_interval_ms,
               task_timeout_ms
             ) do
          {:ok, :tasks_executed, count} ->
            # Tasks completed, poll for next batch immediately
            Logger.debug("Executed batch of tasks",
              run_id: run_id,
              task_count: count
            )

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
              max_poll_seconds,
              task_timeout_ms
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
                  max_poll_seconds,
                  task_timeout_ms
                )
            end

          {:error, reason} ->
            Logger.error("Task execution failed",
              run_id: run_id,
              reason: inspect(reason)
            )

            {:error, reason}
        end
    end
  end

  # Poll pgmq for messages and execute tasks (matches QuantumFlow architecture)
  @spec poll_and_execute_batch(
          String.t(),
          WorkflowDefinition.t(),
          module(),
          String.t(),
          integer(),
          integer(),
          integer(),
          integer()
        ) :: {:ok, :no_messages} | {:ok, :tasks_executed, integer()} | {:error, term()}
  defp poll_and_execute_batch(
         workflow_slug,
         definition,
         repo,
         worker_id,
         batch_size,
         max_poll_seconds,
         poll_interval_ms,
         task_timeout_ms
       ) do
    # Phase 1: Poll pgmq for messages
    # Add safety margin timeout (max_poll_seconds + 5 sec grace period) to prevent infinite waiting
    poll_timeout_ms = (max_poll_seconds + 5) * 1000

    messages_result =
      repo.query(
        """
        SELECT *
        FROM Singularity.Workflow.read_with_poll(
          queue_name => $1::text,
          vt => $2::integer,
          qty => $3::integer,
          max_poll_seconds => $4::integer,
          poll_interval_ms => $5::integer
        )
        """,
        [workflow_slug, 30, batch_size, max_poll_seconds, poll_interval_ms],
        timeout: poll_timeout_ms
      )

    case messages_result do
      {:ok, %{rows: []}} ->
        # No messages available
        {:ok, :no_messages}

      {:ok, %{rows: message_rows}} ->
        # Extract message IDs
        msg_ids = Enum.map(message_rows, fn [msg_id | _rest] -> msg_id end)

        Logger.debug("Polled messages from queue",
          workflow_slug: workflow_slug,
          msg_count: length(msg_ids)
        )

        # Phase 2: Call start_tasks() to claim tasks
        # Set timeout to 10 seconds to prevent row-level locking hangs
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
            [workflow_slug, msg_ids, worker_id],
            timeout: 10_000
          )

        case tasks_result do
          {:ok, %{columns: columns, rows: task_rows}} ->
            # Convert rows to task records
            tasks =
              Enum.map(task_rows, fn row ->
                Enum.zip(columns, row) |> Map.new()
              end)

            Logger.debug("Claimed tasks for execution",
              workflow_slug: workflow_slug,
              task_count: length(tasks)
            )

            # Phase 3: Execute tasks concurrently
            results =
              Task.async_stream(
                tasks,
                fn task -> execute_task_from_map(task, definition, repo, task_timeout_ms) end,
                max_concurrency: batch_size,
                timeout: 60_000
              )
              |> Enum.to_list()

            # Check for execution or worker failures (not task function failures, which are handled)
            failed =
              Enum.filter(results, fn
                # Task execution or DB call failed
                {:ok, {:error, _}} -> true
                # Worker process exited
                {:exit, _} -> true
                _ -> false
              end)

            if failed != [] do
              Logger.warning(
                "TaskExecutor: #{length(failed)}/#{length(tasks)} task executions failed in batch",
                workflow_slug: workflow_slug,
                failed_count: length(failed)
              )

              # Return error only if significant portion of batch failed (>50%)
              # This allows for occasional worker failures without cascading retry loops
              if length(failed) * 2 > length(tasks) do
                {:error, {:batch_failure, length(failed), length(tasks)}}
              else
                {:ok, :tasks_executed, length(tasks)}
              end
            else
              {:ok, :tasks_executed, length(tasks)}
            end

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
  #
  # Retrieves the step function from the workflow definition and executes it with a configurable
  # timeout using Task.async/yield pattern. Catches any exceptions and converts them to error
  # tuples for consistent error handling. Upon completion (success or failure), calls
  # complete_task_success/5 or complete_task_failure/5 to update the database state.
  #
  # Timeout handling: If a task exceeds the timeout (in milliseconds), Task.shutdown(:brutal_kill)
  # is called to terminate it and an error tuple is returned.
  #
  # Exception handling: Any exception (throw, error, exit) is caught and converted to
  # {:error, {:exception, {kind, error}}} tuple for logging and recovery.
  @spec execute_task_from_map(map(), WorkflowDefinition.t(), module(), integer()) ::
          {:ok, :task_executed} | {:error, term()}
  defp execute_task_from_map(task_map, definition, repo, task_timeout_ms) do
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

    # Execute step function with configurable timeout
    result =
      try do
        task_with_timeout = Task.async(fn -> step_fn.(input) end)

        case Task.yield(task_with_timeout, task_timeout_ms) do
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

  # Complete task successfully (using QuantumFlow complete_task function)
  #
  # Calls the PostgreSQL complete_task stored function to mark the task as successfully
  # executed and store the output. This function handles dependency counters, task queue
  # updates, and may trigger execution of dependent steps if this task's step is now complete.
  #
  # Returns {:ok, :task_executed} on success, or {:error, reason} if the database call fails.
  @spec complete_task_success(Ecto.UUID.t(), String.t(), integer(), map(), module()) ::
          {:ok, :task_executed} | {:error, term()}
  defp complete_task_success(run_id, step_slug, task_index, output, repo) do
    # Call PostgreSQL complete_task function
    # Set timeout to 15 seconds to prevent transaction deadlock hangs
    result =
      repo.query(
        "SELECT complete_task($1::uuid, $2::text, $3::integer, $4::jsonb)",
        [run_id, step_slug, task_index, output],
        timeout: 15_000
      )

    case result do
      {:ok, _} ->
        Logger.debug("Task completed successfully",
          run_id: run_id,
          step_slug: step_slug,
          task_index: task_index
        )

        {:ok, :task_executed}

      {:error, reason} ->
        Logger.error("Failed to complete task",
          run_id: run_id,
          step_slug: step_slug,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Complete task with failure (using QuantumFlow fail_task function)
  #
  # Calls the PostgreSQL fail_task stored function to mark a task as failed with an error
  # message. This function may increment retry counters or mark the step/workflow as failed
  # depending on the failure policy configured for the step.
  #
  # Returns {:ok, :task_executed} on success, or {:error, reason} if the database call fails.
  @spec complete_task_failure(Ecto.UUID.t(), String.t(), integer(), term(), module()) ::
          {:ok, :task_executed} | {:error, term()}
  defp complete_task_failure(run_id, step_slug, task_index, reason, repo) do
    error_message = inspect(reason)

    # Call PostgreSQL fail_task function
    # Set timeout to 15 seconds to prevent transaction deadlock hangs
    result =
      repo.query(
        "SELECT Singularity.Workflow.fail_task($1::uuid, $2::text, $3::integer, $4::text)",
        [run_id, step_slug, task_index, error_message],
        timeout: 15_000
      )

    case result do
      {:ok, _} ->
        Logger.warning("Task failed",
          run_id: run_id,
          step_slug: step_slug,
          task_index: task_index,
          reason: error_message
        )

        {:ok, :task_executed}

      {:error, db_reason} ->
        Logger.error("Failed to mark task as failed",
          run_id: run_id,
          step_slug: step_slug,
          reason: inspect(db_reason)
        )

        {:error, db_reason}
    end
  end

  # Check run status to determine if execution is complete
  @spec check_run_status(Ecto.UUID.t(), module()) ::
          {:ok, map()} | {:ok, :in_progress} | {:error, term()}
  defp check_run_status(run_id, repo) do
    case repo.get(WorkflowRun, run_id) do
      nil ->
        Logger.error("Run not found", run_id: run_id)
        {:error, {:run_not_found, run_id}}

      run ->
        case run.status do
          "completed" ->
            Logger.info("Run completed", run_id: run_id)
            {:ok, run.output || %{}}

          "failed" ->
            Logger.error("Run failed", run_id: run_id, error: run.error_message)
            {:error, {:run_failed, run.error_message}}

          "started" ->
            # Still in progress
            {:ok, :in_progress}
        end
    end
  end
end
