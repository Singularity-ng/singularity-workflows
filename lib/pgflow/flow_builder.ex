defmodule Pgflow.FlowBuilder do
  @moduledoc """
  API for building workflows dynamically at runtime.

  Enables AI/LLM agents to generate workflows on-the-fly without code changes.

  ## Usage

  ### Create a workflow

      {:ok, workflow} = Pgflow.FlowBuilder.create_flow("ai_generated_workflow", repo,
        max_attempts: 5,
        timeout: 60
      )

  ### Add steps with dependencies

      {:ok, _} = Pgflow.FlowBuilder.add_step("ai_generated_workflow", "fetch_data", [], repo)

      {:ok, _} = Pgflow.FlowBuilder.add_step("ai_generated_workflow", "process", ["fetch_data"], repo,
        initial_tasks: 10,  # Map step - process 10 items
        max_attempts: 3
      )

      {:ok, _} = Pgflow.FlowBuilder.add_step("ai_generated_workflow", "save", ["process"], repo)

  ### Execute the dynamic workflow

      # Register step functions
      step_functions = %{
        fetch_data: fn _input -> {:ok, %{data: [1, 2, 3]}} end,
        process: fn input -> {:ok, Map.get(input, "item")} end,
        save: fn input -> {:ok, input} end
      }

      {:ok, result} = Pgflow.Executor.execute_dynamic(
        "ai_generated_workflow",
        %{"input" => "data"},
        step_functions,
        repo
      )

  ## AI/LLM Integration

  Perfect for:
  - Claude generating custom workflows from natural language
  - Multi-agent systems creating sub-workflows
  - A/B testing different workflow structures
  - Dynamic workflow optimization
  - User-specific workflow customization

  ## Architecture

  Dynamic workflows use the same execution engine as code-based workflows:
  - Stored in PostgreSQL (workflows, workflow_steps, workflow_step_dependencies_def tables)
  - Execute via same pgmq coordination layer
  - Same performance characteristics
  - Same error handling & retry logic

  Only difference: Definition source (DB vs code modules)
  """

  @doc """
  Creates a new workflow definition.

  ## Parameters

    - `workflow_slug` - Unique identifier (must match `^[a-zA-Z_][a-zA-Z0-9_]*$`)
    - `repo` - Ecto repo module
    - `opts` - Options:
      - `:max_attempts` - Default retry count for all steps (default: 3)
      - `:timeout` - Default timeout in seconds (default: 60, matches pgflow)

  ## Returns

    - `{:ok, workflow_map}` - Workflow created successfully
    - `{:error, reason}` - Validation or database error

  ## Examples

      {:ok, workflow} = FlowBuilder.create_flow("my_workflow", MyApp.Repo)

      {:ok, workflow} = FlowBuilder.create_flow("retry_workflow", MyApp.Repo,
        max_attempts: 5,
        timeout: 120
      )
  """
  @spec create_flow(String.t(), module(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_flow(workflow_slug, repo, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    timeout = Keyword.get(opts, :timeout, 30)

    case repo.query(
           """
           SELECT * FROM pgflow.create_flow($1::text, $2::integer, $3::integer)
           """,
           [workflow_slug, max_attempts, timeout]
         ) do
      {:ok, %{columns: columns, rows: [row]}} ->
        workflow = Enum.zip(columns, row) |> Map.new()
        {:ok, workflow}

      {:ok, %{rows: []}} ->
        {:error, :workflow_creation_failed}

      {:error, %Postgrex.Error{} = error} ->
        {:error, parse_postgres_error(error)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Adds a step to a workflow definition.

  ## Parameters

    - `workflow_slug` - Workflow identifier (must exist via create_flow)
    - `step_slug` - Step identifier (must match `^[a-zA-Z_][a-zA-Z0-9_]*$`)
    - `depends_on` - List of step slugs this step depends on
    - `repo` - Ecto repo module
    - `opts` - Options:
      - `:step_type` - "single" or "map" (default: "single")
      - `:initial_tasks` - For map steps, number of tasks (default: nil = determined at runtime)
      - `:max_attempts` - Override workflow default retry count
      - `:timeout` - Override workflow default timeout

  ## Returns

    - `{:ok, step_map}` - Step created successfully
    - `{:error, reason}` - Validation or database error

  ## Examples

      # Root step (no dependencies)
      {:ok, _} = FlowBuilder.add_step("my_workflow", "fetch", [], MyApp.Repo)

      # Dependent step
      {:ok, _} = FlowBuilder.add_step("my_workflow", "process", ["fetch"], MyApp.Repo)

      # Map step with 50 parallel tasks
      {:ok, _} = FlowBuilder.add_step("my_workflow", "process_batch", ["fetch"], MyApp.Repo,
        step_type: "map",
        initial_tasks: 50,
        max_attempts: 5
      )

      # Multiple dependencies
      {:ok, _} = FlowBuilder.add_step("my_workflow", "merge", ["process_a", "process_b"], MyApp.Repo)
  """
  @spec add_step(String.t(), String.t(), [String.t()], module(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def add_step(workflow_slug, step_slug, depends_on, repo, opts \\ []) do
    step_type = Keyword.get(opts, :step_type, "single")
    initial_tasks = Keyword.get(opts, :initial_tasks)
    max_attempts = Keyword.get(opts, :max_attempts)
    timeout = Keyword.get(opts, :timeout)

    case repo.query(
           """
           SELECT * FROM pgflow.add_step(
             $1::text, $2::text, $3::text[], $4::text,
             $5::integer, $6::integer, $7::integer
           )
           """,
           [workflow_slug, step_slug, depends_on, step_type, initial_tasks, max_attempts, timeout]
         ) do
      {:ok, %{columns: columns, rows: [row]}} ->
        step = Enum.zip(columns, row) |> Map.new()
        {:ok, step}

      {:ok, %{rows: []}} ->
        {:error, :step_creation_failed}

      {:error, %Postgrex.Error{} = error} ->
        {:error, parse_postgres_error(error)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all dynamic workflows.

  ## Returns

    - `{:ok, [workflow_maps]}` - List of all workflows

  ## Examples

      {:ok, workflows} = FlowBuilder.list_flows(MyApp.Repo)
      Enum.each(workflows, fn w -> IO.inspect(w["workflow_slug"]) end)
  """
  @spec list_flows(module()) :: {:ok, [map()]} | {:error, term()}
  def list_flows(repo) do
    case repo.query("SELECT * FROM workflows ORDER BY created_at DESC") do
      {:ok, %{columns: columns, rows: rows}} ->
        workflows = Enum.map(rows, fn row -> Enum.zip(columns, row) |> Map.new() end)
        {:ok, workflows}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a workflow with all its steps and dependencies.

  ## Returns

    - `{:ok, workflow_with_steps}` - Workflow definition with nested steps
    - `{:error, :not_found}` - Workflow doesn't exist

  ## Examples

      {:ok, workflow} = FlowBuilder.get_flow("my_workflow", MyApp.Repo)
      # => %{
      #   "workflow_slug" => "my_workflow",
      #   "steps" => [
      #     %{"step_slug" => "fetch", "depends_on" => []},
      #     %{"step_slug" => "process", "depends_on" => ["fetch"]}
      #   ]
      # }
  """
  @spec get_flow(String.t(), module()) :: {:ok, map()} | {:error, :not_found | term()}
  def get_flow(workflow_slug, repo) do
    workflow_query = """
    SELECT * FROM workflows WHERE workflow_slug = $1::text
    """

    steps_query = """
    SELECT
      ws.*,
      COALESCE(array_agg(dep.dep_slug) FILTER (WHERE dep.dep_slug IS NOT NULL), '{}') AS depends_on
    FROM workflow_steps ws
    LEFT JOIN workflow_step_dependencies_def dep
      ON dep.workflow_slug = ws.workflow_slug
      AND dep.step_slug = ws.step_slug
    WHERE ws.workflow_slug = $1::text
    GROUP BY ws.workflow_slug, ws.step_slug, ws.step_type, ws.step_index,
             ws.deps_count, ws.initial_tasks, ws.max_attempts, ws.timeout, ws.created_at
    ORDER BY ws.step_index
    """

    with {:ok, %{rows: [workflow_row], columns: workflow_columns}} <-
           repo.query(workflow_query, [workflow_slug]),
         {:ok, %{rows: step_rows, columns: step_columns}} <- repo.query(steps_query, [workflow_slug]) do
      workflow = Enum.zip(workflow_columns, workflow_row) |> Map.new()
      steps = Enum.map(step_rows, fn row -> Enum.zip(step_columns, row) |> Map.new() end)

      {:ok, Map.put(workflow, "steps", steps)}
    else
      {:ok, %{rows: []}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes a workflow and all its steps.

  ## Parameters

    - `workflow_slug` - Workflow to delete
    - `repo` - Ecto repo module

  ## Returns

    - `:ok` - Workflow deleted
    - `{:error, reason}` - Deletion failed

  ## Examples

      :ok = FlowBuilder.delete_flow("old_workflow", MyApp.Repo)
  """
  @spec delete_flow(String.t(), module()) :: :ok | {:error, term()}
  def delete_flow(workflow_slug, repo) do
    case repo.query("DELETE FROM workflows WHERE workflow_slug = $1::text", [workflow_slug]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helpers

  defp parse_postgres_error(%Postgrex.Error{postgres: %{message: message}}) do
    cond do
      String.contains?(message, "Invalid workflow_slug") -> :invalid_workflow_slug
      String.contains?(message, "Invalid step_slug") -> :invalid_step_slug
      String.contains?(message, "does not exist") -> :workflow_not_found
      String.contains?(message, "Map step") -> :map_step_constraint_violation
      true -> message
    end
  end

  defp parse_postgres_error(_error), do: :database_error
end
