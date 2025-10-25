defmodule Pgflow.DAG.DynamicWorkflowLoader do
  @moduledoc """
  Loads workflow definitions from database (created via FlowBuilder).

  Converts DB-stored definitions into WorkflowDefinition structs for execution.
  Enables AI/LLM-generated workflows to run through the same execution engine
  as code-based workflows.

  ## Architecture

  Dynamic workflows:
  1. Created via FlowBuilder.create_flow() + add_step()
  2. Loaded from DB by this module
  3. Converted to WorkflowDefinition struct
  4. Executed via standard TaskExecutor

  ## Integration

  The Executor automatically detects workflow type:
  - String workflow_slug → Load from DB (dynamic)
  - Module with __workflow_steps__/0 → Parse from code (static)
  """

  alias Pgflow.DAG.WorkflowDefinition

  @doc """
  Loads a dynamic workflow from database.

  ## Parameters

    - `workflow_slug` - Workflow identifier
    - `step_functions` - Map of step_slug atoms to functions
    - `repo` - Ecto repo module

  ## Returns

    - `{:ok, %WorkflowDefinition{}}` - Loaded and validated
    - `{:error, reason}` - Not found or invalid

  ## Examples

      step_functions = %{
        fetch: fn _input -> {:ok, %{data: "fetched"}} end,
        process: fn input -> {:ok, Map.put(input, "processed", true)} end
      }

      {:ok, definition} = DynamicWorkflowLoader.load("ai_workflow", step_functions, repo)
  """
  @spec load(String.t(), map(), module()) :: {:ok, WorkflowDefinition.t()} | {:error, term()}
  def load(workflow_slug, step_functions, repo) when is_binary(workflow_slug) do
    with {:ok, workflow_data} <- fetch_workflow(workflow_slug, repo),
         {:ok, steps_data} <- fetch_steps(workflow_slug, repo),
         {:ok, deps_data} <- fetch_dependencies(workflow_slug, repo) do
      build_definition(workflow_slug, workflow_data, steps_data, deps_data, step_functions)
    end
  end

  # Fetch workflow record from DB
  defp fetch_workflow(workflow_slug, repo) do
    case repo.query("SELECT * FROM workflows WHERE workflow_slug = $1::text", [workflow_slug]) do
      {:ok, %{columns: columns, rows: [row]}} ->
        workflow = Enum.zip(columns, row) |> Map.new()
        {:ok, workflow}

      {:ok, %{rows: []}} ->
        {:error, {:workflow_not_found, workflow_slug}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Fetch all steps for workflow
  defp fetch_steps(workflow_slug, repo) do
    case repo.query(
           """
           SELECT * FROM workflow_steps
           WHERE workflow_slug = $1::text
           ORDER BY step_index
           """,
           [workflow_slug]
         ) do
      {:ok, %{columns: columns, rows: rows}} ->
        steps = Enum.map(rows, fn row -> Enum.zip(columns, row) |> Map.new() end)
        {:ok, steps}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Fetch all dependencies for workflow
  defp fetch_dependencies(workflow_slug, repo) do
    case repo.query(
           """
           SELECT step_slug, dep_slug FROM workflow_step_dependencies_def
           WHERE workflow_slug = $1::text
           """,
           [workflow_slug]
         ) do
      {:ok, %{rows: rows}} ->
        # Build map: step_slug => [dep_slugs]
        deps =
          rows
          |> Enum.group_by(fn [step_slug, _dep] -> step_slug end, fn [_step, dep_slug] -> dep_slug end)

        {:ok, deps}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Build WorkflowDefinition struct from DB data
  defp build_definition(workflow_slug, _workflow_data, steps_data, deps_data, step_functions) do
    # Convert steps to WorkflowDefinition format
    steps_list =
      Enum.map(steps_data, fn step ->
        step_slug_atom = String.to_existing_atom(step["step_slug"])
        step_fn = Map.get(step_functions, step_slug_atom)

        if step_fn == nil do
          raise "Missing function for step #{step["step_slug"]} in dynamic workflow #{workflow_slug}"
        end

        depends_on =
          deps_data
          |> Map.get(step["step_slug"], [])
          |> Enum.map(&String.to_existing_atom/1)

        initial_tasks = step["initial_tasks"]
        max_attempts = step["max_attempts"] || 3
        timeout = step["timeout"]

        {step_slug_atom, step_fn, depends_on: depends_on, initial_tasks: initial_tasks, max_attempts: max_attempts, timeout: timeout}
      end)

    # Parse using WorkflowDefinition.parse_steps
    {:ok, parsed} = WorkflowDefinition.parse_steps(steps_list)

    # Validate and build full definition
    with :ok <- WorkflowDefinition.validate_dependencies(parsed.steps, parsed.dependencies),
         :ok <- WorkflowDefinition.validate_no_cycles(parsed.dependencies),
         {:ok, root_steps} <- WorkflowDefinition.find_root_steps(parsed.dependencies) do
      {:ok,
       %WorkflowDefinition{
         steps: parsed.steps,
         dependencies: parsed.dependencies,
         root_steps: root_steps,
         slug: workflow_slug,
         step_metadata: parsed.step_metadata
       }}
    end
  end
end
