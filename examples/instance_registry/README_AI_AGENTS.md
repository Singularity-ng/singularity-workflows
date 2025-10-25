# AI Agent Registry for ex_pgflow

**PRODUCTION-READY** agent registry for multi-agent AI systems. Track agent instances, execution history, LLM costs, and tool usage patterns.

## Features

- ✅ **Agent Instance Tracking** - Which agents are online, their capacity, and current load
- ✅ **LLM Cost Tracking** - Track prompt/completion tokens and estimated USD costs per execution
- ✅ **Success Metrics** - Success rates, retry counts, average duration
- ✅ **Tool Usage Analytics** - Which tools agents use most, success rates
- ✅ **Performance Summaries** - Aggregated metrics updated automatically
- ✅ **Load Balancing** - Find least-loaded agent for task assignment
- ✅ **Heartbeat Monitoring** - Automatic offline detection for stale agents
- ✅ **Complete Implementation** - No placeholders, production-ready

## Perfect For

- Multi-agent AI systems (planner, executor, researcher, coder agents)
- LLM cost tracking and optimization
- Agent performance monitoring
- Tool usage pattern analysis
- Load balancing across agent instances

## Installation

### 1. Copy Files

```bash
cp examples/instance_registry/migration.exs priv/repo/migrations/$(date +%Y%m%d%H%M%S)_create_agent_registry.exs
cp examples/instance_registry/schemas.ex lib/your_app/agent/
cp examples/instance_registry/agent_registry.ex lib/your_app/agent/
```

### 2. Update Module Names

In all copied files, replace:
```elixir
defmodule Pgflow.Agent.Registry do
```

With your app name:
```elixir
defmodule YourApp.Agent.Registry do
```

### 3. Run Migration

```bash
mix ecto.migrate
```

### 4. Add to Supervision Tree

```elixir
# lib/your_app/application.ex
defmodule YourApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      YourApp.Repo,
      # ... other children ...

      # AI Agent Registry
      {YourApp.Agent.Registry,
       repo: YourApp.Repo,
       agent_config: %{
         heartbeat_interval: 5_000,
         stale_timeout: 300
       }}
    ]

    opts = [strategy: :one_for_one, name: YourApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Usage Examples

### Register an Agent

```elixir
alias YourApp.Agent.Registry

# Register a planner agent
{:ok, agent} = Registry.register(%{
  agent_id: "agent_planner_1",
  agent_type: "planner",
  llm_provider: "claude",
  model_name: "claude-3-5-sonnet-20241022",
  temperature: 0.7,
  max_tokens: 8000,
  max_capacity: 10  # Can handle 10 concurrent tasks
})
```

### Track Execution with Costs

```elixir
# Start tracking an execution
{:ok, execution_id} = Registry.start_execution(
  "agent_planner_1",
  %{
    workflow_slug: "code_analysis",
    task_type: "planning",
    run_id: workflow_run_id
  }
)

# Agent does work...
# Call LLM, get response with token counts

# Complete execution with metrics
{:ok, execution} = Registry.complete_execution(
  execution_id,
  :success,
  %{
    prompt_tokens: 1500,
    completion_tokens: 800,
    total_tokens: 2300,
    estimated_cost_usd: 0.045,  # Based on your LLM pricing
    success_score: 0.95         # 0.0 to 1.0
  }
)
```

### Track Tool Usage

```elixir
# Record that agent used a tool
{:ok, usage} = Registry.record_tool_usage(
  "agent_planner_1",
  "code_search",
  %{
    execution_id: execution_id,
    success_count: 1,
    avg_duration_ms: 250.0
  }
)
```

### Load Balancing

```elixir
# Get least loaded planner agent
{:ok, agent} = Registry.get_least_loaded_agent("planner")

if agent do
  # Assign task to this agent
  assign_task(agent.agent_id, task)

  # Update load
  Registry.update_load(agent.agent_id, agent.current_load + 1)
else
  # All planners at capacity, queue task
  queue_task(task)
end
```

### Query Performance

```elixir
# Get agent performance summary
{:ok, perf} = Registry.get_performance("agent_planner_1")

