# Getting Started with ExPgflow

Step-by-step guide to set up and use ExPgflow in your Elixir application.

## 1. Installation

### Add to mix.exs

```elixir
def deps do
  [
    {:ex_pgflow, "~> 0.1"},
    {:oban, "~> 2.17"},
    {:ecto_sql, "~> 3.10"}
  ]
end
```

Run:
```bash
mix deps.get
```

## 2. Basic Workflow (No Persistence)

For simple cases, use Pgflow.Executor directly without Oban.

### Define a workflow

```elixir
# lib/my_app/workflows/hello_world.ex
defmodule MyApp.Workflows.HelloWorld do
  def __workflow_steps__ do
    [
      {:greet, &__MODULE__.greet/1},
      {:exclaim, &__MODULE__.exclaim/1}
    ]
  end

  def greet(input) do
    {:ok, Map.put(input, :greeting, "Hello, #{input[:name]}")}
  end

  def exclaim(prev) do
    {:ok, Map.put(prev, :exclamation, prev[:greeting] <> "!")}
  end
end
```

### Execute directly

```elixir
{:ok, result} = Pgflow.Executor.execute(
  MyApp.Workflows.HelloWorld,
  %{name: "World"},
  max_attempts: 3,
  timeout: 30000
)

IO.inspect(result)
# %{
#   name: "World",
#   greeting: "Hello, World",
#   exclamation: "Hello, World!"
# }
```

## 3. Distributed Workflows (With Oban)

For production with multiple instances, use Oban.

### Configure Oban

In `config/config.exs`:

```elixir
config :my_app, Oban,
  engine: Oban.Engines.Basic,
  queues: [
    default: [limit: 10, paused: false],   # 10 concurrent jobs per instance
    priority: [limit: 5, paused: false],
    background: [limit: 3, paused: false]
  ],
  repo: MyApp.Repo,
  plugins: [
    Oban.Plugins.Repeater,     # Handle stale jobs
    Oban.Plugins.Cron          # Schedule periodic tasks
  ]
```

And in `config/runtime.exs`:

```elixir
config :ex_pgflow,
  instance_id: System.get_env("INSTANCE_ID") || "instance_#{Node.self()}",
  instance_heartbeat_interval: 5000,
  instance_stale_timeout: 300
```

### Add Oban to supervision tree

In `lib/my_app/application.ex`:

```elixir
def start(_type, _args) do
  children = [
    MyApp.Repo,
    {Pgflow.Instance.Registry},  # Track instances
    {Oban, Application.fetch_env!(:my_app, Oban)},
    MyApp.Endpoint
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### Create a worker

```elixir
# lib/my_app/workers/hello_world_worker.ex
defmodule MyApp.Workers.HelloWorldWorker do
  use Pgflow.Worker, queue: :default, max_attempts: 3

  def perform(%Oban.Job{args: args}) do
    Pgflow.Executor.execute(MyApp.Workflows.HelloWorld, args)
  end
end
```

### Enqueue jobs

```elixir
# In your application code
{:ok, _job} = MyApp.Workers.HelloWorldWorker.new(%{name: "Alice"})
  |> Oban.insert()

{:ok, _job} = MyApp.Workers.HelloWorldWorker.new(%{name: "Bob"})
  |> Oban.insert()

