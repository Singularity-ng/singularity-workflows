defmodule QuantumFlow.Orchestrator.Executor do
  @moduledoc """
  HTDAG-specific workflow executor with enhanced monitoring and error handling.

  Extends the base quantum_flow executor with HTDAG-specific features:
  - Real-time event broadcasting
  - Task-level monitoring and metrics
  - Enhanced error handling and recovery
  - Performance tracking and optimization
  """

  require Logger
  alias QuantumFlow.Orchestrator.Repository

  @doc """
  Execute an HTDAG workflow with enhanced monitoring.

  ## Parameters

  - `workflow` - HTDAG workflow definition
  - `context` - Execution context (goal, parameters, etc.)
  - `repo` - Ecto repository
  - `opts` - Execution options
    - `:execution_id` - Custom execution ID (auto-generated if not provided)
    - `:monitor` - Enable real-time monitoring (default: true)
    - `:timeout` - Execution timeout in milliseconds (default: 300_000)
    - `:retry_failed_tasks` - Retry failed tasks automatically (default: true)

  ## Returns

  - `{:ok, result}` - Workflow executed successfully
  - `{:error, reason}` - Execution failed

  ## Example

      {:ok, result} = QuantumFlow.Orchestrator.Executor.execute_workflow(
        workflow,
        %{goal: "Build auth system"},
        MyApp.Repo,
        monitor: true,
        timeout: 600_000
      )
  """
  @spec execute_workflow(map(), map(), Ecto.Repo.t(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def execute_workflow(workflow, context, repo, opts \\ []) do
    execution_id = Keyword.get(opts, :execution_id, generate_execution_id())
    monitor = Keyword.get(opts, :monitor, true)
    timeout = Keyword.get(opts, :timeout, 300_000)
    retry_failed_tasks = Keyword.get(opts, :retry_failed_tasks, true)

    Logger.info("Starting HTDAG workflow execution: #{workflow.name} (#{execution_id})")

    # Create execution record
    with {:ok, execution} <- create_execution_record(workflow, context, execution_id, repo),
         {:ok, result} <-
           execute_with_monitoring(workflow, context, execution, repo,
             monitor: monitor,
             timeout: timeout,
             retry_failed_tasks: retry_failed_tasks
           ) do
      Logger.info("HTDAG workflow execution completed: #{execution_id}")
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("HTDAG workflow execution failed: #{execution_id} - #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Execute a single task within an HTDAG workflow.

  ## Parameters

  - `task_config` - Task configuration
  - `context` - Execution context
  - `execution` - Parent execution record
  - `repo` - Ecto repository
  - `opts` - Task execution options

  ## Returns

  - `{:ok, result}` - Task executed successfully
  - `{:error, reason}` - Task execution failed
  """
  @spec execute_task(map(), map(), map(), Ecto.Repo.t(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def execute_task(task_config, context, execution, repo, _opts \\ []) do
    task_id = task_config.name
    task_name = task_config.description || to_string(task_id)
    timeout = Map.get(task_config, :timeout, 30_000)
    max_attempts = Map.get(task_config, :max_attempts, 3)
    retry_delay = Map.get(task_config, :retry_delay, 1_000)

    Logger.info("Executing HTDAG task: #{task_name} (#{task_id})")

    # Create task execution record
    with {:ok, task_execution} <- create_task_execution_record(task_id, task_name, execution, repo),
         {:ok, result} <-
           execute_task_with_retries(task_config, context, task_execution, repo,
             timeout: timeout,
             max_attempts: max_attempts,
             retry_delay: retry_delay
           ) do
      Logger.info("HTDAG task completed: #{task_name} (#{task_id})")
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("HTDAG task failed: #{task_name} (#{task_id}) - #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get execution status and progress.

  ## Parameters

  - `execution_id` - Execution ID
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, status}` - Execution status and progress
  - `{:error, reason}` - Failed to get status
  """
  @spec get_execution_status(String.t(), Ecto.Repo.t()) :: {:ok, map()} | {:error, any()}
  def get_execution_status(execution_id, repo) do
    with {:ok, execution} <- Repository.get_execution(execution_id, repo),
         {:ok, task_executions} <- get_task_executions(execution_id, repo) do
      status = %{
        execution_id: execution_id,
        status: execution.status,
        started_at: execution.started_at,
        completed_at: execution.completed_at,
        duration_ms: execution.duration_ms,
        total_tasks: length(task_executions),
        completed_tasks: Enum.count(task_executions, &(&1.status == "completed")),
        failed_tasks: Enum.count(task_executions, &(&1.status == "failed")),
        running_tasks: Enum.count(task_executions, &(&1.status == "running")),
        pending_tasks: Enum.count(task_executions, &(&1.status == "pending")),
        progress_percentage: calculate_progress_percentage(task_executions),
        task_statuses:
          Enum.map(
            task_executions,
            &%{
              task_id: &1.task_id,
              status: &1.status,
              started_at: &1.started_at,
              completed_at: &1.completed_at,
              duration_ms: &1.duration_ms,
              error_message: &1.error_message
            }
          )
      }

      {:ok, status}
    end
  end

  @doc """
  Cancel a running execution.

  ## Parameters

  - `execution_id` - Execution ID to cancel
  - `repo` - Ecto repository
  - `opts` - Cancellation options
    - `:reason` - Cancellation reason
    - `:force` - Force cancellation even if tasks are running

  ## Returns

  - `:ok` - Execution cancelled successfully
  - `{:error, reason}` - Cancellation failed
  """
  @spec cancel_execution(String.t(), Ecto.Repo.t(), keyword()) :: :ok | {:error, any()}
  def cancel_execution(execution_id, repo, opts \\ []) do
    reason = Keyword.get(opts, :reason, "User requested cancellation")
    force = Keyword.get(opts, :force, false)

    Logger.info("Cancelling HTDAG execution: #{execution_id}")

    with {:ok, execution} <- Repository.get_execution(execution_id, repo),
         :ok <- validate_cancellation(execution, force),
         {:ok, _} <-
           Repository.update_execution_status(execution, "cancelled", repo, error_message: reason) do
      # Cancel running tasks
      cancel_running_tasks(execution_id, repo)

      # Broadcast cancellation event
      QuantumFlow.OrchestratorNotifications.broadcast_workflow(
        execution_id,
        :cancelled,
        %{reason: reason},
        repo
      )

      Logger.info("HTDAG execution cancelled: #{execution_id}")
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to cancel HTDAG execution: #{execution_id} - #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp create_execution_record(workflow, context, execution_id, repo) do
    attrs = %{
      execution_id: execution_id,
      workflow_id: workflow.id,
      goal_context: context,
      status: "running",
      started_at: DateTime.utc_now()
    }

    Repository.create_execution(attrs, repo)
  end

  defp create_task_execution_record(task_id, task_name, execution, repo) do
    attrs = %{
      execution_id: execution.id,
      task_id: to_string(task_id),
      task_name: task_name,
      status: "pending"
    }

    Repository.create_task_execution(attrs, repo)
  end

  defp execute_with_monitoring(workflow, context, execution, repo, opts) do
    monitor = Keyword.get(opts, :monitor)
    timeout = Keyword.get(opts, :timeout, 30_000)
    _retry_failed_tasks = Keyword.get(opts, :retry_failed_tasks)

    # Start monitoring if enabled
    if monitor do
      QuantumFlow.OrchestratorNotifications.broadcast_workflow(
        execution.execution_id,
        :started,
        %{
          workflow_name: workflow.name,
          goal: context[:goal]
        },
        repo
      )
    end

    # Execute workflow using base executor with timeout
    case Task.await(
           Task.async(fn -> QuantumFlow.Executor.execute(workflow, context, repo) end),
           timeout
         ) do
      {:ok, result} ->
        # Update execution status
        duration_ms = DateTime.diff(DateTime.utc_now(), execution.started_at, :millisecond)

        Repository.update_execution_status(execution, "completed", repo,
          completed_at: DateTime.utc_now(),
          duration_ms: duration_ms,
          result: result
        )

        # Broadcast completion event
        if monitor do
          QuantumFlow.OrchestratorNotifications.broadcast_workflow(
            execution.execution_id,
            :completed,
            %{
              result: result,
              duration_ms: duration_ms
            },
            repo
          )
        end

        {:ok, result}

      {:error, reason} ->
        # Update execution status
        Repository.update_execution_status(execution, "failed", repo,
          completed_at: DateTime.utc_now(),
          error_message: inspect(reason)
        )

        # Broadcast failure event
        if monitor do
          QuantumFlow.OrchestratorNotifications.broadcast_workflow(
            execution.execution_id,
            :failed,
            %{
              error: inspect(reason)
            },
            repo
          )
        end

        {:error, reason}
    end
  end

  defp execute_task_with_retries(task_config, context, task_execution, repo, opts) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    retry_delay = Keyword.get(opts, :retry_delay, 1_000)
    timeout = Keyword.get(opts, :timeout, 30_000)

    execute_with_retries(
      task_config,
      context,
      task_execution,
      repo,
      max_attempts,
      retry_delay,
      timeout,
      0
    )
  end

  defp execute_with_retries(
         task_config,
         context,
         task_execution,
         repo,
         max_attempts,
         retry_delay,
         timeout,
         attempt
       ) do
    if attempt >= max_attempts do
      {:error, :max_retries_exceeded}
    else
      # Update task status to running
      Repository.update_task_execution_status(task_execution, "running", repo,
        started_at: DateTime.utc_now(),
        retry_count: attempt
      )

      # Broadcast task started event
      QuantumFlow.OrchestratorNotifications.broadcast_task(
        task_execution.task_id,
        :started,
        %{
          attempt: attempt + 1,
          max_attempts: max_attempts
        },
        repo
      )

      # Execute task with timeout
      case execute_task_with_timeout(task_config, context, timeout) do
        {:ok, result} ->
          # Update task status to completed
          duration_ms = DateTime.diff(DateTime.utc_now(), task_execution.started_at, :millisecond)

          Repository.update_task_execution_status(task_execution, "completed", repo,
            completed_at: DateTime.utc_now(),
            duration_ms: duration_ms,
            result: result
          )

          # Broadcast task completed event
          QuantumFlow.OrchestratorNotifications.broadcast_task(
            task_execution.task_id,
            :completed,
            %{
              result: result,
              duration_ms: duration_ms
            },
            repo
          )

          {:ok, result}

        {:error, reason} ->
          # Update task status to failed
          Repository.update_task_execution_status(task_execution, "failed", repo,
            error_message: inspect(reason)
          )

          # Broadcast task failed event
          QuantumFlow.OrchestratorNotifications.broadcast_task(
            task_execution.task_id,
            :failed,
            %{
              error: inspect(reason),
              attempt: attempt + 1
            },
            repo
          )

          # Retry if attempts remaining
          if attempt < max_attempts - 1 do
            Process.sleep(retry_delay)

            execute_with_retries(
              task_config,
              context,
              task_execution,
              repo,
              max_attempts,
              retry_delay,
              timeout,
              attempt + 1
            )
          else
            {:error, reason}
          end
      end
    end
  end

  defp execute_task_with_timeout(task_config, context, timeout) do
    task =
      Task.async(fn ->
        task_config.function.(context)
      end)

    case Task.yield(task, timeout) do
      {:ok, result} ->
        result

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}

      {:exit, reason} ->
        {:error, reason}
    end
  end

  defp get_task_executions(execution_id, repo) do
    import Ecto.Query

    query =
      from(te in QuantumFlow.Orchestrator.Schemas.TaskExecution,
        where: te.execution_id == ^execution_id,
        order_by: [asc: te.inserted_at],
        select: te
      )

    task_executions = repo.all(query)
    {:ok, task_executions}
  rescue
    error ->
      Logger.error("Failed to fetch task executions: #{inspect(error)}")
      {:error, error}
  end

  defp calculate_progress_percentage(task_executions) do
    total = length(task_executions)

    if total == 0 do
      0.0
    else
      completed = Enum.count(task_executions, &(&1.status == "completed"))
      completed / total * 100.0
    end
  end

  defp validate_cancellation(execution, force) do
    if execution.status == "running" or force do
      :ok
    else
      {:error, :execution_not_running}
    end
  end

  defp cancel_running_tasks(execution_id, repo) do
    import Ecto.Query

    # Update all running tasks to cancelled status
    query =
      from(te in QuantumFlow.Orchestrator.Schemas.TaskExecution,
        where: te.execution_id == ^execution_id and te.status == "running",
        select: te
      )

    repo.transaction(fn ->
      # Fetch running tasks
      running_tasks = repo.all(query)

      # Cancel each running task
      Enum.each(running_tasks, fn task ->
        changeset =
          QuantumFlow.Orchestrator.Schemas.TaskExecution.task_execution_changeset(
            task,
            %{
              status: "cancelled",
              completed_at: DateTime.utc_now(),
              error_message: "Task cancelled by user request"
            }
          )

        case repo.update(changeset) do
          {:ok, _} ->
            Logger.info("Cancelled task: #{task.task_id}")

          {:error, error} ->
            Logger.error("Failed to cancel task #{task.task_id}: #{inspect(error)}")
            repo.rollback(error)
        end
      end)

      Logger.info("Cancelled #{length(running_tasks)} running tasks for execution #{execution_id}")
    end)

    :ok
  rescue
    error ->
      Logger.error("Failed to cancel running tasks: #{inspect(error)}")
      {:error, error}
  end

  defp generate_execution_id do
    "htdag_#{:erlang.system_time(:millisecond)}_#{:rand.uniform(10000)}"
  end
end
