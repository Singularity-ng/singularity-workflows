# ExPgflow Architecture

ExPgflow is an Elixir implementation of pgflow's database-driven DAG execution engine. This document explains the internal architecture, design decisions, and how components interact.

## Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Application Layer                            │
│  (Pgflow.Executor, Pgflow.FlowBuilder, Workflow implementations)     │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
            ┌───────▼───────┐      ┌──────────▼──────────┐
            │   DAG Layer    │      │   Execution Layer   │
            │  (Parsing &    │      │  (Task execution &  │
            │  Validation)   │      │  Status tracking)   │
            └───────┬───────┘      └──────────┬──────────┘
                    │                         │
                    └────────────┬────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │   Storage Layer         │
                    │  (PostgreSQL + pgmq)    │
                    └─────────────────────────┘
```

## Layer 1: DAG (Directed Acyclic Graph)

The DAG layer handles workflow definition parsing, validation, and graph analysis.

### Key Modules

**Pgflow.DAG.WorkflowDefinition** (`lib/pgflow/dag/workflow_definition.ex`)
- Parses JSON workflow definitions
- Validates step structure and dependencies
- Detects cycles to prevent infinite loops
- Extracts dependency edges for execution planning

```elixir
# Example: Parse and validate a workflow
definition = %{
  "version" => "1.0",
  "title" => "My Workflow",
  "steps" => [
    %{"name" => "step1", "type" => "task", "command" => "cmd1"},
    %{"name" => "step2", "type" => "task", "command" => "cmd2",
      "dependencies" => ["step1"]}
  ]
}

{:ok, workflow} = WorkflowDefinition.parse(definition)
```

**Pgflow.DAG.DynamicWorkflowLoader** (`lib/pgflow/dag/dynamic_workflow_loader.ex`)
- Loads workflow definitions from modules at runtime
- Implements dynamic behavior callbacks
- Bridges workflow code and engine execution

### Cycle Detection Algorithm

WorkflowDefinition uses depth-first search (DFS) to detect cycles:

```
1. Build adjacency list from dependencies
2. For each unvisited node:
   - Mark as visiting (in progress)
   - Recursively visit all dependencies
   - If visiting → cycle dependency found
   - Mark as visited (complete)
3. Return cycle path for debugging
```

## Layer 2: Execution

The execution layer orchestrates task processing, state management, and completion logic.

### Key Modules

**Pgflow.Executor** (`lib/pgflow/executor.ex`)
- Main entry point for starting and monitoring workflows
- Delegates to DAG for definition parsing
- Initializes workflow state in database
- Orchestrates polling loop for task execution

```elixir
# Example: Start and execute a workflow
{:ok, run_id} = Executor.start_workflow(MyWorkflow, %{"input" => "data"})
{:ok, executed} = Executor.execute_pending_tasks()
{:ok, run} = Executor.status(run_id)
```

**Pgflow.DAG.RunInitializer** (`lib/pgflow/dag/run_initializer.ex`)
- Creates workflow_runs record
- Initializes step_states for all workflow steps
- Sets up step_dependencies edges
- For map steps, creates one task per item

**Pgflow.DAG.TaskExecutor** (`lib/pgflow/dag/task_executor.ex`)
- Polls pgmq queue for pending tasks
- Executes tasks via workflow callback functions
- Handles retries and error handling
- Updates task state after execution
- Checks if run is complete and calls completion handler

### Execution Flow Diagram

```
Executor.start_workflow()
    │
    ├─> Parse workflow definition
    ├─> Detect cycles in DAG
    │
    ├─> RunInitializer.initialize()
    │   ├─> Create workflow_runs record (status: "started")
    │   ├─> Create step_states (status: "pending")
    │   ├─> Create step_dependencies (edges)
    │   └─> If map steps: create_step_tasks (one per item)
    │
    └─> Enqueue initial steps (no dependencies)

Executor.execute_pending_tasks()
    │
    ├─> Poll pgmq queue (10 message batch)
    │
    ├─> For each task:
    │   ├─> Dequeue from pgmq
    │   ├─> Retrieve step info from step_states
    │   ├─> Call Workflow.execute_command/4
    │   ├─> Update step_states (status: "done", output)
    │   ├─> Check dependencies satisfied
    │   └─> If ready: enqueue dependent steps
    │
    └─> Check if all steps done
        └─> If yes: call Workflow.on_complete()
            or Workflow.on_failure() if any failed