%{
  total_executions: 1250,
  successful_executions: 1180,
  failed_executions: 70,
  success_rate: 0.944,
  avg_duration_ms: 3200.5,
  total_tokens_used: 2_850_000,
  total_cost_usd: 142.50,
  last_execution_at: ~U[2025-01-15 14:23:10Z]
}
```

### List Online Agents

```elixir
{:ok, agents} = Registry.list_online_agents()

Enum.each(agents, fn agent ->
  IO.puts("#{agent.agent_id}: #{agent.current_load}/#{agent.max_capacity} (#{agent.agent_type})")
end)

# Output:
# agent_planner_1: 3/10 (planner)
# agent_executor_1: 7/10 (executor)
# agent_researcher_1: 1/10 (researcher)
```

## Database Schema

### agent_instances

Tracks which agents are currently running:

| Column | Type | Description |
|--------|------|-------------|
| agent_id | text (PK) | Unique agent identifier |
| agent_type | text | Type: planner, executor, researcher, etc. |
| status | text | online, offline, paused, busy |
| current_load | integer | Number of active tasks |
| max_capacity | integer | Maximum concurrent tasks |
| llm_provider | text | claude, openai, gemini, etc. |
| model_name | text | Model identifier |
| last_heartbeat | timestamp | Last health check |

### agent_executions

Tracks individual task executions with costs:

| Column | Type | Description |
|--------|------|-------------|
| id | uuid (PK) | Execution identifier |
| agent_id | text (FK) | Which agent executed |
| task_type | text | planning, code_generation, analysis, etc. |
| status | text | success, failed, timeout |
| duration_ms | integer | Execution duration |
| prompt_tokens | integer | Input tokens |
| completion_tokens | integer | Output tokens |
| estimated_cost_usd | float | Estimated LLM API cost |
| success_score | float | 0.0 to 1.0 quality metric |

### agent_tool_usage

Tracks which tools agents use:

| Column | Type | Description |
|--------|------|-------------|
| agent_id | text (FK) | Which agent |
| tool_name | text | code_search, file_edit, bash, etc. |
| invocation_count | integer | How many times called |
| success_count | integer | Successful calls |
| failure_count | integer | Failed calls |

### agent_performance_summary

Aggregated metrics (updated every 60 seconds):

| Column | Type | Description |
|--------|------|-------------|
| agent_id | text (PK) | Which agent |
| total_executions | integer | Total runs |
| success_rate | float | successful / total |
| avg_duration_ms | float | Average execution time |
| total_cost_usd | float | Cumulative LLM costs |

## Integration with ex_pgflow Workflows

### Track Agent Execution in Workflows

```elixir
defmodule MyApp.Agents.PlannerAgent do
  @agent_id "planner_#{Node.self()}"

  def execute(workflow_slug, run_id, task) do
    # Start tracking
    {:ok, execution_id} = Agent.Registry.start_execution(@agent_id, %{
      workflow_slug: workflow_slug,
      run_id: run_id,
      task_type: "planning"
    })

    try do
      # Do LLM call
      result = call_llm(task)

      # Complete with metrics
      Agent.Registry.complete_execution(execution_id, :success, %{
        prompt_tokens: result.usage.prompt_tokens,
        completion_tokens: result.usage.completion_tokens,
        total_tokens: result.usage.total_tokens,
        estimated_cost_usd: calculate_cost(result.usage),
        success_score: evaluate_quality(result)
      })

      {:ok, result}
    rescue
      error ->
        Agent.Registry.complete_execution(execution_id, :failed, %{
          error_message: Exception.message(error),
          retry_count: task.attempt
        })

        {:error, error}
    end
  end

  defp calculate_cost(usage) do
    # Claude Sonnet 3.5 pricing (example)
    prompt_cost = usage.prompt_tokens / 1_000_000 * 3.00
    completion_cost = usage.completion_tokens / 1_000_000 * 15.00
    prompt_cost + completion_cost
  end
end
```

### Dashboard Integration

Use with Phoenix LiveView dashboard:

```elixir
defmodule MyAppWeb.AgentDashboardLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(2000, self(), :refresh)
    end

    {:ok, load_data(socket)}
  end

  defp load_data(socket) do
    {:ok, agents} = Agent.Registry.list_online_agents()

    agents_with_perf = Enum.map(agents, fn agent ->
      {:ok, perf} = Agent.Registry.get_performance(agent.agent_id)
      Map.put(agent, :performance, perf)
    end)

    socket
    |> assign(:agents, agents_with_perf)
    |> assign(:total_cost, Enum.sum_by(agents_with_perf, & &1.performance.total_cost_usd))
  end
