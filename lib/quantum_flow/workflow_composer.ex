defmodule QuantumFlow.WorkflowComposer do
  @moduledoc """
  Compose workflows from HTDAG decomposition.

  Provides high-level API for creating and executing goal-driven workflows
  using HTDAG task decomposition and quantum_flow execution.

  ## Features

  - **Goal-Driven Workflows**: Describe what you want, not how to do it
  - **HTDAG Integration**: Automatic task decomposition
  - **Workflow Generation**: Convert tasks to executable workflows
  - **Real-time Execution**: Event-driven workflow execution
  - **Performance Optimization**: Automatic parallelization and optimization

  ## Usage

      # Define step functions for your tasks
      step_functions = %{
        "analyze" => &MyApp.Tasks.analyze_requirements/1,
        "design" => &MyApp.Tasks.design_architecture/1,
        "implement" => &MyApp.Tasks.implement_solution/1,
        "test" => &MyApp.Tasks.test_solution/1,
        "deploy" => &MyApp.Tasks.deploy_solution/1
      }
      
      # Compose and execute workflow from goal
      {:ok, result} = QuantumFlow.WorkflowComposer.compose_from_goal(
        "Build microservices authentication system",
        &MyApp.GoalDecomposer.decompose/1,
        step_functions,
        MyApp.Repo
      )

  ## Architecture

  WorkflowComposer orchestrates the following components:

  1. **Goal Decomposition**: Uses HTDAG to break down goals
  2. **Task Analysis**: Analyzes task dependencies and requirements
  3. **Workflow Generation**: Creates optimized quantum_flow workflows
  4. **Execution**: Runs workflows with real-time monitoring
  5. **Optimization**: Learns from execution to improve future workflows

  ## AI Navigation Metadata

  ### Module Identity
  - **Type**: High-Level API (facade)
  - **Purpose**: Unified entry point for goal-driven workflow composition
  - **Wraps**: QuantumFlow.Orchestrator, QuantumFlow.OrchestratorOptimizer

  ### Call Graph
  - `compose_from_goal/5` → Orchestrator.decompose_goal, create_workflow, execute
  - `compose_from_task_graph/4` → Orchestrator.create_workflow, execute
  - `compose_multiple_workflows/5` → parallel composition and execution
  - **Integrates**: Orchestrator, OrchestratorOptimizer, Executor, OrchestratorNotifications

  ### Anti-Patterns
  - ❌ DO NOT bypass WorkflowComposer to call Orchestrator directly from user code
  - ❌ DO NOT compose workflows without step_functions - they're required
  - ✅ DO use compose_from_goal for simple goal-driven workflows
  - ✅ DO pass monitoring/optimization flags for production workflows

  ### Search Keywords
  workflow_composition, goal_driven_api, high_level_api, workflow_generation,
  composition_api, facade_pattern, orchestration_coordination, workflow_execution,
  unified_entry_point, goal_to_workflow

  ### Decision Tree (Which Composition Function to Use?)

  ```
  What do you want to compose?
  ├─ YES: I have a goal string/description
  │  ├─ Is it a simple goal?
  │  │  └─ Use `compose_from_goal/5` (simplest, all-in-one)
  │  │
  │  └─ Is it a very complex goal with multiple sub-goals?
  │     └─ Use `compose_multiple_workflows/5` (breaks into multiple workflows)
  │
  ├─ NO: I already have a task graph
  │  └─ Use `compose_from_task_graph/4` (skip decomposition)
  │
  └─ Additional options
     ├─ Want real-time monitoring?
     │  └─ Pass `monitor: true` in opts
     │
     ├─ Want workflow optimization?
     │  └─ Pass `optimize: true` in opts
     │
     └─ Want statistics/history?
        └─ Use `get_composition_stats/2`
  ```

  ### Data Flow Diagram

  ```
  User Goal Input
      │
      ├─ compose_from_goal/5
      │  │
      │  ├─ decompose_goal(goal, decomposer)
      │  │  │ (Orchestrator → GoalDecomposer function)
      │  │  └─ Task Graph + Dependencies
      │  │
      │  ├─ create_workflow(task_graph, step_functions)
      │  │  │ (Orchestrator → quantum_flow format)
      │  │  └─ Workflow + Steps
      │  │
      │  ├─ maybe_optimize_workflow(workflow, optimize flag)
      │  │  │ (OrchestratorOptimizer if enabled)
      │  │  └─ Optimized Workflow
      │  │
      │  └─ execute_workflow(workflow, monitor flag)
      │     │ (Executor.execute_workflow with/without monitoring)
      │     │ (Broadcasts events if notifications enabled)
      │     └─ Workflow Result
      │
      ├─ compose_from_task_graph/4
      │  └─ [Skip decomposition] → create_workflow → execute_workflow
      │
      └─ compose_multiple_workflows/5
         └─ decompose_complex_goal (returns list of task_graphs)
            └─ Parallel execution of multiple workflows
  ```
  """

  require Logger

  @doc """
  Compose a workflow from goal decomposition.

  This is the main entry point for goal-driven workflow creation and execution.

  ## Parameters

  - `goal` - Goal to decompose and execute
  - `decomposer` - Function: (goal) -> {:ok, tasks}
  - `step_functions` - Map of task_id -> function for execution
  - `repo` - Ecto repository
  - `opts` - Options for composition and execution
    - `:workflow_name` - Name for the generated workflow
    - `:max_depth` - Maximum decomposition depth
    - `:max_parallel` - Maximum parallel tasks
    - `:retry_attempts` - Retry attempts for failed tasks
    - `:timeout` - Execution timeout in milliseconds
    - `:optimize` - Enable workflow optimization (default: true)
    - `:monitor` - Enable real-time monitoring (default: true)

  ## Returns

  - `{:ok, result}` - Workflow execution result
  - `{:error, reason}` - Failed at any step

  ## Example

      {:ok, result} = QuantumFlow.WorkflowComposer.compose_from_goal(
        "Deploy microservices architecture",
        &MyApp.GoalDecomposer.decompose/1,
        step_functions,
        MyApp.Repo,
        workflow_name: "microservices_deployment",
        max_depth: 3,
        max_parallel: 5
      )
  """
  @spec compose_from_goal(any(), function(), map(), Ecto.Repo.t(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def compose_from_goal(goal, decomposer, step_functions, repo, opts \\ []) do
    _workflow_name = Keyword.get(opts, :workflow_name, generate_workflow_name(goal))

    optimize =
      Keyword.get(opts, :optimize, QuantumFlow.Orchestrator.Config.feature_enabled?(:optimization))

    monitor =
      Keyword.get(opts, :monitor, QuantumFlow.Orchestrator.Config.feature_enabled?(:monitoring))

    Logger.info("Composing workflow from goal: #{inspect(goal)}")

    # Add repo to opts for notifications
    opts_with_repo = Keyword.put(opts, :repo, repo)

    with {:ok, task_graph} <- decompose_goal(goal, decomposer, opts_with_repo),
         {:ok, workflow} <- create_workflow(task_graph, step_functions, opts),
         {:ok, optimized_workflow} <- maybe_optimize_workflow(workflow, optimize, repo),
         {:ok, result} <- execute_workflow(optimized_workflow, goal, monitor, repo) do
      Logger.info("Workflow composition completed successfully")
      {:ok, result}
    end
  end

  @doc """
  Compose a workflow from existing task graph.

  Useful when you already have a task graph and want to create a workflow from it.

  ## Parameters

  - `task_graph` - Pre-existing task graph
  - `step_functions` - Map of task_id -> function
  - `repo` - Ecto repository
  - `opts` - Workflow options

  ## Returns

  - `{:ok, result}` - Workflow execution result
  - `{:error, reason}` - Failed

  ## Example

      {:ok, result} = QuantumFlow.WorkflowComposer.compose_from_task_graph(
        task_graph,
        step_functions,
        MyApp.Repo
      )
  """
  @spec compose_from_task_graph(map(), map(), Ecto.Repo.t(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def compose_from_task_graph(task_graph, step_functions, repo, opts \\ []) do
    Logger.info("Composing workflow from existing task graph")

    with {:ok, workflow} <- create_workflow(task_graph, step_functions, opts),
         {:ok, result} <- execute_workflow(workflow, %{}, true, repo) do
      {:ok, result}
    end
  end

  @doc """
  Compose multiple workflows from a complex goal.

  For very complex goals, this can create multiple related workflows
  that execute in coordination.

  ## Parameters

  - `goal` - Complex goal to decompose
  - `decomposer` - Function: (goal) -> {:ok, task_graphs}
  - `step_functions` - Map of task_id -> function
  - `repo` - Ecto repository
  - `opts` - Composition options

  ## Returns

  - `{:ok, results}` - List of workflow execution results
  - `{:error, reason}` - Failed

  ## Example

      {:ok, results} = QuantumFlow.WorkflowComposer.compose_multiple_workflows(
        "Build complete microservices platform",
        &MyApp.GoalDecomposer.decompose_complex/1,
        step_functions,
        MyApp.Repo
      )
  """
  @spec compose_multiple_workflows(any(), function(), map(), Ecto.Repo.t(), keyword()) ::
          {:ok, list()} | {:error, any()}
  def compose_multiple_workflows(goal, decomposer, step_functions, repo, opts \\ []) do
    Logger.info("Composing multiple workflows from complex goal: #{inspect(goal)}")

    with {:ok, task_graphs} <- decompose_complex_goal(goal, decomposer, opts) do
      # Execute each workflow in parallel
      results =
        task_graphs
        |> Enum.map(fn task_graph ->
          compose_from_task_graph(task_graph, step_functions, repo, opts)
        end)
        |> Enum.with_index()
        |> Enum.map(fn {{:ok, result}, index} ->
          {:ok, Map.put(result, :workflow_index, index)}
        end)

      # Check if all workflows succeeded
      if Enum.all?(results, &match?({:ok, _}, &1)) do
        successful_results = Enum.map(results, fn {:ok, result} -> result end)
        Logger.info("All #{length(successful_results)} workflows completed successfully")
        {:ok, successful_results}
      else
        failed_results = Enum.filter(results, &match?({:error, _}, &1))
        Logger.error("Failed to execute #{length(failed_results)} workflows")
        {:error, :workflow_execution_failed}
      end
    end
  end

  @doc """
  Get composition statistics.

  ## Parameters

  - `repo` - Ecto repository
  - `opts` - Query options
    - `:workflow_name` - Filter by workflow name
    - `:since` - Filter by creation date
    - `:limit` - Maximum number of results

  ## Returns

  - `{:ok, stats}` - Composition statistics
  - `{:error, reason}` - Failed to get stats
  """
  @spec get_composition_stats(Ecto.Repo.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def get_composition_stats(repo, opts \\ []) do
    import Ecto.Query
    require Logger

    # Get time range from opts (default to last 30 days)
    since_date =
      Keyword.get(opts, :since, DateTime.add(DateTime.utc_now(), -30 * 24 * 60 * 60, :second))

    # Count total workflows
    total_query =
      from(w in QuantumFlow.Orchestrator.Schemas.Workflow,
        where: w.inserted_at >= ^since_date,
        select: count(w.id)
      )

    total_workflows = repo.one(total_query) || 0

    # Count successful compositions
    success_query =
      from(w in QuantumFlow.Orchestrator.Schemas.Workflow,
        where: w.inserted_at >= ^since_date and w.status == "completed",
        select: count(w.id)
      )

    successful_compositions = repo.one(success_query) || 0

    # Count failed compositions
    failed_query =
      from(w in QuantumFlow.Orchestrator.Schemas.Workflow,
        where: w.inserted_at >= ^since_date and w.status == "failed",
        select: count(w.id)
      )

    failed_compositions = repo.one(failed_query) || 0

    # Calculate average execution time
    avg_time_query =
      from(e in QuantumFlow.Orchestrator.Schemas.Execution,
        join: w in QuantumFlow.Orchestrator.Schemas.Workflow,
        on: e.workflow_id == w.id,
        where:
          w.inserted_at >= ^since_date and e.status == "completed" and not is_nil(e.duration_ms),
        select: avg(e.duration_ms)
      )

    avg_execution_time = repo.one(avg_time_query) || 0

    # Find most common goals
    goals_query =
      from(tg in QuantumFlow.Orchestrator.Schemas.TaskGraph,
        join: w in QuantumFlow.Orchestrator.Schemas.Workflow,
        on: w.task_graph_id == tg.id,
        where: w.inserted_at >= ^since_date,
        group_by: tg.goal,
        order_by: [desc: count(tg.id)],
        limit: 5,
        select: {tg.goal, count(tg.id)}
      )

    goal_stats = repo.all(goals_query) || []

    most_common_goals =
      Enum.map(goal_stats, fn {goal, count} ->
        %{goal: goal, count: count}
      end)

    {:ok,
     %{
       total_workflows: total_workflows,
       successful_compositions: successful_compositions,
       failed_compositions: failed_compositions,
       avg_execution_time: round(avg_execution_time),
       most_common_goals: most_common_goals
     }}
  rescue
    error ->
      Logger.error("Failed to get composition stats: #{inspect(error)}")
      {:error, error}
  end

  # Private functions

  defp decompose_goal(goal, decomposer, opts) do
    QuantumFlow.Orchestrator.decompose_goal(goal, decomposer, opts)
  end

  defp create_workflow(task_graph, step_functions, opts) do
    QuantumFlow.Orchestrator.create_workflow(task_graph, step_functions, opts)
  end

  defp decompose_complex_goal(goal, decomposer, opts) do
    # Pass options to decomposer for configuration
    # For complex goals, the decomposer should return multiple task graphs
    case decomposer.(goal, opts) do
      {:ok, task_graphs} when is_list(task_graphs) ->
        {:ok, task_graphs}

      {:ok, single_graph} ->
        {:ok, [single_graph]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_optimize_workflow(workflow, true, repo) do
    # Automatic optimization using orchestrator optimizer
    Logger.info("Optimizing workflow: #{workflow.name}")

    # Use the OrchestratorOptimizer with automatic defaults
    case QuantumFlow.OrchestratorOptimizer.optimize_workflow(
           workflow,
           repo,
           optimization_level: :advanced,
           preserve_structure: true,
           max_parallel: 10
         ) do
      {:ok, optimized_workflow} ->
        Logger.info("Workflow optimized successfully with advanced optimizations")
        {:ok, optimized_workflow}

      {:error, reason} ->
        Logger.warning("Optimization failed, using original workflow: #{inspect(reason)}")
        # Fall back to unoptimized workflow
        {:ok, workflow}
    end
  end

  defp maybe_optimize_workflow(workflow, false, _repo) do
    {:ok, workflow}
  end

  defp execute_workflow(workflow, goal, true, repo) do
    # Execute with real-time monitoring using HTDAG executor
    Logger.info("Executing workflow with monitoring: #{workflow.name}")

    # Use HTDAG executor for enhanced monitoring
    QuantumFlow.Orchestrator.Executor.execute_workflow(workflow, %{goal: goal}, repo, monitor: true)
  end

  defp execute_workflow(workflow, goal, false, repo) do
    # Execute without monitoring using base executor
    Logger.info("Executing workflow: #{workflow.name}")
    QuantumFlow.Orchestrator.Executor.execute_workflow(workflow, %{goal: goal}, repo)
  end

  defp generate_workflow_name(goal) do
    # Generate a workflow name from the goal
    goal_string =
      case goal do
        goal when is_binary(goal) -> goal
        goal when is_map(goal) -> Map.get(goal, :description, "workflow")
        _ -> "workflow"
      end

    # Clean up the goal string to make it a valid workflow name
    clean_name =
      goal_string
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s]/, "")
      |> String.replace(~r/\s+/, "_")
      |> String.slice(0, 50)

    "htdag_#{clean_name}_#{:erlang.system_time(:millisecond)}"
  end
end