```

## Layer 3: Storage

ExPgflow uses PostgreSQL + pgmq for persistent, reliable task coordination.

### Database Schema

**workflow_runs**
- Tracks workflow execution instances
- One row per workflow start
- Columns:
  - `id` (UUID v7): Primary key
  - `workflow_slug` (string): Workflow module name
  - `status` (string): "started", "completed", "failed"
  - `input` (map): Initial input data
  - `output` (map): Final result (if completed)
  - `remaining_steps` (integer): Counter decremented as steps complete
  - `created_at` (timestamp): When workflow started
  - `started_at`, `completed_at`, `failed_at`: Lifecycle timestamps

**workflow_step_states**
- Tracks state of each step in a run
- One row per step per run
- Columns:
  - `id` (UUID v7): Primary key
  - `workflow_run_id` (UUID): Foreign key to workflow_runs
  - `step_name` (string): Name from workflow definition
  - `status` (string): "pending", "started", "done", "failed"
  - `input` (map): Input to this step
  - `output` (map): Output from execution (if done)
  - `error_message` (text): If failed
  - `attempt` (integer): Retry counter
  - `enqueued_at` (timestamp): When task was queued

**workflow_step_tasks**
- Individual tasks for map steps
- One row per item in a map operation
- Columns:
  - `id` (UUID v7): Primary key
  - `step_state_id` (UUID): Foreign key to workflow_step_states
  - `item_index` (integer): Position in map iteration
  - `item_value` (any): The value to process
  - `status` (string): "pending", "started", "done", "failed"
  - `output` (any): Result from task

**workflow_step_dependencies**
- DAG edges representing step dependencies
- One row per dependency relationship
- Columns:
  - `id` (UUID v7): Primary key
  - `workflow_run_id` (UUID): Foreign key to workflow_runs
  - `from_step_name` (string): Dependency source
  - `to_step_name` (string): Dependency target

**pgmq Tables** (created by extension)
- `pgmq.q_pgflow_queue`: Message queue for task coordination
- Messages contain:
  ```json
  {
    "workflow_run_id": "...",
    "step_name": "...",
    "step_state_id": "...",
    "step_task_id": "...",  // null for regular steps, UUID for map tasks
    "is_map_task": false
  }
  ```

### Visibility Timeout (VT) Pattern

Tasks are coordinated via pgmq's visibility timeout to prevent duplicate execution:

```
1. Enqueue task message with vt=300 (5 minutes)
   - Message invisible for 300 seconds
2. Worker polls pgmq.read()
   - Returns only visible messages
3. Worker executes task
   - If 300s elapses without ack: message reappears (timeout → retry)
   - Task executor calls pgmq.delete() after success (acknowledge receipt)
4. Worker deletes message on success
   - Message no longer reappears
```

This ensures:
- **Exactly-once execution** (in normal conditions)
- **Automatic retry** if worker crashes
- **No message loss** if database transaction rolls back

## Key Design Decisions

### 1. Database-First Architecture

**Why**: Enables multi-instance scaling and reliable coordination
- ✅ Works across multiple processes/machines
- ✅ PostgreSQL provides ACID guarantees
- ✅ pgmq gives distributed task queue semantics
- ❌ Slightly slower than in-memory queues
- ❌ Requires database connection for every task

### 2. Remaining Steps Counter

**Why**: Fast completion detection without counting rows
- Each step completion decrements counter
- When counter reaches 0, workflow is complete
- **Performance**: O(1) completion check instead of O(n) row count

### 3. Visibility Timeout for Task Coordination

**Why**: Reliable "at-least-once" delivery with automatic retry
- If task executor crashes: message reappears after VT
- No coordinator needed (simpler than Saga pattern)
- PostgreSQL handles the timeout (no separate timeout service)

### 4. Step States vs Step Tasks

**Why**: Different semantics for regular vs map steps
- **Regular steps**: One step_state per step per run
- **Map steps**: One step_state + one step_task per item
- Allows parallel execution of map items with shared completion logic

### 5. Dependency Edges vs Ordering

**Why**: Explicit DAG edges enable parallel execution
- Instead of strict step ordering, dependencies are edges
- Step A can run as soon as all dependencies complete
- Multiple independent steps run in parallel automatically

## Workflow Behavior Callbacks

Workflows implement `Pgflow.Executor.Workflow` behavior with callbacks:

```elixir
@callback definition :: map()
  # Returns workflow definition (steps, dependencies)

