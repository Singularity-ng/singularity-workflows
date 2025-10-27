defmodule Pgflow.FlowOperations do
  @moduledoc """
  Direct Elixir implementations of workflow operations.

  Bypasses PostgreSQL 17 parser regression by implementing create_flow and add_step
  logic directly in Elixir instead of as stored functions.

  This is a pragmatic workaround for PostgreSQL 17's "ambiguous column reference" bug
  that incorrectly detects column ambiguity in stored functions even when fully qualified.
  """

  require Logger
  alias Pgflow.Repo

  @doc """
  Creates a workflow definition in the database.

  Equivalent to pgflow.create_flow() PostgreSQL function, but implemented in Elixir
  to bypass PostgreSQL 17 parser issues.

  Returns the created workflow as a map matching the expected format:
  %{
    "workflow_slug" => string,
    "max_attempts" => integer,
    "timeout" => integer,
    "created_at" => DateTime
  }
  """
  @spec create_flow(String.t(), integer(), integer()) :: {:ok, map()} | {:error, term()}
  def create_flow(workflow_slug, max_attempts \\ 3, timeout \\ 60) do
    # Check if workflow already exists - return error for duplicates
    case Repo.query("SELECT 1 FROM workflows WHERE workflow_slug = $1::text", [workflow_slug]) do
      {:ok, %{rows: [_|_]}} ->
        {:error, {:workflow_already_exists, workflow_slug}}

      {:error, reason} ->
        {:error, reason}

      {:ok, %{rows: []}} ->
        # Workflow doesn't exist, insert it
        case Repo.query(
          """
          INSERT INTO workflows (workflow_slug, max_attempts, timeout)
          VALUES ($1::text, $2::integer, $3::integer)
          RETURNING workflow_slug, max_attempts, timeout, created_at
          """,
          [workflow_slug, max_attempts, timeout]
        ) do
          {:ok, %{columns: columns, rows: [row]}} ->
            workflow = Enum.zip(columns, row) |> Map.new()
            Logger.debug("Created workflow: #{workflow_slug}")
            {:ok, workflow}

          {:ok, %{rows: []}} ->
            {:error, :workflow_creation_failed}

          {:error, %Postgrex.Error{postgres: %{constraint: "workflow_slug_is_valid"}} = error} ->
            Logger.error("Failed to create workflow - invalid slug: #{inspect(error)}")
            {:error, {:invalid_workflow_slug, workflow_slug}}

          {:error, reason} ->
            Logger.error("Failed to create workflow: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Adds a step to a workflow definition.

  Equivalent to pgflow.add_step() PostgreSQL function, but implemented in Elixir
  to bypass PostgreSQL 17 parser issues.

  Returns the created/updated step as a map matching the expected format:
  %{
    "workflow_slug" => string,
    "step_slug" => string,
    "step_type" => string,
    "step_index" => integer,
    "deps_count" => integer,
    "initial_tasks" => integer,
    "max_attempts" => integer,
    "timeout" => integer,
    "created_at" => DateTime
  }
  """
  @spec add_step(
    String.t(),
    String.t(),
    [String.t()],
    String.t(),
    integer() | nil,
    integer() | nil,
    integer() | nil
  ) :: {:ok, map()} | {:error, term()}
  def add_step(
    workflow_slug,
    step_slug,
    depends_on \\ [],
    step_type \\ "single",
    initial_tasks \\ nil,
    max_attempts \\ nil,
    timeout \\ nil
  ) do
    with :ok <- validate_step_inputs(workflow_slug, step_slug, step_type, depends_on),
         :ok <- validate_workflow_exists(workflow_slug),
         {:ok, next_index} <- get_next_step_index(workflow_slug),
         {:ok, _} <- insert_step(workflow_slug, step_slug, step_type, next_index, initial_tasks, max_attempts, timeout),
         {:ok, _} <- insert_dependencies(workflow_slug, step_slug, depends_on),
         {:ok, step} <- fetch_step(workflow_slug, step_slug) do
      Logger.debug("Added step: #{workflow_slug}.#{step_slug}")
      {:ok, step}
    else
      {:error, reason} ->
        Logger.error("Failed to add step: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private helper functions

  defp validate_step_inputs(workflow_slug, step_slug, step_type, depends_on) do
    cond do
      not is_valid_slug(workflow_slug) ->
        {:error, {:invalid_workflow_slug, workflow_slug}}

      not is_valid_slug(step_slug) ->
        {:error, {:invalid_step_slug, step_slug}}

      step_type not in ["single", "map"] ->
        {:error, {:invalid_step_type, step_type}}

      step_type == "map" and length(depends_on) > 1 ->
        {:error, {:map_step_constraint_violation, "Map steps can have at most 1 dependency"}}

      true ->
        :ok
    end
  end

  defp is_valid_slug(slug) when is_binary(slug) do
    slug_length = String.length(slug)

    cond do
      slug_length == 0 -> false
      slug_length > 128 -> false
      not Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, slug) -> false
      slug in ["run"] -> false  # Reserved word
      true -> true
    end
  end

  defp is_valid_slug(_), do: false

  defp validate_workflow_exists(workflow_slug) do
    case Repo.query("SELECT 1 FROM workflows WHERE workflow_slug = $1::text", [workflow_slug]) do
      {:ok, %{rows: [_|_]}} -> :ok
      {:ok, %{rows: []}} -> {:error, {:workflow_not_found, workflow_slug}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_next_step_index(workflow_slug) do
    case Repo.query(
      "SELECT COALESCE(MAX(step_index) + 1, 0) as next_index FROM workflow_steps WHERE workflow_slug = $1::text",
      [workflow_slug]
    ) do
      {:ok, %{columns: ["next_index"], rows: [[next_index]]}} ->
        {:ok, next_index}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp insert_step(workflow_slug, step_slug, step_type, step_index, initial_tasks, max_attempts, timeout) do
    deps_count = 0  # Will be updated when dependencies are inserted

    Repo.query(
      """
      DELETE FROM workflow_steps
      WHERE workflow_slug = $1::text AND step_slug = $2::text
      """,
      [workflow_slug, step_slug]
    )

    case Repo.query(
      """
      INSERT INTO workflow_steps (workflow_slug, step_slug, step_type, step_index, deps_count, initial_tasks, max_attempts, timeout)
      VALUES ($1::text, $2::text, $3::text, $4::integer, $5::integer, $6::integer, $7::integer, $8::integer)
      """,
      [workflow_slug, step_slug, step_type, step_index, deps_count, initial_tasks, max_attempts, timeout]
    ) do
      {:ok, _} -> {:ok, :inserted}
      {:error, %Postgrex.Error{postgres: %{constraint: constraint}} = error} ->
        Logger.error("Failed to insert step - constraint #{constraint}: #{inspect(error)}")
        {:error, {:constraint_violation, constraint}}
      {:error, reason} ->
        Logger.error("Failed to insert step: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp insert_dependencies(_workflow_slug, _step_slug, []) do
    {:ok, :no_dependencies}
  end

  defp insert_dependencies(workflow_slug, step_slug, depends_on) do
    # Validate all dependencies exist
    case validate_dependencies_exist(workflow_slug, depends_on) do
      :ok ->
        # Insert dependencies, ignoring duplicates
        depends_on
        |> Enum.each(fn dep_slug ->
          Repo.query(
            """
            INSERT INTO workflow_step_dependencies_def (workflow_slug, dep_slug, step_slug)
            VALUES ($1::text, $2::text, $3::text)
            ON CONFLICT DO NOTHING
            """,
            [workflow_slug, dep_slug, step_slug]
          )
        end)

        # Update deps_count on the step
        Repo.query(
          """
          UPDATE workflow_steps
          SET deps_count = $1::integer
          WHERE workflow_slug = $2::text AND step_slug = $3::text
          """,
          [length(depends_on), workflow_slug, step_slug]
        )

      error ->
        error
    end
  end

  defp validate_dependencies_exist(workflow_slug, depends_on) do
    missing =
      Enum.filter(depends_on, fn dep_slug ->
        case Repo.query(
          "SELECT 1 FROM workflow_steps WHERE workflow_slug = $1::text AND step_slug = $2::text",
          [workflow_slug, dep_slug]
        ) do
          {:ok, %{rows: []}} -> true
          {:ok, %{rows: [_|_]}} -> false
          {:error, _} -> true
        end
      end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_dependencies, missing}}
    end
  end

  defp fetch_step(workflow_slug, step_slug) do
    case Repo.query(
      """
      SELECT
        ws.workflow_slug,
        ws.step_slug,
        ws.step_type,
        ws.step_index,
        ws.deps_count,
        ws.initial_tasks,
        ws.max_attempts,
        ws.timeout,
        ws.created_at
      FROM workflow_steps ws
      WHERE ws.workflow_slug = $1::text AND ws.step_slug = $2::text
      """,
      [workflow_slug, step_slug]
    ) do
      {:ok, %{columns: columns, rows: [row]}} ->
        step = Enum.zip(columns, row) |> Map.new()
        {:ok, step}

      {:ok, %{rows: []}} ->
        {:error, :step_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
