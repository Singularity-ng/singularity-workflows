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
    # Validate inputs
    with :ok <- validate_workflow_slug(workflow_slug),
         :ok <- validate_max_attempts(opts),
         :ok <- validate_timeout(opts) do
      max_attempts = Keyword.get(opts, :max_attempts, 3)
      timeout = Keyword.get(opts, :timeout, 60)

      # Use Elixir implementation instead of PostgreSQL function to bypass PG17 parser bug
      Pgflow.FlowOperations.create_flow(workflow_slug, max_attempts, timeout)
    else
      {:error, _reason} = error -> error
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
    # Validate inputs
    with :ok <- validate_workflow_slug(workflow_slug),
         :ok <- validate_step_slug(step_slug),
         :ok <- validate_step_type(opts),
         :ok <- validate_initial_tasks(opts),
         :ok <- validate_max_attempts(opts),
         :ok <- validate_timeout(opts) do
      step_type = Keyword.get(opts, :step_type, "single")
      initial_tasks = Keyword.get(opts, :initial_tasks)
      max_attempts = Keyword.get(opts, :max_attempts)
      timeout = Keyword.get(opts, :timeout)

      # Use Elixir implementation instead of PostgreSQL function to bypass PG17 parser bug
      Pgflow.FlowOperations.add_step(
        workflow_slug,
        step_slug,
        depends_on,
        step_type,
        initial_tasks,
        max_attempts,
        timeout
      )
    else
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Lists all dynamic workflows.

  ## Returns

    - `{:ok, [workflow_maps]}` - List of all workflows

  ## Examples

      iex> {:ok, workflows} = FlowBuilder.list_flows(MyApp.Repo)
      iex> length(workflows)
      3
      iex> Enum.map(workflows, &(&1["workflow_slug"]))
      ["payment_flow", "user_onboarding", "data_pipeline"]

      # Filter workflows created today
      iex> {:ok, workflows} = FlowBuilder.list_flows(MyApp.Repo)
      iex> today = Date.utc_today()
      iex> recent = Enum.filter(workflows, fn w ->
      ...>   Date.compare(w["created_at"], today) == :eq
      ...> end)
      iex> length(recent)
      1
  """
  @spec list_flows(module()) :: {:ok, [map()]} | {:error, term()}
  def list_flows(repo) do
    case repo.query("SELECT * FROM workflows ORDER BY created_at DESC", []) do
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
         {:ok, %{rows: step_rows, columns: step_columns}} <-
           repo.query(steps_query, [workflow_slug]) do
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
    with {:ok, _} <-
           repo.query("DELETE FROM workflow_step_dependencies_def WHERE workflow_slug = $1::text", [
             workflow_slug
           ]),
         {:ok, _} <-
           repo.query("DELETE FROM workflow_steps WHERE workflow_slug = $1::text", [workflow_slug]),
         {:ok, _} <-
           repo.query("DELETE FROM workflows WHERE workflow_slug = $1::text", [workflow_slug]) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helpers

  # Input validation functions

  defp validate_workflow_slug(slug) when is_binary(slug) do
    slug_length = String.length(slug)

    cond do
      slug_length == 0 ->
        {:error, :workflow_slug_cannot_be_empty}

      slug_length > 128 ->
        {:error, :workflow_slug_too_long}

      not Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, slug) ->
        {:error, :workflow_slug_invalid_format}

      slug == "run" ->
        {:error, :workflow_slug_reserved}

      true ->
        :ok
    end
  end

  defp validate_workflow_slug(_), do: {:error, :workflow_slug_must_be_string}

  defp validate_step_slug(slug) when is_binary(slug) do
    slug_length = String.length(slug)

    cond do
      slug_length == 0 ->
        {:error, :step_slug_cannot_be_empty}

      slug_length > 128 ->
        {:error, :step_slug_too_long}

      not Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, slug) ->
        {:error, :step_slug_invalid_format}

      slug == "run" ->
        {:error, :step_slug_reserved}

      true ->
        :ok
    end
  end

  defp validate_step_slug(_), do: {:error, :step_slug_must_be_string}

  defp validate_step_type(opts) do
    case Keyword.get(opts, :step_type) do
      nil -> :ok
      "single" -> :ok
      "map" -> :ok
      _other -> {:error, :step_type_must_be_single_or_map}
    end
  end

  defp validate_initial_tasks(opts) do
    case Keyword.get(opts, :initial_tasks) do
      nil -> :ok
      n when is_integer(n) and n > 0 -> :ok
      n when is_integer(n) -> {:error, :initial_tasks_must_be_positive}
      _other -> {:error, :initial_tasks_must_be_integer}
    end
  end

  defp validate_max_attempts(opts) do
    case Keyword.get(opts, :max_attempts) do
      nil -> :ok
      n when is_integer(n) and n >= 0 -> :ok
      n when is_integer(n) -> {:error, :max_attempts_must_be_non_negative}
      _other -> {:error, :max_attempts_must_be_integer}
    end
  end

  defp validate_timeout(opts) do
    case Keyword.get(opts, :timeout) do
      nil -> :ok
      n when is_integer(n) and n > 0 -> :ok
      n when is_integer(n) -> {:error, :timeout_must_be_positive}
      _other -> {:error, :timeout_must_be_integer}
    end
  end
end