@callback execute_command(
  run_id :: String.t(),
  command :: String.t(),
  input :: map(),
  context :: map()
) :: {:ok, output :: any()} | {:error, reason :: any()}
  # Executes a step (called by task executor)

@callback on_complete(
  run_id :: String.t(),
  output :: map(),
  context :: map()
) :: :ok | {:error, reason :: any()}
  # Called when all steps done successfully

@callback on_failure(
  run_id :: String.t(),
  error :: map(),
  context :: map()
) :: :ok | {:error, reason :: any()}
  # Called when any step fails
```

## Comparison with pgflow (Python)

ExPgflow matches pgflow's core architecture with Elixir idioms:

| Feature | pgflow | ExPgflow |
|---------|--------|----------|
| DAG Parsing | JSON parsing | JSON + Elixir pattern matching |
| Cycle Detection | DFS | DFS (same algorithm) |
| Task Queue | pgmq (Python driver) | pgmq (Postgrex driver) |
| Parallel Execution | DAG dependencies | DAG dependencies |
| Map Steps | Per-item tasks | per-item step_tasks |
| Status Tracking | Database tables | PostgreSQL schema |
| Completion Check | Row counting | Remaining counter |
| Visibility Timeout | pgmq VT | pgmq VT |
| Error Handling | try/except blocks | {:ok, result} | {:error, reason} |

**Key differences**:
1. **Language**: Python (pgflow) vs Elixir (ExPgflow)
2. **Concurrency**: asyncio (pgflow) vs BEAM (ExPgflow)
3. **Type Safety**: Type hints (pgflow) vs Dialyzer (ExPgflow)

Both achieve the same execution guarantees through identical database patterns.

## Performance Characteristics

### Latency
- **Task start latency**: 10-50ms (database roundtrip)
- **Completion latency**: Polling interval (default: 100ms)
- **Overall latency** for simple workflow: 50ms-2s

### Throughput
- **Tasks/second**: 100-1000 (depending on CPU, DB, network)
- **Concurrent runs**: Unlimited (database scales)
- **Bottleneck**: PostgreSQL connection pool, pgmq queue throughput

### Scalability
- **Horizontal**: Add more ExPgflow instances polling same pgmq queue
- **Vertical**: Increase PostgreSQL resources (CPU, RAM, I/O)
- **Maximum**: Limited by PostgreSQL capacity (10K+ tasks/second possible)

## Future Extensions

Possible enhancements without breaking the core architecture:

1. **Conditional Steps**: If/else logic in workflow definitions
2. **Loop Steps**: Repeat/while operations
3. **Timeout Handling**: Per-step timeout with automatic cancellation
4. **Metrics**: Built-in latency, throughput, error rate tracking
5. **Distributed Tracing**: OpenTelemetry integration for debugging
6. **Priority Queue**: Prioritize high-importance tasks
7. **Graceful Degradation**: Continue despite individual step failures

## Testing Strategy

ExPgflow uses:
- **Unit tests**: SQL logic, cycle detection algorithm
- **Integration tests**: Full workflow execution end-to-end
- **Mock workflows**: Deterministic testing without external dependencies
- **ExUnit sandbox**: Transaction-level test isolation

See `test/` directory for examples.

## Deployment Considerations

1. **Database**: Must support pgmq extension (PostgreSQL 14+)
2. **Connection Pool**: Configure via Ecto (default: 10 connections)
3. **Polling Interval**: 100-500ms (trade-off: latency vs CPU)
4. **Concurrency**: Number of BEAM schedulers (defaults to CPU count)
5. **Monitoring**: Check pgmq queue depth, step failure rate
6. **Backup**: PostgreSQL WAL archiving for durability

See [GETTING_STARTED.md](GETTING_STARTED.md) for deployment steps.

## Debugging

### Check Workflow Status
```elixir
{:ok, run} = Pgflow.Executor.status(run_id)
IO.inspect(run, pretty: true)
```

### View Pending Tasks
```elixir
alias Pgflow.StepState
Pgflow.Repo.all(from s in StepState, where: s.workflow_run_id == ^run_id)
```

### View pgmq Queue Depth
```sql
SELECT COUNT(*) FROM pgmq.q_pgflow_queue;
```

### Enable Debug Logging
```elixir
# config/config.exs
config :logger, level: :debug
```

## License

MIT - See [LICENSE](LICENSE) for details.
