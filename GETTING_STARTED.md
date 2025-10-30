# Getting Started with ExQuantumFlow

ExQuantumFlow is an Elixir implementation of [QuantumFlow](https://github.com/quantum_flow-dev/QuantumFlow), a database-driven DAG execution engine. This guide walks you through installation, basic setup, and running your first workflow.

## Installation

Add `quantum_flow` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:quantum_flow, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Database Setup

ExQuantumFlow requires PostgreSQL 14+ with the `pgmq` extension:

### 1. Create a PostgreSQL Database

```bash
createdb my_app
```

### 2. Add ExQuantumFlow Repository

Configure Ecto in your app to include the QuantumFlow.Repo:

```elixir
# config/config.exs
config :my_app, QuantumFlow.Repo,
  database: "my_app",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432
```

### 3. Install pgmq Extension

```bash
# Install pgmq from PGXN
pgxn install pgmq

# Or via PostgreSQL:
psql my_app -c "CREATE EXTENSION IF NOT EXISTS pgmq"
```

### 4. Run Migrations

```bash
# Generate migrations for ExQuantumFlow tables
mix ecto.gen.migration init_quantum_flow

# Run all migrations
mix ecto.migrate
```

The migration will create:
- `workflow_runs` - Tracks workflow execution instances
- `workflow_step_states` - State for each step in a run
- `workflow_step_tasks` - Individual tasks for map steps
- `workflow_step_dependencies` - Dependency edges in the DAG
- pgmq queue tables - For task coordination

## Your First Workflow

### 1. Define a Workflow

Create a workflow module that implements `QuantumFlow.Executor.Workflow`:

```elixir
defmodule MyApp.Workflows.HelloWorld do
  @behaviour QuantumFlow.Executor.Workflow

  @impl true
  def definition do
    %{
      "version" => "1.0",
      "title" => "Hello World",
      "steps" => [
        %{
          "name" => "greet",
          "type" => "task",
          "command" => "greeting"
        }
      ]
    }
  end

  @impl true
  def execute_command(run_id, "greeting", _input, _context) do
    {:ok, %{"message" => "Hello, World!"}}
  end

  @impl true
  def on_complete(run_id, output, context) do
    IO.inspect(output, label: "Workflow completed")
    :ok
  end

  @impl true
  def on_failure(run_id, error, context) do
    IO.inspect(error, label: "Workflow failed")
    :ok
  end
end
```

### 2. Start the Workflow

```elixir
alias MyApp.Workflows.HelloWorld

# Start a new workflow run
{:ok, run_id} = HelloWorld.start(%{"name" => "Alice"})

# Check status
{:ok, run} = HelloWorld.status(run_id)
IO.inspect(run)
# => %QuantumFlow.WorkflowRun{
#   id: "...",
#   workflow_slug: "MyApp.Workflows.HelloWorld",
#   status: "started",
#   input: %{"name" => "Alice"},
#   remaining_steps: 1
# }
```

### 3. Execute Pending Tasks

The workflow engine coordinates task execution via the pgmq queue. To process tasks:

```elixir
alias QuantumFlow.Executor

# Poll the queue and execute pending tasks
{:ok, executed_count} = Executor.execute_pending_tasks()

# Wait for completion
:timer.sleep(1000)

# Check final status
{:ok, run} = HelloWorld.status(run_id)
IO.inspect(run.status)  # => "completed"
```

## DAG Workflows with Dependencies

ExQuantumFlow supports complex DAG workflows with parallel execution and dependency management:

```elixir
defmodule MyApp.Workflows.DataPipeline do
  @behaviour QuantumFlow.Executor.Workflow

  @impl true
  def definition do
    %{
      "version" => "1.0",
      "title" => "Data Processing Pipeline",
      "steps" => [
        # Extract data from two sources in parallel
        %{
          "name" => "extract_users",
          "type" => "task",
          "command" => "extract",
          "args" => %{"source" => "users"}
        },
        %{
          "name" => "extract_orders",
          "type" => "task",
          "command" => "extract",
          "args" => %{"source" => "orders"}
        },
        # Join them
        %{
          "name" => "join",
          "type" => "task",
          "command" => "merge",
          "dependencies" => ["extract_users", "extract_orders"]
        },
        # Load to warehouse
        %{
          "name" => "load",
          "type" => "task",
          "command" => "load",
          "dependencies" => ["join"]
        }
      ]
    }
  end

  @impl true
  def execute_command(_run_id, "extract", %{"source" => source}, _ctx) do
    # Simulate data extraction
    {:ok, %{"items" => 100, "source" => source}}
  end

  @impl true
  def execute_command(_run_id, "merge", input, _ctx) do
    # Merge results from previous steps
    {:ok, %{"merged_count" => 200}}
  end

  @impl true
  def execute_command(_run_id, "load", input, _ctx) do
    # Load to warehouse
    {:ok, %{"loaded" => true}}
  end

  @impl true
  def on_complete(_run_id, output, _ctx) do
    IO.puts("Pipeline completed!")
  end

  @impl true
  def on_failure(_run_id, error, _ctx) do
    IO.inspect(error, label: "Pipeline failed")
  end
end
```

## Map Steps (Parallel Iteration)

Execute the same task across multiple items:

```elixir
defmodule MyApp.Workflows.ProcessItems do
  @behaviour QuantumFlow.Executor.Workflow

  @impl true
  def definition do
    %{
      "version" => "1.0",
      "title" => "Process Multiple Items",
      "steps" => [
        # Map step: create a task for each item
        %{
          "name" => "process_items",
          "type" => "map",
          "command" => "process",
          "over" => "[1, 2, 3, 4, 5]"
        },
        # Wait for all to complete
        %{
          "name" => "aggregate",
          "type" => "task",
          "command" => "aggregate",
          "dependencies" => ["process_items"]
        }
      ]
    }
  end

  @impl true
  def execute_command(_run_id, "process", %{"item" => item}, _ctx) do
    {:ok, %{"processed" => item, "result" => item * 2}}
  end

  @impl true
  def execute_command(_run_id, "aggregate", input, _ctx) do
    {:ok, %{"aggregated" => true}}
  end

  @impl true
  def on_complete(_run_id, _output, _ctx), do: :ok
  def on_failure(_run_id, _error, _ctx), do: :ok
end
```

## Configuration

ExQuantumFlow respects these environment variables:

```bash
# PostgreSQL connection
DATABASE_URL=postgres://user:pass@localhost:5432/my_app

# PGMQ queue name (default: quantum_flow_queue)
PGFLOW_QUEUE_NAME=my_queue

# Visibility timeout for in-flight tasks (default: 300s = 5 min)
PGFLOW_VT=300

# Max concurrent task executions (default: 10)
PGFLOW_MAX_WORKERS=10
```

## Troubleshooting

### "pgmq extension not found"

Install the extension:

```bash
pgxn install pgmq
createdb my_app
psql my_app -c "CREATE EXTENSION IF NOT EXISTS pgmq"
```

### "Queue not found"

Ensure migrations have run:

```bash
mix ecto.status  # Check pending migrations
mix ecto.migrate  # Run all migrations
```

### Tasks hanging or not executing

Check queue health:

```elixir
alias QuantumFlow.Executor

# See how many tasks are pending
{:ok, count} = Executor.pending_task_count()
IO.inspect(count)

# Manually trigger task processing
Executor.execute_pending_tasks()
```

### Type errors in custom workflows

ExQuantumFlow uses Dialyzer for type checking. Run:

```bash
mix dialyzer
```

## Next Steps

- Read [ARCHITECTURE.md](ARCHITECTURE.md) for internal design details
- Check [DYNAMIC_WORKFLOWS_GUIDE.md](DYNAMIC_WORKFLOWS_GUIDE.md) for advanced patterns
- See [PGFLOW_REFERENCE.md](PGFLOW_REFERENCE.md) for complete API documentation
- Review [SECURITY_AUDIT.md](SECURITY_AUDIT.md) for security considerations

## Contributing

Found a bug? Have a feature request? See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT - See [LICENSE](LICENSE) for details.
