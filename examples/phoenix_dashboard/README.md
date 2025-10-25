# Phoenix LiveView Dashboard for ex_pgflow

**Complete, production-ready** real-time monitoring dashboard for ex_pgflow workflows.

## Features

- 📊 **Real-time Metrics** - Auto-refreshes every 2 seconds
- 🔄 **Workflow Tracking** - See active, completed, and failed workflows
- 📈 **Queue Monitoring** - pgmq queue depths and backlog
- ⚡ **Task Progress** - Individual task execution status
- 🎯 **Step Visualization** - Dependency-aware step states
- 💪 **Production Ready** - Complete implementation, no placeholders

## Screenshots

### Dashboard Overview
Shows:
- Total workflows (running, completed, failed)
- Active tasks and queue depths
- Real-time progress bars
- Recent completions timeline
- Step-by-step execution details

## Installation

### 1. Add to your Phoenix app

Copy files to your project:

```bash
cp examples/phoenix_dashboard/pgflow_live.ex lib/your_app_web/live/
cp examples/phoenix_dashboard/pgflow_live.html.heex lib/your_app_web/live/
```

### 2. Add route to router.ex

```elixir
# lib/your_app_web/router.ex

scope "/", YourAppWeb do
  pipe_through :browser

  # ex_pgflow dashboard
  live "/pgflow", PgflowLive
end
```

### 3. Update module name

In `pgflow_live.ex`, change:
```elixir
defmodule YourAppWeb.PgflowLive do
```

To match your app name:
```elixir
defmodule MyApp.Web.PgflowLive do
```

### 4. Configure Repo

The dashboard uses `Pgflow.Repo` - update queries if using different Repo:

```elixir
# Change from:
alias Pgflow.Repo

# To:
alias MyApp.Repo
```

### 5. Add dependencies (if not already installed)

```elixir
# mix.exs
{:phoenix_live_view, "~> 0.20"}
```

### 6. Visit dashboard

```
http://localhost:4000/pgflow
```

## Metrics Explained

### Workflow Stats
- **Total Workflows** - All workflow executions (completed + failed + running)
- **Running** - Currently executing workflows
- **Completed/Failed** - Success rate visualization

### Task Stats
- **Total Tasks** - All tasks across all workflows
- **Running Tasks** - Currently executing (pulled from pgmq)
- **Completed/Failed** - Task-level success metrics

### Queue Depths (pgmq)
- Shows pending messages in pgmq queues
- Indicates backlog and throughput bottlenecks
- Empty = All tasks being processed in real-time

### Active Workflows
- Live execution tracking with progress bars
- Step completion ratios
- Task completion metrics
- Remaining dependencies

### Recent Completions
- Last 10 finished workflows
- Duration metrics (execution time)
- Status (completed vs failed)

### Step States
- Individual step execution details
- Task counts per step
- Dependency blocking visualization
- Failed task identification

## Customization

### Change Refresh Interval

```elixir
# Default: 2 seconds
@refresh_interval 2000

# Change to 5 seconds:
@refresh_interval 5000
```

### Add Filters

```elixir
# Add to mount/3
def mount(params, _session, socket) do
  workflow_slug = params["workflow"]
  status = params["status"]

  socket
  |> assign(:filters, %{workflow: workflow_slug, status: status})
  |> load_data()
  |> ...
end

# Update queries to use filters
defp load_active_workflows(%{filters: filters}) do
  # Add WHERE clauses based on filters
end
```

### Add Pagination

```elixir
# Add page param
def mount(%{"page" => page}, _session, socket) do
  page = String.to_integer(page || "1")

  socket
  |> assign(:page, page)
  |> assign(:per_page, 20)
  |> ...
end

# Update query with OFFSET/LIMIT
"""
...
LIMIT #{socket.assigns.per_page}
OFFSET #{(socket.assigns.page - 1) * socket.assigns.per_page}
"""
```

### Export Metrics

```elixir
# Add export endpoint
def handle_event("export_csv", _params, socket) do
  csv_data = generate_csv(socket.assigns.active_workflows)
  {:noreply, push_download(socket, csv_data, filename: "workflows.csv")}
end
```