# Jobs will be executed automatically by Oban
```

## 4. Real-World Example: LLM Request Workflow

### Define workflow

```elixir
# lib/my_app/workflows/llm_request.ex
defmodule MyApp.Workflows.LlmRequest do
  require Logger

  def __workflow_steps__ do
    [
      {:receive_request, &__MODULE__.receive_request/1},
      {:select_model, &__MODULE__.select_model/1},
      {:call_llm, &__MODULE__.call_llm/1},
      {:store_result, &__MODULE__.store_result/1}
    ]
  end

  def receive_request(input) do
    Logger.debug("Received LLM request", request_id: input["request_id"])
    {:ok, input}
  end

  def select_model(prev) do
    task_type = prev["task_type"]

    model = case task_type do
      "simple" -> "gpt-3.5-turbo"
      "medium" -> "gpt-4"
      "complex" -> "gpt-4-turbo"
      _ -> "gpt-4"
    end

    Logger.debug("Selected model", model: model)
    {:ok, Map.put(prev, :model, model)}
  end

  def call_llm(prev) do
    Logger.info("Calling LLM", model: prev[:model])

    # Simulate LLM call
    case simulate_llm_call(prev[:model], prev["prompt"]) do
      {:ok, response} ->
        Logger.info("LLM responded", tokens: response.tokens)
        {:ok, Map.merge(prev, %{
          response: response.text,
          tokens_used: response.tokens,
          cost_cents: response.cost_cents
        })}

      {:error, reason} ->
        Logger.error("LLM call failed", reason: inspect(reason))
        {:error, {:llm_error, reason}}
    end
  end

  def store_result(prev) do
    Logger.info("Storing result",
      request_id: prev["request_id"],
      tokens: prev[:tokens_used]
    )

    # Store in database
    MyApp.Repo.insert!(%MyApp.Schema.LlmResult{
      request_id: prev["request_id"],
      response: prev[:response],
      model: prev[:model],
      tokens_used: prev[:tokens_used],
      cost_cents: prev[:cost_cents]
    })

    {:ok, prev}
  end

  defp simulate_llm_call(model, prompt) do
    # In real code, call actual LLM API
    {:ok, %{
      text: "This is a response from #{model}",
      tokens: String.split(prompt) |> length(),
      cost_cents: 5
    }}
  end
end
```

### Create worker

```elixir
# lib/my_app/workers/llm_request_worker.ex
defmodule MyApp.Workers.LlmRequestWorker do
  use Pgflow.Worker, queue: :default, max_attempts: 3

  def perform(%Oban.Job{args: args}) do
    Pgflow.Executor.execute(MyApp.Workflows.LlmRequest, args,
      timeout: 60000  # 60 second timeout for LLM calls
    )
  end
end
```

### Enqueue requests

```elixir
{:ok, _} = MyApp.Workers.LlmRequestWorker.new(%{
  request_id: "550e8400-e29b-41d4-a716-446655440000",
  task_type: "complex",
  prompt: "Design a scalable cache system"
}) |> Oban.insert()
```

## 5. Multi-Instance Deployment

### Start instances

```bash
# Terminal 1: Instance A
export INSTANCE_ID=instance_a
mix phx.server -p 4000

# Terminal 2: Instance B
export INSTANCE_ID=instance_b
mix phx.server -p 4001

# Terminal 3: Instance C
export INSTANCE_ID=instance_c
mix phx.server -p 4002
```

All three instances connect to the same PostgreSQL and automatically:
- Claim available jobs
- Balance load
- Retry on failure
- Handle crashes

### Monitor distribution

```bash
# Check which instance is executing which job
psql $DATABASE_URL -c "
  SELECT
    id,
    worker,
    args,
    reserved_by,
    state,
    attempt
  FROM oban_jobs
  WHERE state IN ('executing', 'available')
  ORDER BY id;
"

# Check instance health
psql $DATABASE_URL -c "
  SELECT
    instance_id,
    status,
    load,
    NOW() - last_heartbeat as idle_time
  FROM pgflow_instances
  ORDER BY last_heartbeat DESC;
"
```

## 6. Error Handling

### Step-level errors

```elixir
defmodule MyApp.Workflows.Robust do
  def __workflow_steps__ do
    [
      {:fetch, &__MODULE__.fetch/1},
      {:validate, &__MODULE__.validate/1},
      {:process, &__MODULE__.process/1}
    ]
  end

  def fetch(input) do
    case HTTP.get(input.url, recv_timeout: 10000) do
      {:ok, response} ->
        {:ok, Map.put(input, :data, response.body)}

      {:error, reason} ->
        Logger.error("Fetch failed", reason: inspect(reason))
        {:error, {:fetch_error, reason}}
    end
  end

  def validate(prev) do
    if valid?(prev.data) do
      {:ok, prev}
    else
      {:error, "Invalid data format"}
    end
  end

  def process(prev) do
    {:ok, Map.put(prev, :result, process_data(prev.data))}
  end

  defp valid?(data), do: is_map(data) and Map.has_key?(data, :id)
  defp process_data(data), do: data
