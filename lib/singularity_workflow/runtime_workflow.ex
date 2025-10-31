defmodule Singularity.Workflow.Runtime.Workflow do
  @moduledoc """
  Singularity.Workflow.Runtime.Workflow - Production-grade workflow orchestration module.

  Provides complete workflow lifecycle management with database-driven execution,
  real-time notifications, and Broadway producer integration.
  """

  use GenServer
  require Logger
  alias Singularity.Workflow.{Executor, Notifications}

  @doc """
  Start a workflow process for Broadway producer integration.
  """
  @spec start_link(String.t(), module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(workflow_name, workflow_module, opts \\ []) do
    repo = Keyword.get(opts, :repo) || raise "repo option required"
    producer_pid = Keyword.get(opts, :producer_pid)

    # Validate workflow module
    unless function_exported?(workflow_module, :__workflow_steps__, 0) do
      {:error, "Workflow module #{inspect(workflow_module)} must implement __workflow_steps__/0"}
    else
      # Create workflow process state
      state = %{
        workflow_name: workflow_name,
        workflow_module: workflow_module,
        repo: repo,
        producer_pid: producer_pid,
        active_runs: %{},
        created_at: DateTime.utc_now()
      }

      # Start GenServer process
      case GenServer.start_link(__MODULE__, state, name: via_tuple(workflow_name)) do
        {:ok, pid} ->
          Logger.info("Singularity.Workflow.Runtime.Workflow: Started workflow process",
            workflow_name: workflow_name,
            workflow_module: workflow_module,
            pid: inspect(pid)
          )

          {:ok, pid}

        {:error, reason} = error ->
          Logger.error("Singularity.Workflow.Runtime.Workflow: Failed to start workflow process",
            workflow_name: workflow_name,
            reason: inspect(reason)
          )

          error
      end
    end
  end

  @doc """
  Enqueue a job for workflow processing.
  """
  @spec enqueue(pid(), atom(), map()) :: {:ok, String.t()} | {:error, term()}
  def enqueue(workflow_pid, step_name, input)
      when is_pid(workflow_pid) and is_atom(step_name) and is_map(input) do
    GenServer.call(workflow_pid, {:enqueue, step_name, input}, 30_000)
  end

  @doc """
  Update job status in workflow.
  """
  @spec update(pid(), :ack | :nack | :requeue, map()) :: :ok | {:error, term()}
  def update(workflow_pid, action, job_data)
      when is_pid(workflow_pid) and action in [:ack, :nack, :requeue] and is_map(job_data) do
    job_id = Map.get(job_data, :id) || raise "job_data must contain :id"
    GenServer.call(workflow_pid, {:update, action, job_id, job_data}, 30_000)
  end

  @doc """
  Get the parent producer PID for this workflow.
  """
  @spec get_parent(pid()) :: pid() | nil
  def get_parent(workflow_pid) when is_pid(workflow_pid) do
    GenServer.call(workflow_pid, :get_parent, 5000)
  end

  # GenServer callbacks
  @impl GenServer
  def init(state) do
    Logger.debug("Singularity.Workflow.Runtime.Workflow: Initialized",
      workflow_name: state.workflow_name,
      workflow_module: state.workflow_module
    )

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:enqueue, step_name, input}, _from, state) do
    job_id = generate_job_id()

    Logger.info("Singularity.Workflow.Runtime.Workflow: Enqueuing job",
      workflow_name: state.workflow_name,
      step_name: step_name,
      job_id: job_id
    )

    # Create single-step workflow for this job
    workflow_input = Map.put(input, :_job_id, job_id)
    workflow_input = Map.put(workflow_input, :_step_name, step_name)

    # Execute via Singularity.Workflow.Executor
    case Executor.execute(state.workflow_module, workflow_input, state.repo, timeout: 300_000) do
      {:ok, result} ->
        # Send real-time notification
        Notifications.send_with_notify(
          "workflow_jobs",
          %{
            type: "job_completed",
            workflow_name: state.workflow_name,
            job_id: job_id,
            step_name: step_name,
            result: result
          },
          state.repo
        )

        {:reply, {:ok, job_id}, state}

      {:error, reason} ->
        Logger.error("Singularity.Workflow.Runtime.Workflow: Job execution failed",
          workflow_name: state.workflow_name,
          job_id: job_id,
          step_name: step_name,
          reason: inspect(reason)
        )

        # Send failure notification
        Notifications.send_with_notify(
          "workflow_jobs",
          %{
            type: "job_failed",
            workflow_name: state.workflow_name,
            job_id: job_id,
            step_name: step_name,
            error: inspect(reason)
          },
          state.repo
        )

        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:update, action, job_id, job_data}, _from, state) do
    Logger.debug("Singularity.Workflow.Runtime.Workflow: Processing update",
      workflow_name: state.workflow_name,
      action: action,
      job_id: job_id
    )

    # Send notification for job status update
    notification_data = %{
      type: "job_#{action}",
      workflow_name: state.workflow_name,
      job_id: job_id,
      timestamp: DateTime.utc_now()
    }

    # Add additional metadata
    notification_data =
      case action do
        :nack -> Map.put(notification_data, :reason, Map.get(job_data, :reason))
        :requeue -> Map.put(notification_data, :delay, Map.get(job_data, :delay))
        _ -> notification_data
      end

    Notifications.send_with_notify("workflow_jobs", notification_data, state.repo)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:get_parent, _from, state) do
    {:reply, state.producer_pid, state}
  end

  @doc """
  Execute a function with retry and optional timeout semantics.

  This helper is intended for workflow steps that may fail transiently.
  """
  @spec run_with_resilience((-> any), keyword()) :: any
  def run_with_resilience(fun, opts \\ []) when is_function(fun, 0) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 60_000)
    retry_opts = Keyword.get(opts, :retry_opts, [])
    operation = Keyword.get(opts, :operation, :workflow_operation)

    max_retries = Keyword.get(retry_opts, :max_retries, 0)
    base_delay = Keyword.get(retry_opts, :base_delay_ms, 500)
    max_delay = Keyword.get(retry_opts, :max_delay_ms, base_delay * 5)

    execute_with_retries(fun, operation, timeout_ms, max_retries, base_delay, max_delay, 0)
  end

  defp execute_with_retries(fun, operation, timeout_ms, max_retries, base_delay, max_delay, attempt) do
    result =
      try do
        task = Task.async(fun)

        case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
          {:ok, value} ->
            value

          {:exit, reason} ->
            {:error, {:exit, reason}}

          nil ->
            {:error, :timeout}
        end
      rescue
        exception ->
          {:error, {:exception, exception, __STACKTRACE__}}
      catch
        kind, reason ->
          {:error, {kind, reason}}
      end

    case result do
      {:ok, _} = ok ->
        ok

      :ok ->
        :ok

      {:error, reason} ->
        maybe_retry(fun, operation, timeout_ms, max_retries, base_delay, max_delay, attempt, reason)

      other ->
        {:ok, other}
    end
  end

  defp maybe_retry(fun, operation, timeout_ms, max_retries, base_delay, max_delay, attempt, reason) do
    if attempt < max_retries do
      next_attempt = attempt + 1
      delay_ms = calculate_delay(base_delay, max_delay, next_attempt)

      Logger.warning("Singularity.Workflow.Runtime.Workflow: retrying operation",
        operation: operation,
        attempt: next_attempt,
        max_retries: max_retries,
        reason: inspect(reason),
        delay_ms: delay_ms
      )

      Process.sleep(delay_ms)

      execute_with_retries(
        fun,
        operation,
        timeout_ms,
        max_retries,
        base_delay,
        max_delay,
        next_attempt
      )
    else
      Logger.error("Singularity.Workflow.Runtime.Workflow: operation failed",
        operation: operation,
        attempts: attempt + 1,
        reason: inspect(reason)
      )

      {:error, reason}
    end
  end

  defp calculate_delay(base_delay, max_delay, attempt) do
    delay =
      base_delay
      |> Kernel.*(:math.pow(2, attempt - 1))
      |> round()

    min(delay, max_delay)
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("Singularity.Workflow.Runtime.Workflow: Terminating",
      workflow_name: state.workflow_name,
      reason: inspect(reason)
    )
  end

  # Private functions

  # Generate unique job ID
  defp generate_job_id do
    # Use UUID v7 for time-ordered uniqueness
    uuid = Ecto.UUID.bingenerate()
    uuid
  end

  # Registry name for workflow processes
  defp via_tuple(workflow_name) do
    {:via, Registry, {Singularity.Workflow.Runtime.WorkflowRegistry, workflow_name}}
  end

  # Macro for workflow modules
  defmacro __using__(_opts \\ []) do
    quote do
      # Default implementation of __workflow_steps__/0
      def __workflow_steps__, do: []

      # Import common functions
      import Singularity.Workflow.Runtime.Workflow,
        only: [
          start_link: 3,
          enqueue: 3,
          update: 3,
          get_parent: 1,
          run_with_resilience: 2
        ]

      defoverridable __workflow_steps__: 0
    end
  end
end