### Add Authentication

```elixir
# In router.ex
scope "/admin", YourAppWeb do
  pipe_through [:browser, :require_admin]

  live "/pgflow", PgflowLive
end
```

## Performance Considerations

### Database Load

The dashboard queries PostgreSQL every 2 seconds. For high-traffic systems:

1. **Add indexes** (if not already present):

```sql
CREATE INDEX workflow_runs_status_idx ON workflow_runs(status);
CREATE INDEX workflow_step_tasks_status_idx ON workflow_step_tasks(status);
CREATE INDEX workflow_runs_updated_at_idx ON workflow_runs(updated_at DESC);
```

2. **Use read replicas**:

```elixir
# Configure separate read-only Repo
config :my_app, MyApp.ReadRepo,
  url: System.get_env("READ_DATABASE_URL"),
  pool_size: 5

# Update dashboard to use read replica
alias MyApp.ReadRepo, as: Repo
```

3. **Cache expensive queries**:

```elixir
defp load_stats do
  Cachex.fetch(:pgflow_cache, :stats, fn ->
    # Compute stats
    {:commit, stats, ttl: :timer.seconds(5)}
  end)
end
```

### WebSocket Connections

Each connected client opens a WebSocket. For many users:

1. **Increase connection limit** in endpoint.ex:

```elixir
socket "/live", Phoenix.LiveView.Socket,
  websocket: [
    connect_info: [:peer_data, :x_headers],
    max_frame_size: 8_000_000
  ]
```

2. **Use pub/sub** instead of individual timers:

```elixir
# Broadcast updates from single process
defmodule MyApp.PgflowMetricsBroadcaster do
  use GenServer

  def init(_) do
    :timer.send_interval(2000, :broadcast)
    {:ok, %{}}
  end

  def handle_info(:broadcast, state) do
    metrics = load_metrics()
    Phoenix.PubSub.broadcast(MyApp.PubSub, "pgflow:metrics", {:metrics, metrics})
    {:noreply, state}
  end
end

# Subscribe in LiveView
def mount(_params, _session, socket) do
  Phoenix.PubSub.subscribe(MyApp.PubSub, "pgflow:metrics")
  {:ok, socket}
end

def handle_info({:metrics, metrics}, socket) do
  {:noreply, assign(socket, :stats, metrics)}
end
```

## Troubleshooting

### "No active workflows" but workflows are running

Check that `workflow_runs` table has rows:

```sql
SELECT * FROM workflow_runs LIMIT 5;
```

### Queue depths show 0 but tasks are pending

Verify pgmq queue name:

```sql
-- Should return rows
SELECT * FROM pgmq.q_pgflow LIMIT 5;
```

The queue name is hardcoded as `pgflow` in the query. Update if using different name.

### Dashboard not auto-refreshing

WebSocket not connected. Check:
1. LiveView properly configured in endpoint.ex
2. Browser console for WebSocket errors
3. Firewall/proxy allows WebSocket connections

### Slow dashboard loads

Add database indexes (see Performance Considerations above).

## Alternative: Phoenix LiveDashboard Integration

Instead of standalone page, integrate into Phoenix.LiveDashboard:

```elixir
# lib/your_app_web/telemetry.ex
defmodule YourAppWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def metrics do
    [
      # ex_pgflow metrics
      last_value("pgflow.workflows.running"),
      last_value("pgflow.tasks.running"),
      counter("pgflow.workflows.completed"),
      counter("pgflow.workflows.failed")
    ]
  end
end

# Emit metrics in your code
:telemetry.execute([:pgflow, :workflows, :running], %{count: running_count})
```

Then view in existing LiveDashboard: `http://localhost:4000/dashboard`

## See Also

- [ex_pgflow Architecture](../../ARCHITECTURE.md) - How workflows execute
- [Instance Registry Example](../instance_registry/) - Track worker instances
- [Phoenix LiveView Docs](https://hexdocs.pm/phoenix_live_view/) - LiveView reference
