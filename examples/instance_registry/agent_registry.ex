defmodule Pgflow.Agent.Registry do
  @moduledoc """
  **PRODUCTION-READY** AI Agent Registry for ex_pgflow.

  Tracks AI agent instances, execution history, cost metrics, and tool usage.
  Optimized for multi-agent AI systems with LLM cost tracking and success metrics.

  ## Features

  - ✅ Agent instance registration & heartbeat
  - ✅ LLM provider & model tracking
  - ✅ Cost tracking (prompt/completion tokens, estimated USD)
  - ✅ Success rate metrics
  - ✅ Tool usage patterns
  - ✅ Performance summaries
  - ✅ Load balancing support (current_load / max_capacity)

  ## Usage

  Add to your supervision tree:

      children = [
        YourApp.Repo,
        {Pgflow.Agent.Registry, repo: YourApp.Repo, agent_config: agent_config()}
      ]

  Register an agent:

      Pgflow.Agent.Registry.register(%{
        agent_id: "agent_planner_1",
        agent_type: "planner",
        llm_provider: "claude",
        model_name: "claude-3-5-sonnet-20241022",
        max_capacity: 10
      })

  Track execution:

      {:ok, execution_id} = Pgflow.Agent.Registry.start_execution(
        "agent_planner_1",
        %{
          workflow_slug: "code_analysis",
          task_type: "planning",
          run_id: run_id
        }
      )

      # ... agent does work ...

      Pgflow.Agent.Registry.complete_execution(execution_id, :success, %{
        prompt_tokens: 1500,
        completion_tokens: 800,
        estimated_cost_usd: 0.045,
        success_score: 0.95
      })

  Query metrics:

      {:ok, stats} = Pgflow.Agent.Registry.get_performance("agent_planner_1")
      # => %{success_rate: 0.94, avg_duration_ms: 3200, total_cost_usd: 12.50}

      {:ok, agents} = Pgflow.Agent.Registry.list_online_agents()
      # => [%{agent_id: "...", current_load: 3, max_capacity: 10}]
  """

  use GenServer
  require Logger

  alias Pgflow.Agent.{Instance, Execution, ToolUsage, PerformanceSummary}
  import Ecto.Query

  # Client API

  @doc """
  Start the Agent Registry GenServer.
  """
  def start_link(opts) do
    repo = Keyword.fetch!(opts, :repo)
    agent_config = Keyword.get(opts, :agent_config, %{})

    GenServer.start_link(__MODULE__, {repo, agent_config}, name: __MODULE__)
  end

  @doc """
  Register a new agent instance.
  """
  @spec register(map()) :: {:ok, Instance.t()} | {:error, Ecto.Changeset.t()}
  def register(attrs) do
    GenServer.call(__MODULE__, {:register, attrs})
  end

  @doc """
  Update agent heartbeat.
  """
  @spec heartbeat(String.t(), map()) :: :ok
  def heartbeat(agent_id, metrics \\ %{}) do
    GenServer.cast(__MODULE__, {:heartbeat, agent_id, metrics})
  end

  @doc """
  Update agent load (number of active tasks).
  """
  @spec update_load(String.t(), integer()) :: :ok
  def update_load(agent_id, load) do
    GenServer.cast(__MODULE__, {:update_load, agent_id, load})
  end

  @doc """
  Mark agent as offline.
  """
  @spec mark_offline(String.t()) :: :ok
  def mark_offline(agent_id) do
    GenServer.cast(__MODULE__, {:mark_offline, agent_id})
  end

  @doc """
  Start tracking an execution.
  """
  @spec start_execution(String.t(), map()) :: {:ok, Ecto.UUID.t()} | {:error, Ecto.Changeset.t()}
  def start_execution(agent_id, attrs) do
    GenServer.call(__MODULE__, {:start_execution, agent_id, attrs})
  end

  @doc """
  Complete an execution with metrics.
  """
  @spec complete_execution(Ecto.UUID.t(), :success | :failed | :timeout, map()) ::
          {:ok, Execution.t()} | {:error, Ecto.Changeset.t()}
  def complete_execution(execution_id, status, metrics \\ %{}) do
    GenServer.call(__MODULE__, {:complete_execution, execution_id, status, metrics})
  end

  @doc """
  Record tool usage.
  """
  @spec record_tool_usage(String.t(), String.t(), map()) :: {:ok, ToolUsage.t()} | {:error, Ecto.Changeset.t()}
  def record_tool_usage(agent_id, tool_name, attrs \\ %{}) do
    GenServer.call(__MODULE__, {:record_tool_usage, agent_id, tool_name, attrs})
  end

  @doc """
  List all online agents.
  """
  @spec list_online_agents() :: {:ok, [Instance.t()]}
  def list_online_agents do
    GenServer.call(__MODULE__, :list_online_agents)
  end

  @doc """
  Get agent performance summary.
  """
  @spec get_performance(String.t()) :: {:ok, PerformanceSummary.t() | nil}
  def get_performance(agent_id) do
    GenServer.call(__MODULE__, {:get_performance, agent_id})
  end

  @doc """
  Get least loaded agent of a specific type.
  """
  @spec get_least_loaded_agent(String.t()) :: {:ok, Instance.t() | nil}
  def get_least_loaded_agent(agent_type) do
    GenServer.call(__MODULE__, {:get_least_loaded_agent, agent_type})
  end

  # GenServer Callbacks

  @impl true
  def init({repo, agent_config}) do
    Logger.info("Pgflow.Agent.Registry: Starting registry", repo: repo)

    # Schedule periodic tasks
    schedule_heartbeat_check()
    schedule_performance_update()

    state = %{
      repo: repo,
      agent_config: agent_config,
      heartbeat_interval: 5_000,
      stale_timeout: 300  # 5 minutes
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register, attrs}, _from, state) do
    result =
      %Instance{}
      |> Instance.online_changeset(attrs)
      |> state.repo.insert(
        on_conflict: {:replace, [:status, :hostname, :pid, :llm_provider, :model_name, :updated_at]},
        conflict_target: :agent_id
      )

    case result do
      {:ok, instance} ->
        Logger.info("Agent registered", agent_id: instance.agent_id, type: instance.agent_type)
        {:reply, {:ok, instance}, state}

      {:error, changeset} ->
        {:reply, {:error, changeset}, state}
    end
  end

  @impl true
  def handle_call(:list_online_agents, _from, state) do
    agents =
      from(i in Instance,
        where: i.status == "online",
        order_by: [asc: i.current_load]
      )
      |> state.repo.all()

    {:reply, {:ok, agents}, state}
  end

  @impl true
  def handle_call({:get_performance, agent_id}, _from, state) do
    performance = state.repo.get(PerformanceSummary, agent_id)
    {:reply, {:ok, performance}, state}
  end

  @impl true
  def handle_call({:get_least_loaded_agent, agent_type}, _from, state) do
    agent =
      from(i in Instance,
        where: i.agent_type == ^agent_type and i.status == "online",
        where: i.current_load < i.max_capacity,
        order_by: [asc: fragment("CAST(? AS FLOAT) / ?", i.current_load, i.max_capacity)],
        limit: 1
      )
      |> state.repo.one()

    {:reply, {:ok, agent}, state}
  end

  @impl true
  def handle_call({:start_execution, agent_id, attrs}, _from, state) do
    result =
      attrs
      |> Map.put(:agent_id, agent_id)
      |> Execution.start_changeset()
      |> state.repo.insert()

    case result do
      {:ok, execution} ->
        Logger.debug("Execution started", execution_id: execution.id, agent_id: agent_id)
        {:reply, {:ok, execution.id}, state}

      {:error, changeset} ->
        {:reply, {:error, changeset}, state}
    end
  end

  @impl true
  def handle_call({:complete_execution, execution_id, status, metrics}, _from, state) do
    execution = state.repo.get!(Execution, execution_id)

    result =
      execution
      |> Execution.complete_changeset(Atom.to_string(status), metrics)
      |> state.repo.update()

    case result do
      {:ok, execution} ->
        Logger.debug("Execution completed",
          execution_id: execution.id,
          status: status,
          duration_ms: execution.duration_ms
        )

        # Update performance summary asynchronously
        Task.start(fn -> update_performance_summary(state.repo, execution.agent_id) end)

        {:reply, {:ok, execution}, state}

      {:error, changeset} ->
        {:reply, {:error, changeset}, state}
    end
  end

  @impl true
  def handle_call({:record_tool_usage, agent_id, tool_name, attrs}, _from, state) do
    result =
      attrs
      |> Map.merge(%{agent_id: agent_id, tool_name: tool_name})
      |> then(&ToolUsage.changeset(%ToolUsage{}, &1))
      |> state.repo.insert(
        on_conflict: [
          inc: [invocation_count: 1],
          inc: [success_count: attrs[:success_count] || 0],
          inc: [failure_count: attrs[:failure_count] || 0]
        ],
        conflict_target: [:agent_id, :tool_name, :execution_id]
      )

    {:reply, result, state}
  end

  @impl true
  def handle_cast({:heartbeat, agent_id, metrics}, state) do
    case state.repo.get(Instance, agent_id) do
      nil ->
        Logger.warning("Heartbeat for unknown agent", agent_id: agent_id)

      instance ->
        instance
        |> Instance.heartbeat_changeset()
        |> Ecto.Changeset.change(metrics)
        |> state.repo.update()
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:update_load, agent_id, load}, state) do
    case state.repo.get(Instance, agent_id) do
      nil ->
        Logger.warning("Load update for unknown agent", agent_id: agent_id)

      instance ->
        instance
        |> Instance.load_changeset(load)
        |> state.repo.update()
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:mark_offline, agent_id}, state) do
    from(i in Instance, where: i.agent_id == ^agent_id)
    |> state.repo.update_all(set: [status: "offline", updated_at: DateTime.utc_now()])

    Logger.info("Agent marked offline", agent_id: agent_id)

    {:noreply, state}
  end

  @impl true
  def handle_info(:check_stale_heartbeats, state) do
    stale_threshold = DateTime.add(DateTime.utc_now(), -state.stale_timeout, :second)

    {count, _} =
      from(i in Instance,
        where: i.status == "online" and i.last_heartbeat < ^stale_threshold
      )
      |> state.repo.update_all(set: [status: "offline"])

    if count > 0 do
      Logger.warning("Marked #{count} agents offline due to stale heartbeat")
    end

    schedule_heartbeat_check()
    {:noreply, state}
  end

  @impl true
  def handle_info(:update_performance_summaries, state) do
    # Update all agent performance summaries
    agent_ids =
      from(i in Instance, select: i.agent_id)
      |> state.repo.all()

    Enum.each(agent_ids, fn agent_id ->
      update_performance_summary(state.repo, agent_id)
    end)

    schedule_performance_update()
    {:noreply, state}
  end

  # Private Helpers

  defp schedule_heartbeat_check do
    Process.send_after(self(), :check_stale_heartbeats, 30_000)  # Every 30s
  end

  defp schedule_performance_update do
    Process.send_after(self(), :update_performance_summaries, 60_000)  # Every 60s
  end

  defp update_performance_summary(repo, agent_id) do
    # Compute aggregated metrics
    stats =
      from(e in Execution,
        where: e.agent_id == ^agent_id,
        select: %{
          total: count(e.id),
          successful: count(e.id, :distinct) |> filter(e.status == "success"),
          failed: count(e.id, :distinct) |> filter(e.status == "failed"),
          avg_duration: avg(e.duration_ms),
          total_tokens: sum(e.total_tokens),
          total_cost: sum(e.estimated_cost_usd),
          last_execution: max(e.started_at)
        }
      )
      |> repo.one()

    success_rate =
      if stats.total > 0, do: stats.successful / stats.total, else: 0.0

    # Upsert performance summary
    %PerformanceSummary{agent_id: agent_id}
    |> PerformanceSummary.changeset(%{
      total_executions: stats.total || 0,
      successful_executions: stats.successful || 0,
      failed_executions: stats.failed || 0,
      avg_duration_ms: stats.avg_duration,
      total_tokens_used: stats.total_tokens || 0,
      total_cost_usd: stats.total_cost || 0.0,
      success_rate: success_rate,
      last_execution_at: stats.last_execution
    })
    |> repo.insert(
      on_conflict: {:replace_all_except, [:agent_id, :inserted_at]},
      conflict_target: :agent_id
    )
  end
end
