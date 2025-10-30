# Dynamic Workflows Guide - AI/LLM Integration

**Date:** 2025-10-25
**Status:** ✅ Production Ready

---

## Overview

quantum_flow now supports **dynamic workflow creation** - perfect for AI/LLM agents that generate workflows at runtime!

### Two Workflow Approaches

| Approach | Use Case | Example |
|----------|----------|---------|
| **Static (Code)** | Hand-written workflows | Elixir modules with `__workflow_steps__/0` |
| **Dynamic (Database)** | AI-generated workflows | FlowBuilder API + step functions map |

**Both use the same execution engine** - identical performance and features!

---

## Quick Start: AI-Generated Workflow

```elixir
# 1. AI generates workflow structure
{:ok, _} = QuantumFlow.FlowBuilder.create_flow("ai_data_pipeline", repo,
  max_attempts: 5,
  timeout: 60
)

# 2. AI adds steps with dependencies
{:ok, _} = QuantumFlow.FlowBuilder.add_step("ai_data_pipeline", "fetch_data", [], repo)

{:ok, _} = QuantumFlow.FlowBuilder.add_step("ai_data_pipeline", "process_batch", ["fetch_data"], repo,
  step_type: "map",
  initial_tasks: 100  # Process 100 items in parallel
)

{:ok, _} = QuantumFlow.FlowBuilder.add_step("ai_data_pipeline", "save_results", ["process_batch"], repo)

# 3. Provide step implementations
step_functions = %{
  fetch_data: fn _input ->
    {:ok, Enum.to_list(1..100)}  # Returns array for map step
  end,

  process_batch: fn input ->
    # Each of 100 tasks processes one item
    item = Map.get(input, "item")
    {:ok, %{processed: item * 2}}
  end,

  save_results: fn input ->
    # Runs after all 100 tasks complete
    {:ok, %{saved: true}}
  end
}

# 4. Execute!
{:ok, result} = QuantumFlow.Executor.execute_dynamic(
  "ai_data_pipeline",
  %{"initial" => "data"},
  step_functions,
  repo
)
```

---

## API Reference

### FlowBuilder.create_flow/3

Creates a workflow definition.

```elixir
{:ok, workflow} = QuantumFlow.FlowBuilder.create_flow(
  "my_workflow",  # Unique identifier
  repo,
  max_attempts: 3,  # Default retry count
  timeout: 30       # Default timeout in seconds
)
```

**Returns:**
- `{:ok, workflow_map}` - Success
- `{:error, :invalid_workflow_slug}` - Invalid name (must be `^[a-zA-Z_][a-zA-Z0-9_]*$`)

---

### FlowBuilder.add_step/5

Adds a step to a workflow.

```elixir
{:ok, step} = QuantumFlow.FlowBuilder.add_step(
  "my_workflow",     # Workflow slug
  "step_name",       # Step identifier
  ["dep1", "dep2"],  # Dependencies (can be empty [])
  repo,
  step_type: "single",      # "single" or "map"
  initial_tasks: nil,       # For map steps: number of tasks
  max_attempts: 5,          # Override workflow default
  timeout: 120              # Override workflow default (seconds)
)
```

**Step Types:**
- `"single"` - One task (default)
- `"map"` - Multiple tasks (requires `initial_tasks` or determines from dependency output)

**Map Step Rules:**
- Can have 0 or 1 dependency (NOT multiple)
- If 0 deps: Maps over workflow input array
- If 1 dep: Maps over dependency's output array

---

### Executor.execute_dynamic/5

Executes a dynamic workflow.

```elixir
{:ok, result} = QuantumFlow.Executor.execute_dynamic(
  "workflow_slug",       # String workflow identifier
  %{"input" => "data"},  # Initial input
  step_functions,        # Map of step_slug atoms => functions
  repo,
  timeout: 300_000,      # Optional: execution timeout (ms)
  poll_interval: 200     # Optional: polling interval (ms)
)
```

**Step Functions Map:**
```elixir
step_functions = %{
  step_slug: fn input -> {:ok, output} end,
  another_step: fn input -> {:ok, output} end
}
```

**Returns:**
- `{:ok, result}` - Workflow completed
- `{:error, reason}` - Workflow failed
- `{:error, {:workflow_not_found, slug}}` - Workflow doesn't exist

---

## AI Integration Patterns

### Pattern 1: Claude Generates Workflow from Natural Language