end
```

## Cost Optimization Strategies

### 1. Route Tasks by Complexity

```elixir
def assign_task(task) do
  agent_type = case task.complexity do
    :simple -> "lightweight"      # GPT-4o-mini, cheap
    :medium -> "standard"          # Claude Haiku
    :complex -> "advanced"         # Claude Opus, expensive
  end

  {:ok, agent} = Registry.get_least_loaded_agent(agent_type)
  execute_on_agent(agent, task)
end
```

### 2. Monitor Cost per Task Type

```elixir
defmodule MyApp.CostAnalyzer do
  def analyze_costs do
    from(e in Execution,
      select: %{
        task_type: e.task_type,
        avg_cost: avg(e.estimated_cost_usd),
        total_cost: sum(e.estimated_cost_usd),
        count: count(e.id)
      },
      group_by: e.task_type,
      order_by: [desc: sum(e.estimated_cost_usd)]
    )
    |> Repo.all()
  end
end
```

### 3. Set Cost Budgets

```elixir
def execute_with_budget(agent_id, task, max_cost_usd) do
  {:ok, perf} = Registry.get_performance(agent_id)

  if perf.avg_cost_per_execution > max_cost_usd do
    {:error, :exceeds_budget}
  else
    execute(agent_id, task)
  end
end
```

## Monitoring & Alerts

### Check for Stale Agents

```elixir
# Agents are automatically marked offline after 5 minutes of no heartbeat
# But you can also manually check:

defmodule MyApp.AgentMonitor do
  def check_health do
    stale_threshold = DateTime.add(DateTime.utc_now(), -60, :second)

    stale_agents =
      from(a in Instance,
        where: a.status == "online" and a.last_heartbeat < ^stale_threshold
      )
      |> Repo.all()

    if length(stale_agents) > 0 do
      send_alert("#{length(stale_agents)} agents appear unhealthy")
    end
  end
end
```

### Monitor Success Rates

```elixir
def check_success_rates do
  low_performers =
    from(p in PerformanceSummary,
      where: p.success_rate < 0.80 and p.total_executions > 10
    )
    |> Repo.all()

  Enum.each(low_performers, fn perf ->
    Logger.warning("Agent #{perf.agent_id} has low success rate: #{perf.success_rate}")
  end)
end
```

## Configuration

```elixir
# config/config.exs
config :your_app, YourApp.Agent.Registry,
  heartbeat_interval: 5_000,   # 5 seconds
  stale_timeout: 300,           # 5 minutes
  performance_update_interval: 60_000  # 1 minute
```

## Testing

```elixir
# test/agent/registry_test.exs
defmodule YourApp.Agent.RegistryTest do
  use YourApp.DataCase, async: false

  alias YourApp.Agent.Registry

  setup do
    # Start registry for test
    start_supervised!({Registry, repo: YourApp.Repo, agent_config: %{}})
    :ok
  end

  test "registers and tracks agent execution" do
    # Register agent
    {:ok, agent} = Registry.register(%{
      agent_id: "test_agent",
      agent_type: "planner",
      llm_provider: "claude",
      model_name: "claude-3-5-sonnet",
      max_capacity: 10
    })

    assert agent.agent_id == "test_agent"

    # Start execution
    {:ok, exec_id} = Registry.start_execution("test_agent", %{
      task_type: "planning"
    })

    # Complete execution
    {:ok, execution} = Registry.complete_execution(exec_id, :success, %{
      prompt_tokens: 100,
      completion_tokens: 50,
      estimated_cost_usd: 0.01
    })

    assert execution.status == "success"
    assert execution.total_tokens == 150

    # Check performance summary
    {:ok, perf} = Registry.get_performance("test_agent")
    assert perf.total_executions == 1
    assert perf.success_rate == 1.0
  end
end
```

## See Also

- [Phoenix Dashboard Example](../phoenix_dashboard/) - Visualize agent metrics
- [ex_pgflow Architecture](../../ARCHITECTURE.md) - How workflows execute
- [Workflow Integration](../../GETTING_STARTED.md) - Using agents with ex_pgflow
