defmodule Pgflow.Orchestrator do
  @moduledoc """
  Hierarchical Task Directed Acyclic Graph support for ex_pgflow.
  
  Provides generic HTDAG functionality that can be used by any Elixir application.
  This module bridges goal-driven task decomposition with ex_pgflow workflow execution.
  
  ## Features
  
  - **Goal Decomposition**: Convert high-level goals into hierarchical task graphs
  - **Workflow Generation**: Transform HTDAG tasks into ex_pgflow workflows
  - **Generic Interface**: Works with any decomposer function
  - **Real-time Integration**: Uses PGMQ + NOTIFY for event-driven execution
  
  ## Usage
  
      # Define a decomposer function
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
      
      # Use HTDAG to create and execute workflows
      {:ok, result} = Pgflow.Orchestrator.execute_goal(
        "Build user authentication system",
        &MyApp.GoalDecomposer.decompose/1,
        step_functions,
        MyApp.Repo
      )
  
  ## Architecture

  HTDAG integrates with ex_pgflow's existing components:

  - **Goal Decomposition**: Custom decomposer functions
  - **Task Graph**: Hierarchical task structure with dependencies
  - **Workflow Generation**: Uses FlowBuilder for dynamic workflow creation
  - **Execution**: Uses Executor for workflow execution
  - **Notifications**: Uses Notifications for real-time events

  ## AI Navigation Metadata

  ### Module Identity
  - **Type**: Orchestration Engine (core infrastructure)
  - **Purpose**: Transform goals → task DAGs → executable workflows
  - **Disambiguates from**:
    - `Pgflow.Executor` (low-level task execution)
    - `Pgflow.WorkflowComposer` (high-level API wrapper)
    - `Pgflow.FlowBuilder` (raw workflow creation)

  ### Call Graph
  - `decompose_goal/3` → `build_task_graph`, `convert_tasks_to_steps`
  - `create_workflow/3` → `FlowBuilder.create_workflow`, `convert_tasks_to_steps`
  - `execute_goal/5` → `decompose_goal`, `create_workflow`, `Executor.execute_workflow`
  - **Integrates**: Executor, FlowBuilder, Notifications, Config, Repository

  ### Anti-Patterns (Duplicate Prevention)
  - ❌ DO NOT create another "Orchestrator" module - this is the single source of truth
  - ❌ DO NOT call `Executor.execute_workflow` directly from user code - use `Orchestrator.execute_goal`
  - ❌ DO NOT hard-code task definitions - use decomposer pattern from `ExampleDecomposer`
  - ❌ DO NOT ignore task dependencies - always validate in `build_task_graph`
  - ✅ DO use `execute_goal` for all goal-driven workflows
  - ✅ DO pass custom decomposer functions for domain-specific logic

  ### Search Keywords
  goal_decomposition, hierarchical_tasks, task_dag, workflow_orchestration, htdag,
  autonomous_decomposition, task_dependencies, pgflow_orchestration, goal_execution,
  workflow_composition, goal_driven_execution, task_graph_creation, decomposer_pattern
  """

  require Logger

  @doc """
  Decompose a complex goal into hierarchical tasks.
  
  ## Parameters
  
  - `goal` - Goal description (string or map)
  - `decomposer` - Function that takes goal and returns task list
  - `opts` - Options for decomposition
    - `:max_depth` - Maximum decomposition depth (default: 5)
    - `:parallel_threshold` - Minimum tasks for parallel execution (default: 2)
    - `:timeout` - Decomposition timeout in milliseconds (default: 30000)
  
  ## Returns
  
  - `{:ok, task_graph}` - Hierarchical task structure
  - `{:error, reason}` - Decomposition failed
  
  ## Example
  
      {:ok, tasks} = Pgflow.Orchestrator.decompose_goal(
        "Build microservices architecture",
        &MyApp.GoalDecomposer.decompose/1,
        max_depth: 3,
        timeout: 60000
      )
  """
  @spec decompose_goal(any(), function(), keyword()) :: {:ok, map()} | {:error, any()}
  def decompose_goal(goal, decomposer, opts \\ []) do
    # Get configuration with overrides
    config = Pgflow.Orchestrator.Config.get_execution_config(opts)
    max_depth = Keyword.get(opts, :max_depth, config.max_depth)
    timeout = Keyword.get(opts, :timeout, config.timeout)
    
    Logger.info("Starting HTDAG decomposition for goal: #{inspect(goal)}")
    
    # Broadcast decomposition started event
    if Pgflow.Orchestrator.Config.feature_enabled?(:notifications) do
      goal_id = generate_goal_id(goal)
      Pgflow.OrchestratorNotifications.broadcast_decomposition(goal_id, :started, %{
        goal: goal,
        max_depth: max_depth
      }, Keyword.get(opts, :repo))
    end
    
    try do
      case decomposer.(goal) do
        {:ok, tasks} when is_list(tasks) ->
          task_graph = build_task_graph(tasks, max_depth)
          Logger.info("HTDAG decomposition completed with #{length(tasks)} tasks")
          
          # Broadcast decomposition completed event
          if Pgflow.Orchestrator.Config.feature_enabled?(:notifications) do
            goal_id = generate_goal_id(goal)
            Pgflow.OrchestratorNotifications.broadcast_decomposition(goal_id, :completed, %{
              task_count: length(tasks),
              max_depth: max_depth
            }, Keyword.get(opts, :repo))
          end
          
          {:ok, task_graph}
          
        {:error, reason} ->
          Logger.error("HTDAG decomposition failed: #{inspect(reason)}")
          
          # Broadcast decomposition failed event
          if Pgflow.Orchestrator.Config.feature_enabled?(:notifications) do
            goal_id = generate_goal_id(goal)
            Pgflow.OrchestratorNotifications.broadcast_decomposition(goal_id, :failed, %{
              error: inspect(reason)
            }, Keyword.get(opts, :repo))
          end
          
          {:error, reason}
          
        other ->
          Logger.error("Invalid decomposer result: #{inspect(other)}")
          {:error, :invalid_decomposer_result}
      end
    rescue
      error ->
        Logger.error("HTDAG decomposition error: #{inspect(error)}")
        
        # Broadcast decomposition failed event
        if Pgflow.Orchestrator.Config.feature_enabled?(:notifications) do
          goal_id = generate_goal_id(goal)
          Pgflow.OrchestratorNotifications.broadcast_decomposition(goal_id, :failed, %{
            error: inspect(error)
          }, Keyword.get(opts, :repo))
        end
        
        {:error, error}
    end
  end

  @doc """
  Create a workflow from HTDAG task graph.
  
  ## Parameters
  
  - `task_graph` - HTDAG task structure from decompose_goal/3
  - `step_functions` - Map of task_id -> function for execution
  - `opts` - Workflow options
    - `:workflow_name` - Name for the generated workflow (default: "htdag_workflow")
    - `:max_parallel` - Maximum parallel tasks (default: 10)
    - `:retry_attempts` - Retry attempts for failed tasks (default: 3)
  
  ## Returns
  
  - `{:ok, workflow}` - ex_pgflow workflow that can be executed
  - `{:error, reason}` - Creation failed
  
  ## Example
  
      step_functions = %{
        "task1" => &MyApp.Tasks.analyze_requirements/1,
        "task2" => &MyApp.Tasks.design_architecture/1,
        "task3" => &MyApp.Tasks.implement_solution/1
      }
      
      {:ok, workflow} = Pgflow.Orchestrator.create_workflow(task_graph, step_functions)
  """
  @spec create_workflow(map(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def create_workflow(task_graph, step_functions, opts \\ []) do
    workflow_name = Keyword.get(opts, :workflow_name, "htdag_workflow")
    max_parallel = Keyword.get(opts, :max_parallel, 10)
    retry_attempts = Keyword.get(opts, :retry_attempts, 3)
    
    Logger.info("Creating workflow from HTDAG task graph with #{map_size(task_graph.tasks)} tasks")
    
    try do
      # Convert HTDAG tasks to ex_pgflow workflow steps
      workflow_steps = convert_tasks_to_steps(task_graph.tasks, step_functions, retry_attempts)
      
      # Create workflow definition
      workflow = %{
        name: workflow_name,
        steps: workflow_steps,
        max_parallel: max_parallel,
        created_at: DateTime.utc_now(),
        task_graph: task_graph
      }
      
      Logger.info("Workflow created successfully: #{workflow_name}")
      {:ok, workflow}
    rescue
      error ->
        Logger.error("Failed to create workflow: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Execute a goal using HTDAG decomposition and ex_pgflow execution.
  
  This is a convenience function that combines decomposition, workflow creation,
  and execution into a single call.
  
  ## Parameters
  
  - `goal` - Goal to decompose and execute
  - `decomposer` - Function: (goal) -> {:ok, tasks}
  - `step_functions` - Map of task_id -> function
  - `repo` - Ecto repository
  - `opts` - Options for decomposition and execution
  
  ## Returns
  
  - `{:ok, result}` - Workflow execution result
  - `{:error, reason}` - Failed at any step
  
  ## Example
  
      {:ok, result} = Pgflow.Orchestrator.execute_goal(
        "Deploy microservices architecture",
        &MyApp.GoalDecomposer.decompose/1,
        step_functions,
        MyApp.Repo,
        max_depth: 3
      )
  """
  @spec execute_goal(any(), function(), map(), Ecto.Repo.t(), keyword()) :: 
    {:ok, any()} | {:error, any()}
  def execute_goal(goal, decomposer, step_functions, repo, opts \\ []) do
    with {:ok, task_graph} <- decompose_goal(goal, decomposer, opts),
         {:ok, workflow} <- create_workflow(task_graph, step_functions, opts) do
      
      Logger.info("Executing HTDAG workflow: #{workflow.name}")
      
      # Execute the workflow
      Pgflow.Executor.execute(workflow, %{goal: goal}, repo)
    end
  end

  @doc """
  Get execution statistics for HTDAG workflows.
  
  ## Parameters
  
  - `workflow_name` - Name of the workflow (optional)
  - `repo` - Ecto repository
  - `opts` - Query options
    - `:since` - Filter by start date
    - `:until` - Filter by end date
  
  ## Returns
  
  - `{:ok, stats}` - Execution statistics
  - `{:error, reason}` - Failed to get stats
  """
  @spec get_execution_stats(String.t() | nil, Ecto.Repo.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def get_execution_stats(workflow_name \\ nil, repo, opts \\ []) do
    # Get workflow ID if workflow_name is provided
    workflow_id = if workflow_name do
      case Pgflow.Orchestrator.Repository.get_workflows_by_name(workflow_name, repo, limit: 1) do
        {:ok, [workflow | _]} -> workflow.id
        _ -> nil
      end
    else
      nil
    end
    
    Pgflow.Orchestrator.Repository.get_execution_stats(repo, Keyword.put(opts, :workflow_id, workflow_id))
  end

  # Private functions

  defp build_task_graph(tasks, max_depth) do
    # Build hierarchical task graph from flat task list
    # Add depth tracking, dependency validation, etc.
    
    # Validate task dependencies
    task_ids = MapSet.new(tasks, & &1.id)
    valid_tasks = Enum.filter(tasks, fn task ->
      Enum.all?(task.depends_on, &MapSet.member?(task_ids, &1))
    end)
    
    if length(valid_tasks) != length(tasks) do
      Logger.warn("Some tasks have invalid dependencies and were filtered out")
    end
    
    # Calculate task depths
    tasks_with_depth = calculate_task_depths(valid_tasks)
    
    %{
      tasks: Enum.into(tasks_with_depth, %{}, &{&1.id, &1}),
      root_tasks: Enum.filter(tasks_with_depth, &(length(&1.depends_on) == 0)),
      max_depth: max_depth,
      created_at: DateTime.utc_now()
    }
  end

  defp calculate_task_depths(tasks) do
    task_map = Enum.into(tasks, %{}, &{&1.id, &1})
    
    # Calculate depth for each task using topological sort
    depths = calculate_depths_recursive(tasks, task_map, %{})
    
    Enum.map(tasks, fn task ->
      Map.put(task, :depth, Map.get(depths, task.id, 0))
    end)
  end

  defp calculate_depths_recursive(tasks, task_map, depths) do
    Enum.reduce(tasks, depths, fn task, acc ->
      if Map.has_key?(acc, task.id) do
        acc
      else
        depth = calculate_task_depth(task, task_map, acc)
        Map.put(acc, task.id, depth)
      end
    end)
  end

  defp calculate_task_depth(task, task_map, depths) do
    if length(task.depends_on) == 0 do
      0
    else
      max_dependency_depth = task.depends_on
      |> Enum.map(fn dep_id ->
        case Map.get(depths, dep_id) do
          nil -> 
            # Calculate depth of dependency recursively
            dep_task = Map.get(task_map, dep_id)
            if dep_task, do: calculate_task_depth(dep_task, task_map, depths), else: 0
          depth -> depth
        end
      end)
      |> Enum.max(fn -> 0 end)
      
      max_dependency_depth + 1
    end
  end

  defp convert_tasks_to_steps(tasks, step_functions, retry_attempts) do
    # Convert HTDAG tasks to ex_pgflow workflow steps
    tasks
    |> Enum.map(fn {task_id, task} ->
      step_function = Map.get(step_functions, task_id)
      
      if step_function do
        step_config = %{
          name: String.to_atom(task_id),
          function: step_function,
          depends_on: Enum.map(task.depends_on, &String.to_atom/1),
          max_attempts: retry_attempts,
          timeout: Map.get(task, :timeout, 30_000),
          retry_delay: Map.get(task, :retry_delay, 1_000),
          description: Map.get(task, :description, task_id)
        }
        
        # Add depth information for optimization
        if Map.has_key?(task, :depth) do
          Map.put(step_config, :depth, task.depth)
        else
          step_config
        end
      else
        raise "No step function found for task: #{task_id}"
      end
    end)
  end

  defp generate_goal_id(goal) do
    case goal do
      goal when is_binary(goal) -> 
        "goal_#{:crypto.hash(:md5, goal) |> Base.encode16(case: :lower) |> String.slice(0, 8)}"
      goal when is_map(goal) ->
        goal_string = Map.get(goal, :description, Map.get(goal, :goal, inspect(goal)))
        "goal_#{:crypto.hash(:md5, goal_string) |> Base.encode16(case: :lower) |> String.slice(0, 8)}"
      _ ->
        "goal_#{:erlang.system_time(:millisecond)}"
    end
  end
end