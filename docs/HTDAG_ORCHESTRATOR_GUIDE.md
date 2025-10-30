# HTDAG Orchestrator Guide

Comprehensive guide to QuantumFlow's Hierarchical Task Directed Acyclic Graph (HTDAG) orchestration system for goal-driven workflow execution.

## Table of Contents

- [Overview](#overview)
- [Core Concepts](#core-concepts)
- [Quick Start](#quick-start)
- [Goal Decomposition](#goal-decomposition)
- [Workflow Composition](#workflow-composition)
- [Workflow Optimization](#workflow-optimization)
- [Event Notifications](#event-notifications)
- [Real-World Examples](#real-world-examples)
- [Configuration](#configuration)
- [Best Practices](#best-practices)

---

## Overview

The HTDAG Orchestrator transforms high-level goals into executable workflows:

```
Goal (String)
    ↓
Decompose (Task Graph)
    ↓
Create Workflow (HTDAG → DAG)
    ↓
Execute (Parallel Task Execution)
    ↓
Optimize (Learn from Execution)
```

### Key Features

- **Goal-Driven Execution**: Describe what you want, not how to do it
- **Automatic Decomposition**: Break goals into hierarchical tasks
- **Smart Optimization**: Learn from execution patterns
- **Real-Time Monitoring**: Event-driven notifications
- **Flexible Composition**: Single workflows or multi-workflow compositions
- **Adaptive Strategies**: Different optimization levels for different workloads

### Components

| Component | Purpose | When to Use |
|-----------|---------|------------|
| **QuantumFlow.Orchestrator** | Goal decomposition engine | Core functionality |
| **QuantumFlow.WorkflowComposer** | High-level composition API | Most user workflows |
| **QuantumFlow.OrchestratorOptimizer** | Optimization engine | Production workflows |
| **QuantumFlow.OrchestratorNotifications** | Event broadcasting | Monitoring & observability |

---

## Core Concepts

### Goal

A high-level description of what needs to be accomplished:

```elixir
# Simple goal
"Build user authentication system"

# Complex goal with context
"Create a microservices payment processing system with PCI compliance"
```

### Task Graph

A hierarchical representation of tasks and their dependencies:

```elixir
%{
  tasks: [
    %{id: "task1", description: "Analyze requirements", depends_on: []},
    %{id: "task2", description: "Design system", depends_on: ["task1"]},
    %{id: "task3", description: "Implement core", depends_on: ["task2"]},
    %{id: "task4", description: "Add security", depends_on: ["task3"]},
    %{id: "task5", description: "Deploy", depends_on: ["task3", "task4"]}
  ]
}
```

### Decomposer

A function that converts goals into task graphs:

```elixir
defmodule MyApp.GoalDecomposer do
  def decompose(goal) do
    # Could call an LLM, use rules, or combine both
    tasks = [
      %{id: "analyze", description: "Analyze #{goal}", depends_on: []},
      %{id: "plan", description: "Plan solution", depends_on: ["analyze"]},
      %{id: "execute", description: "Execute plan", depends_on: ["plan"]}
    ]
    {:ok, tasks}
  end
end
```

### Step Functions

Map task IDs to executable functions:

```elixir
step_functions = %{
  "analyze" => &MyApp.Tasks.analyze/1,
  "plan" => &MyApp.Tasks.plan/1,
  "execute" => &MyApp.Tasks.execute/1
}
```

---

## Quick Start

### 1. Define a Decomposer

```elixir
defmodule MyApp.SimpleDecomposer do
  def decompose(goal) do
    # Break goal into steps
    tasks = [
      %{id: "step1", description: "First step", depends_on: []},
      %{id: "step2", description: "Second step", depends_on: ["step1"]},
      %{id: "step3", description: "Final step", depends_on: ["step2"]}
    ]
    {:ok, tasks}
  end
end
```

### 2. Define Step Functions

```elixir
step_functions = %{
  "step1" => fn input ->
    {:ok, %{result: "Step 1 completed"}}
  end,
  "step2" => fn input ->
    {:ok, %{result: "Step 2 completed"}}
  end,
  "step3" => fn input ->
    {:ok, %{result: "Step 3 completed"}}
  end
}
```

### 3. Execute the Goal

```elixir
{:ok, result} = QuantumFlow.WorkflowComposer.compose_from_goal(
  "Complete the workflow",
  &MyApp.SimpleDecomposer.decompose/1,
  step_functions,
  MyApp.Repo
)
```

---

## Goal Decomposition

### Using QuantumFlow.Orchestrator

The `Orchestrator` module provides low-level decomposition control:

#### decompose_goal/3

```elixir
{:ok, task_graph} = QuantumFlow.Orchestrator.decompose_goal(
  "Build authentication system",
  &MyApp.GoalDecomposer.decompose/1,
  MyApp.Repo
)
```

Returns:
```elixir
{:ok, %{
  tasks: [...],
  id: "htdag_12345",
  decomposed_at: ~U[2025-10-30 21:00:00Z]
}}
```

#### decompose_goal/4 (with options)

```elixir
{:ok, task_graph} = QuantumFlow.Orchestrator.decompose_goal(
  "Build authentication system",
  &MyApp.GoalDecomposer.decompose/1,
  MyApp.Repo,
  learning_enabled: true,
  pattern_confidence_threshold: 0.8
)
```

### Decomposer Patterns

#### Pattern 1: Rule-Based Decomposition

```elixir
defmodule MyApp.RuleBasedDecomposer do
  def decompose(goal) do
    cond do
      String.contains?(goal, "auth") ->
        {:ok, auth_tasks()}
      String.contains?(goal, "payment") ->
        {:ok, payment_tasks()}
      true ->
        {:ok, generic_tasks()}
    end
  end

  defp auth_tasks do
    [
      %{id: "design_auth", description: "Design auth flow", depends_on: []},
      %{id: "implement_auth", description: "Implement auth", depends_on: ["design_auth"]},
      %{id: "test_auth", description: "Test auth", depends_on: ["implement_auth"]}
    ]
  end
end
```

#### Pattern 2: LLM-Based Decomposition

```elixir
defmodule MyApp.LLMDecomposer do
  def decompose(goal) do
    prompt = """
    Break down this goal into steps:
    #{goal}

    Return as JSON:
    [{"id": "step1", "description": "...", "depends_on": []}, ...]
    """

    {:ok, response} = ExLLM.chat(:claude, [
      %{role: "user", content: prompt}
    ])

    tasks = Jason.decode!(response.content)
    {:ok, tasks}
  end
end
```

#### Pattern 3: Hybrid Decomposition

```elixir
defmodule MyApp.HybridDecomposer do
  def decompose(goal) do
    # Start with rules for known patterns
    if String.contains?(goal, "microservices") do
      handle_microservices(goal)
    else
      # Fall back to LLM for unknown goals
      handle_with_llm(goal)
    end
  end
end
```

---

## Workflow Composition

The `WorkflowComposer` provides high-level APIs for creating and executing workflows.

### compose_from_goal/5

One-step goal to execution:

```elixir
{:ok, result} = QuantumFlow.WorkflowComposer.compose_from_goal(
  "Build microservices payment system",
  &MyApp.GoalDecomposer.decompose/1,
  step_functions,
  MyApp.Repo,
  optimization_level: :advanced,
  monitoring: true,
  real_time_notifications: true
)
```

Options:
- `:optimization_level` - `:basic`, `:advanced`, `:aggressive` (default: `:basic`)
- `:monitoring` - Enable execution monitoring (default: true)
- `:real_time_notifications` - Enable NOTIFY events (default: false)
- `:preserve_structure` - Keep task dependencies unchanged (default: true)
- `:max_parallel` - Maximum parallel tasks (default: 10)
- `:timeout` - Execution timeout in ms (default: 300,000)

### compose_from_task_graph/4

Execute a pre-existing task graph:

```elixir
{:ok, task_graph} = QuantumFlow.Orchestrator.decompose_goal(
  goal,
  &decomposer/1,
  repo
)

{:ok, result} = QuantumFlow.WorkflowComposer.compose_from_task_graph(
  task_graph,
  step_functions,
  MyApp.Repo,
  optimization_level: :advanced
)
```

### compose_multiple_workflows/5

Compose and execute multiple related workflows:

```elixir
goals = [
  "Build authentication service",
  "Build payment service",
  "Build notification service"
]

{:ok, results} = QuantumFlow.WorkflowComposer.compose_multiple_workflows(
  goals,
  &MyApp.GoalDecomposer.decompose/1,
  %{
    "auth" => &auth_step_functions/0,
    "payment" => &payment_step_functions/0,
    "notification" => &notification_step_functions/0
  },
  MyApp.Repo,
  parallel: true
)
```

---

## Workflow Optimization

The `OrchestratorOptimizer` learns from execution patterns to improve future workflows.

### Optimization Levels

#### :basic - Safe & Conservative

```elixir
{:ok, optimized} = QuantumFlow.OrchestratorOptimizer.optimize_workflow(
  workflow,
  MyApp.Repo,
  optimization_level: :basic
)
```

Applies:
- Simple timeout adjustments based on historical data
- Basic retry logic for unreliable tasks
- Minimal reordering to improve parallelization
- Safe for production with stable workloads

#### :advanced - Intelligent & Adaptive

```elixir
{:ok, optimized} = QuantumFlow.OrchestratorOptimizer.optimize_workflow(
  workflow,
  MyApp.Repo,
  optimization_level: :advanced
)
```

Applies:
- Dynamic parallelization based on performance metrics
- Intelligent retry strategies with exponential backoff
- Resource allocation optimization
- Task merging for compatible dependencies
- Requires historical execution data

#### :aggressive - Maximum Optimization

```elixir
{:ok, optimized} = QuantumFlow.OrchestratorOptimizer.optimize_workflow(
  workflow,
  MyApp.Repo,
  optimization_level: :aggressive,
  preserve_structure: false
)
```

Applies:
- Complete workflow restructuring
- Advanced parallelization strategies
- Predictive resource allocation
- ML-based optimization models
- Requires extensive historical data (100+ executions)

### Optimization Options

```elixir
QuantumFlow.OrchestratorOptimizer.optimize_workflow(
  workflow,
  MyApp.Repo,
  optimization_level: :advanced,
  preserve_structure: true,  # Keep task dependencies (default: true)
  max_parallel: 10,          # Cap parallel execution
  timeout_threshold: 30000,  # Don't adjust if task runs < 30s
  learning_enabled: true,    # Store patterns for future use
  pattern_confidence_threshold: 0.85  # Only apply high-confidence patterns
)
```

### Getting Optimization Recommendations

```elixir
{:ok, recommendations} = QuantumFlow.OrchestratorOptimizer.get_recommendations(
  workflow,
  MyApp.Repo
)

# Returns:
%{
  parallelizable_pairs: [...],
  timeout_adjustments: %{task1: 5000, task2: 10000},
  failed_pattern_warnings: [...],
  resource_allocation: %{...}
}
```

---

## Event Notifications

The `OrchestratorNotifications` module broadcasts real-time events during execution.

### Event Types

```elixir
# Composition events
:decomposition_started
:decomposition_completed
:decomposition_failed

# Execution events
:execution_started
:execution_completed
:execution_failed

# Task events
:task_started
:task_completed
:task_failed
:task_retried

# Optimization events
:optimization_started
:optimization_completed
:optimization_recommended
```

### Subscribing to Events

```elixir
{:ok, listener} = QuantumFlow.OrchestratorNotifications.listen(
  "orchestrator_events",
  MyApp.Repo
)

# Handle notifications
receive do
  {:notification, ^listener, _channel, message_id} ->
    Logger.info("Event received: #{message_id}")
    # Process the event...
after
  30000 -> Logger.warn("No events received")
end

# Stop listening
:ok = QuantumFlow.OrchestratorNotifications.unlisten(listener, MyApp.Repo)
```

### Getting Recent Events

```elixir
{:ok, events} = QuantumFlow.OrchestratorNotifications.get_recent_events(
  "orchestrator_events",
  MyApp.Repo,
  limit: 100
)

# Returns list of recent event messages
```

### Sending Custom Events

```elixir
{:ok, message_id} = QuantumFlow.OrchestratorNotifications.send_with_notify(
  "orchestrator_events",
  %{
    type: "custom_event",
    workflow_id: workflow.id,
    payload: %{key: "value"}
  },
  MyApp.Repo
)
```

---

## Real-World Examples

### Example 1: Microservices Architecture Design

Goal: "Design a scalable microservices architecture for an e-commerce platform"

```elixir
defmodule MyApp.MicroservicesDecomposer do
  def decompose("Design a scalable microservices architecture for " <> _) do
    {:ok, [
      %{id: "analyze_requirements", description: "Analyze business requirements", depends_on: []},
      %{id: "identify_domains", description: "Identify bounded domains", depends_on: ["analyze_requirements"]},
      %{id: "design_services", description: "Design microservices", depends_on: ["identify_domains"]},
      %{id: "plan_deployment", description: "Plan deployment strategy", depends_on: ["design_services"]},
      %{id: "create_documentation", description: "Create documentation", depends_on: ["plan_deployment"]}
    ]}
  end
end

step_functions = %{
  "analyze_requirements" => &analyze_ecommerce_requirements/1,
  "identify_domains" => &identify_bounded_domains/1,
  "design_services" => &design_microservices/1,
  "plan_deployment" => &plan_k8s_deployment/1,
  "create_documentation" => &create_architecture_docs/1
}

{:ok, result} = QuantumFlow.WorkflowComposer.compose_from_goal(
  "Design a scalable microservices architecture for an e-commerce platform",
  &MyApp.MicroservicesDecomposer.decompose/1,
  step_functions,
  MyApp.Repo,
  optimization_level: :advanced,
  monitoring: true
)
```

### Example 2: Data Pipeline Optimization

Goal: "Optimize our data processing pipeline for 10x throughput"

```elixir
defmodule MyApp.DataPipelineDecomposer do
  def decompose("Optimize our data processing pipeline" <> _) do
    {:ok, [
      %{id: "profile_pipeline", description: "Profile current pipeline", depends_on: []},
      %{id: "identify_bottlenecks", description: "Identify bottlenecks", depends_on: ["profile_pipeline"]},
      %{id: "design_improvements", description: "Design improvements", depends_on: ["identify_bottlenecks"]},
      %{id: "implement_changes", description: "Implement optimizations", depends_on: ["design_improvements"]},
      %{id: "benchmark", description: "Benchmark results", depends_on: ["implement_changes"]},
      %{id: "document_changes", description: "Document changes", depends_on: ["benchmark"]}
    ]}
  end
end

{:ok, result} = QuantumFlow.WorkflowComposer.compose_from_goal(
  "Optimize our data processing pipeline for 10x throughput",
  &MyApp.DataPipelineDecomposer.decompose/1,
  step_functions,
  MyApp.Repo,
  optimization_level: :aggressive  # Aggressive since we have historical data
)
```

### Example 3: Multi-Workflow Composition

Goal: Build three microservices simultaneously

```elixir
goals = [
  "Build user service API",
  "Build product service API",
  "Build order service API"
]

step_functions = %{
  "user_service" => %{
    "design_schema" => &design_user_schema/1,
    "implement_endpoints" => &implement_user_endpoints/1,
    "add_tests" => &test_user_service/1
  },
  "product_service" => %{
    "design_schema" => &design_product_schema/1,
    "implement_endpoints" => &implement_product_endpoints/1,
    "add_tests" => &test_product_service/1
  },
  "order_service" => %{
    "design_schema" => &design_order_schema/1,
    "implement_endpoints" => &implement_order_endpoints/1,
    "add_tests" => &test_order_service/1
  }
}

{:ok, results} = QuantumFlow.WorkflowComposer.compose_multiple_workflows(
  goals,
  &MyApp.ServiceDecomposer.decompose/1,
  step_functions,
  MyApp.Repo,
  parallel: true,  # Execute all three in parallel
  optimization_level: :advanced
)
```

---

## Configuration

Configure HTDAG behavior in `config/config.exs`:

```elixir
config :quantum_flow,
  orchestrator: %{
    # Goal decomposition settings
    max_depth: 10,
    timeout: 60_000,
    max_parallel: 10,
    retry_attempts: 3,

    # Decomposer types
    decomposers: %{
      simple: %{max_depth: 5, timeout: 30_000},
      microservices: %{max_depth: 15, timeout: 120_000},
      data_pipeline: %{max_depth: 10, timeout: 60_000},
      ml_pipeline: %{max_depth: 20, timeout: 300_000}
    },

    # Execution settings
    execution: %{
      timeout: 300_000,
      max_parallel: 10,
      retry_attempts: 3,
      retry_delay: 1000,
      task_timeout: 30_000,
      monitor: true
    },

    # Optimization settings
    optimization: %{
      enabled: true,
      level: :advanced,
      preserve_structure: true,
      max_parallel: 10,
      timeout_threshold: 1000,
      learning_enabled: true,
      pattern_confidence_threshold: 0.85
    },

    # Notification settings
    notifications: %{
      enabled: true,
      real_time: true,
      event_types: [:execution_started, :execution_completed, :task_failed],
      queue_prefix: "orchestrator_",
      timeout: 5000
    },

    # Feature flags
    features: %{
      monitoring: true,
      optimization: true,
      notifications: true,
      learning: true,
      real_time: true
    }
  }
```

---

## Best Practices

### 1. Design Robust Decomposers

```elixir
# ✅ GOOD: Handles errors gracefully
def decompose(goal) do
  case parse_goal(goal) do
    {:ok, parsed} -> create_tasks(parsed)
    {:error, reason} ->
      Logger.error("Failed to parse goal: #{reason}")
      {:error, :invalid_goal}
  end
end

# ❌ BAD: No error handling
def decompose(goal) do
  {:ok, create_tasks(goal)}
end
```

### 2. Provide Meaningful Step Functions

```elixir
# ✅ GOOD: Descriptive, returns proper tuple
def analyze_requirements(input) do
  requirements = analyze(input)
  {:ok, %{requirements: requirements}}
end

# ❌ BAD: Opaque, doesn't follow convention
def step_1(x), do: x * 2
```

### 3. Start with Basic, Escalate to Advanced

```elixir
# ✅ GOOD: Start safe, optimize after profiling
{:ok, result} = compose_from_goal(
  goal,
  decomposer,
  steps,
  repo,
  optimization_level: :basic
)

# After confirming with metrics:
{:ok, result} = compose_from_goal(
  goal,
  decomposer,
  steps,
  repo,
  optimization_level: :advanced
)

# ❌ BAD: Jump to aggressive without data
{:ok, result} = compose_from_goal(
  goal,
  decomposer,
  steps,
  repo,
  optimization_level: :aggressive
)
```

### 4. Monitor Execution with Events

```elixir
# ✅ GOOD: Subscribe to events for observability
{:ok, listener} = OrchestratorNotifications.listen("orchestrator_events", repo)

{:ok, result} = WorkflowComposer.compose_from_goal(
  goal,
  decomposer,
  steps,
  repo,
  monitoring: true,
  real_time_notifications: true
)

# ❌ BAD: No monitoring, blind execution
{:ok, result} = WorkflowComposer.compose_from_goal(
  goal,
  decomposer,
  steps,
  repo
)
```

### 5. Use Task Graph Caching for Repeated Goals

```elixir
# ✅ GOOD: Cache and reuse decompositions
cached_task_graphs = %{
  "build_auth" => precomputed_auth_graph,
  "build_payment" => precomputed_payment_graph
}

def get_or_decompose(goal, decomposer, repo) do
  case Map.fetch(cached_task_graphs, goal) do
    {:ok, graph} -> {:ok, graph}
    :error -> Orchestrator.decompose_goal(goal, decomposer, repo)
  end
end

# ❌ BAD: Decompose every time
def compose(goal, decomposer, steps, repo) do
  {:ok, graph} = Orchestrator.decompose_goal(goal, decomposer, repo)
  WorkflowComposer.compose_from_task_graph(graph, steps, repo)
end
```

---

## Troubleshooting

### Issue: Slow decomposition with complex goals

**Solution**: Use rule-based decomposer for known patterns, LLM for unknown

### Issue: Optimization changing workflow semantics

**Solution**: Use `preserve_structure: true` option (default)

### Issue: Missing events

**Solution**: Ensure `real_time_notifications: true` and check queue configuration

### Issue: Low optimization confidence

**Solution**: Collect more execution data (100+ runs recommended) before aggressive optimization

---

## See Also

- [README.md](../README.md) - Project overview
- [ARCHITECTURE.md](./ARCHITECTURE.md) - System architecture
- [QUANTUM_FLOW_REFERENCE.md](./QUANTUM_FLOW_REFERENCE.md) - QuantumFlow comparison
- [DYNAMIC_WORKFLOWS_GUIDE.md](./DYNAMIC_WORKFLOWS_GUIDE.md) - FlowBuilder examples