end
```

### Worker-level error handling

```elixir
defmodule MyApp.Workers.RobustWorker do
  use Pgflow.Worker, queue: :default, max_attempts: 5

  def perform(%Oban.Job{args: args}) do
    case Pgflow.Executor.execute(MyApp.Workflows.Robust, args) do
      {:ok, result} ->
        {:ok, result}

      {:error, {:step_error, {step, reason}}} ->
        Logger.warn("Step #{step} failed", reason: inspect(reason))
        {:error, reason}

      {:error, {:step_timeout, {step, timeout}}} ->
        Logger.error("Step #{step} timed out after #{timeout}ms")
        {:error, :timeout}

      {:error, {:max_attempts_exceeded, reason}} ->
        Logger.error("Workflow exhausted all retries", reason: inspect(reason))
        {:error, :max_retries}
    end
  end
end
```

## 7. Monitoring and Observability

### Logging

ExPgflow logs every step execution. Configure log level in config:

```elixir
# config/config.exs
config :logger,
  level: :debug  # Or :info for production
```

### Metrics (Optional)

Add optional tracking:

```elixir
defmodule MyApp.WorkflowMetrics do
  def track_workflow(workflow_module, args, fun) do
    start_time = System.monotonic_time(:millisecond)

    case fun.() do
      {:ok, result} ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        # Send to metrics system (Prometheus, DataDog, etc.)
        :telemetry.execute(
          [:workflow, :success],
          %{duration_ms: elapsed},
          %{workflow: workflow_module}
        )

        {:ok, result}

      {:error, reason} ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        :telemetry.execute(
          [:workflow, :error],
          %{duration_ms: elapsed},
          %{workflow: workflow_module, reason: reason}
        )

        {:error, reason}
    end
  end
end
```

## 8. Next Steps

1. **Read documentation**
   - [README.md](./README.md) - Overview and features
   - [ARCHITECTURE.md](./ARCHITECTURE.md) - Deep dive

2. **Try examples**
   - Start with simple workflows (2-3 steps)
   - Add error handling
   - Add Oban for persistence

3. **Deploy**
   - Single instance for development
   - Multiple instances for production
   - Monitor with Oban.Web (optional)

4. **Optimize**
   - Monitor step execution times
   - Tune timeouts based on actual performance
   - Consider adding metrics/telemetry

## Common Issues

### Workflow not executing

```bash
# Check Oban is running
iex> Oban.Engine.running?()
true

# Check jobs in queue
iex> Oban.Job |> Repo.all() |> Enum.take(5)

# Check worker is registered
iex> MyApp.Workers.MyWorker.__info__(:module)
:ok
```

### Jobs stuck in queue

```bash
# Look at oldest job
psql $DATABASE_URL -c "
  SELECT * FROM oban_jobs
  WHERE state = 'available'
  ORDER BY inserted_at
  LIMIT 1
"

# Check if Oban is polling (watch logs)
tail -f logs/dev.log | grep Oban
```

### Performance issues

```elixir
# Increase timeout for slow steps
Pgflow.Executor.execute(
  MyApp.Workflows.Slow,
  input,
  timeout: 120000  # 2 minutes
)

# Or reduce max_attempts for quick failure
use Pgflow.Worker, queue: :default, max_attempts: 1
```

## Advanced: Integration with CentralCloud

For multi-instance learning aggregation:

```elixir
defmodule MyApp.Workers.ResultAggregator do
  use Pgflow.Worker, queue: :metrics

  def perform(_job) do
    # Collect results from last 30 seconds
    recent = MyApp.Repo.all(
      from r in MyApp.Schema.Result,
      where: r.created_at > ago(30, "second"),
      select: %{
        model: r.model,
        cost_cents: r.cost_cents,
        success: r.success
      }
    )

    # Aggregate
    avg_cost = Enum.average_by(recent, & &1.cost_cents)
    success_rate = success_count(recent) / length(recent)

    # Send to CentralCloud
    PgmqClient.send_message(
      "centralcloud_updates",
      Jason.encode!(%{
        instance_id: Pgflow.Instance.Registry.instance_id(),
        timestamp: DateTime.utc_now(),
        avg_cost_cents: avg_cost,
        success_rate: success_rate
      })
    )

    {:ok, %{sent: true}}
  end

  defp success_count(results), do: Enum.count(results, & &1.success)
end
```

---

**Need help?** See [README.md](./README.md) or open an issue on GitHub.