```elixir
defmodule AIWorkflowGenerator do
  def generate_from_prompt(prompt, repo) do
    # 1. Claude analyzes prompt and generates workflow structure
    workflow_spec = ask_claude("""
      Generate a workflow for: #{prompt}

      Return JSON with:
      {
        "workflow_slug": "...",
        "steps": [
          {"slug": "...", "depends_on": [...], "type": "single|map"}
        ]
      }
    """)

    # 2. Create workflow
    {:ok, _} = QuantumFlow.FlowBuilder.create_flow(workflow_spec.workflow_slug, repo)

    # 3. Add steps
    for step <- workflow_spec.steps do
      QuantumFlow.FlowBuilder.add_step(
        workflow_spec.workflow_slug,
        step.slug,
        step.depends_on,
        repo,
        step_type: step.type
      )
    end

    # 4. Claude generates step implementations
    step_functions = generate_step_functions(workflow_spec, prompt)

    # 5. Execute
    QuantumFlow.Executor.execute_dynamic(
      workflow_spec.workflow_slug,
      %{"prompt" => prompt},
      step_functions,
      repo
    )
  end
end
```

---

### Pattern 2: Multi-Agent Workflow Coordination

```elixir
defmodule MultiAgentWorkflow do
  def create_agent_workflow(agents, repo) do
    {:ok, _} = QuantumFlow.FlowBuilder.create_flow("multi_agent_task", repo)

    # Create steps for each agent
    prev_step = nil
    for agent <- agents do
      deps = if prev_step, do: [prev_step], else: []

      {:ok, _} = QuantumFlow.FlowBuilder.add_step(
        "multi_agent_task",
        agent.slug,
        deps,
        repo
      )

      prev_step = agent.slug
    end

    # Map agent functions
    step_functions =
      agents
      |> Enum.map(fn agent -> {String.to_atom(agent.slug), agent.function} end)
      |> Map.new()

    QuantumFlow.Executor.execute_dynamic("multi_agent_task", %{}, step_functions, repo)
  end
end
```

---

### Pattern 3: A/B Testing Workflows

```elixir
defmodule ABTestWorkflows do
  def create_variant(variant_name, config, repo) do
    workflow_slug = "ab_test_#{variant_name}"

    {:ok, _} = QuantumFlow.FlowBuilder.create_flow(workflow_slug, repo)

    # Build workflow based on variant config
    for {step_name, step_config} <- config.steps do
      QuantumFlow.FlowBuilder.add_step(
        workflow_slug,
        step_name,
        step_config.depends_on,
        repo
      )
    end

    workflow_slug
  end

  def run_ab_test(input, repo) do
    # Create variants
    variant_a = create_variant("a", @config_a, repo)
    variant_b = create_variant("b", @config_b, repo)

    # Run both in parallel
    tasks = [
      Task.async(fn ->
        QuantumFlow.Executor.execute_dynamic(variant_a, input, @step_fns, repo)
      end),
      Task.async(fn ->
        QuantumFlow.Executor.execute_dynamic(variant_b, input, @step_fns, repo)
      end)
    ]

    Task.await_many(tasks)
  end
end
```

---

## Database Schema

Dynamic workflows are stored in these tables:

```sql
-- Workflow definitions
workflows (
  workflow_slug TEXT PRIMARY KEY,
  max_attempts INTEGER DEFAULT 3,
  timeout INTEGER DEFAULT 30,
  created_at TIMESTAMPTZ
)

-- Steps within workflows
workflow_steps (
  workflow_slug TEXT,
  step_slug TEXT,
  step_type TEXT DEFAULT 'single',  -- 'single' or 'map'
  step_index INTEGER,
  deps_count INTEGER,
  initial_tasks INTEGER,
  max_attempts INTEGER,
  timeout INTEGER,
  PRIMARY KEY (workflow_slug, step_slug)
)

-- Step dependencies
workflow_step_dependencies_def (
  workflow_slug TEXT,
  dep_slug TEXT,        -- dependency step
  step_slug TEXT,       -- dependent step
  PRIMARY KEY (workflow_slug, dep_slug, step_slug)
)
```

---

## FlowBuilder Helper Functions

### List All Workflows

```elixir
{:ok, workflows} = QuantumFlow.FlowBuilder.list_flows(repo)
Enum.each(workflows, fn w ->
  IO.puts("#{w["workflow_slug"]} - #{w["max_attempts"]} attempts")
end)
```

### Get Workflow with Steps

