# Instance Registry Example

**IMPORTANT: This is an EXAMPLE implementation, not part of the core ex_pgflow library.**

## What This Is

An optional instance registry GenServer that tracks which ex_pgflow instances are currently running across your cluster. Useful for observability and manual coordination in production deployments.

## Why This Is An Example (Not Core Library)

ex_pgflow is a **library**, not a framework. Core workflow coordination is handled by:

- **pgmq** - Distributed task queue with automatic failover
- **PostgreSQL** - ACID guarantees and visibility timeout coordination
- **Visibility timeout pattern** - No central coordinator needed

### Multi-Instance Coordination Already Works

```
Worker 1 crashes → VT expires → Worker 2 picks up task
Multiple workers → Poll same queue → pgmq prevents duplicates
Load balancing → Automatic via queue semantics
```

See [ARCHITECTURE.md](../../ARCHITECTURE.md#visibility-timeout-vt-pattern) for details.

### Instance Registry Provides OBSERVABILITY, Not Coordination

**What it adds:**
- ✅ See which instances are alive (heartbeat monitoring)
- ✅ Track load per instance (number of executing tasks)
- ✅ Manual pause/resume of specific instances
- ✅ Debugging aid for production deployments

**What it doesn't do:**
- ❌ Not required for workflow execution
- ❌ Doesn't improve reliability (pgmq handles that)
- ❌ Doesn't coordinate task assignment (queue does that)

## When To Use This

**Use if you need:**
- Dashboard showing active instances
- Capacity planning metrics
- Manual instance management
- Centralized monitoring/alerting

**Don't use if:**
- You just want workflows to work (they already do!)
- You have < 5 instances (basic monitoring is fine)
- You prefer application-level metrics (Prometheus, etc.)

## Implementation Status

⚠️ **This is PLACEHOLDER CODE** - Database functions are stubs.

To use this, you need to:

1. **Create migration for `pgflow_instances` table**:

```elixir
defmodule YourApp.Repo.Migrations.CreatePgflowInstances do
  use Ecto.Migration

  def change do
    create table(:pgflow_instances, primary_key: false) do
      add :instance_id, :text, primary_key: true
      add :hostname, :text
      add :pid, :text
      add :status, :text  # 'online', 'offline', 'paused'
      add :load, :integer, default: 0
      add :last_heartbeat, :utc_datetime
      add :created_at, :utc_datetime
    end

    create index(:pgflow_instances, [:status])
    create index(:pgflow_instances, [:last_heartbeat])
  end
end
```

2. **Implement database functions** in `registry.ex`:

```elixir
defp register_instance(instance_id) do
  {:ok, hostname_charlist} = :inet.gethostname()
  hostname = to_string(hostname_charlist)

  YourApp.Repo.insert!(
    %PgflowInstance{
      instance_id: instance_id,
      hostname: hostname,
      pid: System.pid(),
      status: "online",
      load: 0,
      last_heartbeat: DateTime.utc_now(),
      created_at: DateTime.utc_now()
    },
    on_conflict: {:replace, [:hostname, :pid, :status, :last_heartbeat]},
    conflict_target: :instance_id
  )
end

defp update_instance_heartbeat(instance_id) do
  from(i in PgflowInstance, where: i.instance_id == ^instance_id)
  |> YourApp.Repo.update_all(set: [last_heartbeat: DateTime.utc_now()])
end

# ... implement other functions similarly
```

3. **Create Ecto schema**:

```elixir
defmodule YourApp.PgflowInstance do
  use Ecto.Schema

  @primary_key {:instance_id, :string, autogenerate: false}
  schema "pgflow_instances" do
    field :hostname, :string
    field :pid, :string
    field :status, :string
    field :load, :integer
    field :last_heartbeat, :utc_datetime
    field :created_at, :utc_datetime
  end
end
```

4. **Add to your supervision tree**:

```elixir
# In your application.ex
children = [
  YourApp.Repo,
  # ... other children ...
  Pgflow.Instance.Registry
]
```

5. **Configure heartbeat interval**:

```elixir
# config/config.exs
config :ex_pgflow,
  instance_id: System.get_env("INSTANCE_ID") || "instance_#{Node.self()}",
  instance_heartbeat_interval: 5000,  # 5 seconds
  instance_stale_timeout: 300         # 5 minutes
```

## Alternative Approaches

Instead of implementing this, consider:

### 1. Application-Level Monitoring (Recommended)

Use existing BEAM observability:

```elixir
# In your application
defmodule YourApp.Metrics do
  use GenServer

  def init(_) do
    :telemetry.attach("pgflow-tasks", [:pgflow, :task, :start], &handle_event/4, nil)
    {:ok, %{active_tasks: 0}}
  end

  def handle_event([:pgflow, :task, :start], _measurements, _metadata, state) do
    # Emit to Prometheus, DataDog, etc.
    :telemetry.execute([:your_app, :pgflow, :active_tasks], %{count: state.active_tasks + 1})
  end
end
```

### 2. PostgreSQL-Based Monitoring

Query existing ex_pgflow tables:

```sql
-- Active workflows per instance (if you tag runs with instance_id)
SELECT
  instance_id,
  COUNT(*) as active_runs
FROM workflow_runs
WHERE status = 'running'
GROUP BY instance_id;

-- Queue depth (shows backlog)
SELECT
  queue_name,
  COUNT(*) as pending_tasks
FROM pgmq.q_*
WHERE vt > NOW();
```

### 3. BEAM Native Tools

```elixir
# See what's running
:observer.start()

# Or programmatically
:erlang.statistics(:run_queue)
Process.list() |> length()
```

## Questions?

- **"Do I need this for ex_pgflow to work?"** - No! Workflows coordinate via pgmq automatically.
- **"Will this make my workflows more reliable?"** - No. Reliability comes from pgmq + PostgreSQL.
- **"Should I implement this?"** - Only if you need centralized instance observability. Start simple.

## See Also

- [ARCHITECTURE.md](../../ARCHITECTURE.md) - How multi-instance coordination actually works
- [Pgflow.Executor](../../lib/pgflow/executor.ex) - Worker polling implementation
- [pgmq documentation](https://github.com/tembo-io/pgmq) - Queue-based coordination
