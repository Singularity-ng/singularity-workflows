# Orchestrator Integration for quantum_flow

This directory contains the Orchestrator (formerly HTDAG: Hierarchical Task Directed Acyclic Graph) integration for quantum_flow, enabling goal-driven workflow creation and execution.

## Overview

Orchestrator allows you to describe what you want to achieve (goals) rather than how to achieve it (workflow steps). The system automatically decomposes complex goals into hierarchical task graphs and converts them into executable quantum_flow workflows.

## Key Components

### Core Modules

- **`QuantumFlow.Orchestrator`** - Main HTDAG functionality for goal decomposition and workflow creation
- **`QuantumFlow.OrchestratorNotifications`** - Real-time event broadcasting for HTDAG workflows
- **`QuantumFlow.WorkflowComposer`** - High-level API for goal-driven workflow composition
- **`QuantumFlow.OrchestratorOptimizer`** - Workflow optimization based on historical performance data

### Example Implementations

- **`QuantumFlow.Orchestrator.ExampleDecomposer`** - Sample decomposer implementations for common workflow types

## Quick Start

### 1. Define a Decomposer Function

```elixir
defmodule MyApp.GoalDecomposer do
  def decompose(goal) do
    # Your custom decomposition logic
    # Could call LLM, use rules, etc.
    tasks = [
      %{id: "task1", description: "Analyze requirements", depends_on: []},
      %{id: "task2", description: "Design architecture", depends_on: ["task1"]},
      %{id: "task3", description: "Implement solution", depends_on: ["task2"]}
    ]
    
    {:ok, tasks}
  end
end
```

### 2. Define Step Functions

```elixir
step_functions = %{
  "task1" => &MyApp.Tasks.analyze_requirements/1,
  "task2" => &MyApp.Tasks.design_architecture/1,
  "task3" => &MyApp.Tasks.implement_solution/1
}
```

### 3. Compose and Execute Workflow

```elixir
{:ok, result} = QuantumFlow.WorkflowComposer.compose_from_goal(
  "Build user authentication system",
  &MyApp.GoalDecomposer.decompose/1,
  step_functions,
  MyApp.Repo
)
```

## Advanced Usage

### Real-time Monitoring

```elixir
# Listen for HTDAG events
{:ok, pid} = QuantumFlow.OrchestratorNotifications.listen("my_workflow", MyApp.Repo)

# Handle events
receive do
  {:htdag_event, ^pid, event_type, data} ->
    # Process HTDAG event
end
```

### Workflow Optimization

```elixir
# Optimize workflow based on historical data
{:ok, optimized_workflow} = QuantumFlow.OrchestratorOptimizer.optimize_workflow(
  workflow,
  MyApp.Repo,
  optimization_level: :advanced
)
```

### Multiple Workflow Composition

```elixir
# Compose multiple related workflows
{:ok, results} = QuantumFlow.WorkflowComposer.compose_multiple_workflows(
  "Build complete microservices platform",
  &MyApp.GoalDecomposer.decompose_complex/1,
  step_functions,
  MyApp.Repo
)
```

## Example Decomposers

The `ExampleDecomposer` module provides sample implementations for common workflow types:

- **Simple Decomposer** - Linear task sequences for basic workflows
- **Microservices Decomposer** - Parallel service deployment for distributed systems
- **Data Pipeline Decomposer** - ETL workflows for data processing
- **ML Pipeline Decomposer** - Machine learning model development and deployment

## Architecture

```
Goal → HTDAG Decomposition → Task Graph → Workflow Generation → Execution
  ↓           ↓                    ↓              ↓              ↓
Events ← Notifications ← Task Events ← Workflow Events ← Execution Events
```

## Benefits

1. **Goal-Driven**: Describe what you want, not how to do it
2. **Intelligent Decomposition**: Automatic task breakdown and dependency management
3. **Real-time Coordination**: Event-driven execution with PGMQ + NOTIFY
4. **Learning and Optimization**: Workflows improve over time
5. **Flexible**: Works with any decomposer function
6. **Scalable**: Supports complex hierarchical workflows

## Integration with quantum_flow

HTDAG seamlessly integrates with quantum_flow's existing features:

- **Workflow Execution**: Uses `QuantumFlow.Executor` for workflow execution
- **Dynamic Workflows**: Uses `QuantumFlow.FlowBuilder` for workflow creation
- **Real-time Notifications**: Uses `QuantumFlow.Notifications` for event broadcasting
- **Multi-instance Support**: Works with quantum_flow's distributed architecture

## Best Practices

1. **Design Decomposers Carefully**: Your decomposer function is the key to good HTDAG workflows
2. **Use Meaningful Task IDs**: Task IDs should be descriptive and consistent
3. **Handle Dependencies Properly**: Ensure task dependencies are correctly specified
4. **Monitor Performance**: Use HTDAG notifications to monitor workflow execution
5. **Optimize Over Time**: Use the optimizer to improve workflow performance
6. **Test Thoroughly**: Test your decomposer functions with various goal types

## Troubleshooting

### Common Issues

1. **Decomposer Returns Invalid Format**: Ensure your decomposer returns `{:ok, tasks}` where tasks is a list of maps with `id`, `description`, and `depends_on` fields
2. **Missing Step Functions**: Ensure all task IDs have corresponding step functions
3. **Circular Dependencies**: Avoid circular dependencies in task graphs
4. **Timeout Issues**: Adjust timeout settings for long-running decompositions

### Debugging

Enable debug logging to see HTDAG decomposition and execution details:

```elixir
# In your application config
config :logger, level: :debug
```

## Contributing

When adding new HTDAG features:

1. Follow the existing module structure
2. Add comprehensive documentation
3. Include example usage
4. Add tests for new functionality
5. Update this README with new features