```elixir
{:ok, workflow} = QuantumFlow.FlowBuilder.get_flow("my_workflow", repo)
# => %{
#   "workflow_slug" => "my_workflow",
#   "steps" => [
#     %{"step_slug" => "step1", "depends_on" => []},
#     %{"step_slug" => "step2", "depends_on" => ["step1"]}
#   ]
# }
```

### Delete Workflow

```elixir
:ok = QuantumFlow.FlowBuilder.delete_flow("old_workflow", repo)
```

---

## Advantages of Dynamic Workflows

### ✅ For AI/LLM

- **Runtime generation** - Claude/GPT generates workflows on-the-fly
- **Natural language input** - "Process these files then email results"
- **Adaptive workflows** - Change structure based on data
- **Multi-tenant** - Different workflow per user/tenant

### ✅ For Developers

- **Same execution engine** - Identical performance as code workflows
- **Admin UIs** - Build visual workflow editors
- **A/B testing** - Test different workflow structures
- **Debugging** - Inspect workflow in database

---

## Limitations

### ❌ Compared to Static Workflows

- **Less type-safe** - No compile-time checking
- **Runtime overhead** - DB lookup to load definition
- **Migration complexity** - Schema changes need careful handling

### ⚠️ Best Practices

1. **Validate step functions exist** - Check all step_slugs have implementations
2. **Use transactions** - Wrap create_flow + add_step in DB transaction
3. **Cache definitions** - Load once, execute many times
4. **Sanitize slugs** - Validate names from AI (use is_valid_slug)

---

## Performance

Dynamic workflows have **identical execution performance** to static workflows:

- ✅ Same pgmq coordination
- ✅ Same PostgreSQL functions
- ✅ Same parallel execution
- ✅ Same error handling

**Only difference:** 1-2ms DB query overhead to load definition initially.

---

## Migration Path

### From Static to Dynamic

```elixir
# Before (static)
defmodule MyWorkflow do
  def __workflow_steps__ do
    [{:step1, &__MODULE__.step1/1, depends_on: []}]
  end
  def step1(input), do: {:ok, input}
end

QuantumFlow.Executor.execute(MyWorkflow, input, repo)

# After (dynamic)
{:ok, _} = QuantumFlow.FlowBuilder.create_flow("my_workflow", repo)
{:ok, _} = QuantumFlow.FlowBuilder.add_step("my_workflow", "step1", [], repo)

step_functions = %{
  step1: fn input -> {:ok, input} end
}

QuantumFlow.Executor.execute_dynamic("my_workflow", input, step_functions, repo)
```

**Both execute identically!**

---

## Example: Claude-Generated ETL Pipeline

```elixir
# User prompt
prompt = """
Extract data from CSV files, validate each row,
transform the valid rows, and load into PostgreSQL.
Process rows in parallel batches of 50.
"""

# Claude generates workflow
{:ok, _} = QuantumFlow.FlowBuilder.create_flow("claude_etl", repo)
{:ok, _} = QuantumFlow.FlowBuilder.add_step("claude_etl", "extract_csv", [], repo)
{:ok, _} = QuantumFlow.FlowBuilder.add_step("claude_etl", "validate_rows", ["extract_csv"], repo,
  step_type: "map",
  initial_tasks: 50
)
{:ok, _} = QuantumFlow.FlowBuilder.add_step("claude_etl", "load_db", ["validate_rows"], repo)

# Implementations
step_functions = %{
  extract_csv: fn _input ->
    rows = File.stream!("data.csv") |> CSV.decode() |> Enum.to_list()
    {:ok, rows}
  end,

  validate_rows: fn input ->
    row = Map.get(input, "item")
    if valid?(row), do: {:ok, transform(row)}, else: {:error, :invalid}
  end,

  load_db: fn input ->
    Repo.insert_all(DataTable, input["validate_rows"])
    {:ok, %{loaded: true}}
  end
}

# Execute
{:ok, result} = QuantumFlow.Executor.execute_dynamic("claude_etl", %{}, step_functions, repo)
```

---

## Summary

Dynamic workflows enable **AI/LLM agents to create workflows at runtime** while using the same battle-tested execution engine as code-based workflows.

**Perfect for:**
- 🤖 AI workflow generation from natural language
- 🧪 A/B testing different workflow structures
- 🏗️ Visual workflow builders
- 🎯 User-specific workflow customization
- 🔄 Runtime workflow adaptation

**Same performance, same features, more flexibility!** ✅
