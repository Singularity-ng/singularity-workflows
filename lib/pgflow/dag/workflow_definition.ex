defmodule Pgflow.DAG.WorkflowDefinition do
  @moduledoc """
  Parses and validates workflow step definitions with DAG support.

  Handles both legacy sequential syntax and new depends_on syntax:

  ## Sequential Syntax (Legacy, Backwards Compatible)

      def __workflow_steps__ do
        [
          {:step1, &__MODULE__.step1/1},
          {:step2, &__MODULE__.step2/1}
        ]
      end

  Automatically converts to: step2 depends_on step1

  ## DAG Syntax (New, Parallel Support)

      def __workflow_steps__ do
        [
          {:fetch_data, &__MODULE__.fetch_data/1, depends_on: []},
          {:analyze, &__MODULE__.analyze/1, depends_on: [:fetch_data]},
          {:summarize, &__MODULE__.summarize/1, depends_on: [:fetch_data]},
          {:save, &__MODULE__.save/1, depends_on: [:analyze, :summarize]}
        ]
      end

  ## Validation

  - Detects cycles in dependency graph
  - Validates all dependencies exist
  - Ensures root steps exist (steps with no dependencies)
  """

  defstruct [:steps, :dependencies, :root_steps, :slug, :step_metadata]

  @type step_metadata :: %{
          initial_tasks: integer(),
          timeout: integer() | nil,
          max_attempts: integer()
        }

  @type step_definition :: {atom(), function(), keyword()}
  @type t :: %__MODULE__{
          steps: %{atom() => function()},
          dependencies: %{atom() => [atom()]},
          root_steps: [atom()],
          slug: String.t(),
          step_metadata: %{atom() => step_metadata()}
        }

  @doc """
  Parses workflow step definitions into a validated DAG structure.
  """
  @spec parse(module()) :: {:ok, t()} | {:error, term()}
  def parse(workflow_module) do
    steps_list = workflow_module.__workflow_steps__()
    workflow_slug = to_string(workflow_module)

    with {:ok, parsed} <- parse_steps(steps_list),
         :ok <- validate_dependencies(parsed.steps, parsed.dependencies),
         :ok <- validate_no_cycles(parsed.dependencies),
         {:ok, root_steps} <- find_root_steps(parsed.dependencies) do
      {:ok,
       %__MODULE__{
         steps: parsed.steps,
         dependencies: parsed.dependencies,
         root_steps: root_steps,
         slug: workflow_slug,
         step_metadata: parsed.step_metadata
       }}
    end
  end

  @doc """
  Parse step definitions, handling both legacy and new syntax.

  Used internally by parse/1 and also by DynamicWorkflowLoader for
  database-stored workflows.
  """
  @spec parse_steps(list()) :: {:ok, map()} | {:error, term()}
  def parse_steps(steps_list) do
    {steps, dependencies, metadata, _prev_step} =
      Enum.reduce(steps_list, {%{}, %{}, %{}, nil}, fn step_def,
                                                       {steps_acc, deps_acc, meta_acc, prev_step} ->
        case step_def do
          # New syntax: {step_name, step_fn, depends_on: [deps], ...}
          {step_name, step_fn, opts} when is_atom(step_name) and is_function(step_fn) ->
            depends_on = Keyword.get(opts, :depends_on, [])
            initial_tasks = Keyword.get(opts, :initial_tasks, 1)
            timeout = Keyword.get(opts, :timeout)
            max_attempts = Keyword.get(opts, :max_attempts, 3)

            step_meta = %{
              initial_tasks: initial_tasks,
              timeout: timeout,
              max_attempts: max_attempts
            }

            {
              Map.put(steps_acc, step_name, step_fn),
              Map.put(deps_acc, step_name, depends_on),
              Map.put(meta_acc, step_name, step_meta),
              step_name
            }

          # Legacy syntax: {step_name, step_fn} - auto-add dependency on previous step
          {step_name, step_fn} when is_atom(step_name) and is_function(step_fn) ->
            depends_on = if prev_step, do: [prev_step], else: []

            step_meta = %{
              initial_tasks: 1,
              timeout: nil,
              max_attempts: 3
            }

            {
              Map.put(steps_acc, step_name, step_fn),
              Map.put(deps_acc, step_name, depends_on),
              Map.put(meta_acc, step_name, step_meta),
              step_name
            }

          invalid ->
            raise ArgumentError,
                  "Invalid step definition: #{inspect(invalid)}. Expected {step_name, step_fn} or {step_name, step_fn, depends_on: [...]}"
        end
      end)

    {:ok, %{steps: steps, dependencies: dependencies, step_metadata: metadata}}
  end

  # Validate that all dependencies reference existing steps
  @doc false
  def validate_dependencies(steps, dependencies) do
    all_step_names = Map.keys(steps)

    invalid_deps =
      Enum.flat_map(dependencies, fn {step_name, deps} ->
        Enum.reject(deps, &(&1 in all_step_names))
        |> Enum.map(&{step_name, &1})
      end)

    if invalid_deps == [] do
      :ok
    else
      {:error, {:invalid_dependencies, invalid_deps}}
    end
  end

  # Validate no cycles using depth-first search
  @doc false
  def validate_no_cycles(dependencies) do
    case find_cycle(dependencies) do
      nil -> :ok
      cycle -> {:error, {:cycle_detected, cycle}}
    end
  end

  @spec find_cycle(map()) :: list(atom()) | nil
  defp find_cycle(dependencies) do
    all_steps = Map.keys(dependencies)

    Enum.find_value(all_steps, fn start_step ->
      case dfs_cycle(start_step, dependencies, MapSet.new(), []) do
        {:cycle, path} -> Enum.reverse([start_step | path])
        :no_cycle -> nil
      end
    end)
  end

  @dialyzer {:nowarn_function, dfs_cycle: 4}
  @spec dfs_cycle(atom(), map(), MapSet.t(atom()), list(atom())) ::
          {:cycle, list(atom())} | :no_cycle
  defp dfs_cycle(step, dependencies, visited, path) do
    # Depth-first search for cycles using visited tracking
    #
    # Algorithm:
    # 1. If step already in visited set AND appears in current path → cycle found
    # 2. Mark step as visited, add to current path
    # 3. Recursively visit all dependencies
    # 4. If any dependency returns {:cycle, path}, propagate it up
    #
    # Performance: O(V + E) where V=steps, E=dependencies (DFS complexity)
    cond do
      MapSet.member?(visited, step) ->
        # Step already visited in this path → cycle detected!
        # Extract the cycle portion (from step to current position)
        cycle_start = Enum.find_index(path, &(&1 == step))
        {:cycle, Enum.drop(path, cycle_start || 0)}

      true ->
        # Mark as visited and add to current path
        new_visited = MapSet.put(visited, step)
        new_path = [step | path]

        # Get dependencies (empty list if step has no dependencies)
        deps = Map.get(dependencies, step, [])

        # Visit each dependency; if any returns a cycle, propagate it
        # All dependencies checked, no cycle found
        Enum.find_value(deps, :no_cycle, fn dep ->
          case dfs_cycle(dep, dependencies, new_visited, new_path) do
            # Cycle found, propagate
            {:cycle, _} = result -> result
            # No cycle in this branch
            :no_cycle -> nil
          end
        end) || :no_cycle
    end
  end

  # Find root steps (steps with no dependencies)
  @doc false
  def find_root_steps(dependencies) do
    root_steps =
      dependencies
      |> Enum.filter(fn {_step, deps} -> deps == [] end)
      |> Enum.map(fn {step, _} -> step end)

    if root_steps == [] do
      {:error, :no_root_steps}
    else
      {:ok, root_steps}
    end
  end

  @doc """
  Get all steps that depend on the given step (forward dependencies).
  """
  @spec get_dependents(t(), atom()) :: [atom()]
  def get_dependents(%__MODULE__{dependencies: dependencies}, step_name) do
    dependencies
    |> Enum.filter(fn {_step, deps} -> step_name in deps end)
    |> Enum.map(fn {step, _} -> step end)
  end

  @doc """
  Get all steps that the given step depends on (reverse dependencies).
  """
  @spec get_dependencies(t(), atom()) :: [atom()]
  def get_dependencies(%__MODULE__{dependencies: dependencies}, step_name) do
    Map.get(dependencies, step_name, [])
  end

  @doc """
  Get step function by name.
  """
  @spec get_step_function(t(), atom()) :: function() | nil
  def get_step_function(%__MODULE__{steps: steps}, step_name) do
    Map.get(steps, step_name)
  end

  @doc """
  Get count of dependencies for a step.
  """
  @spec dependency_count(t(), atom()) :: integer()
  def dependency_count(%__MODULE__{dependencies: dependencies}, step_name) do
    Map.get(dependencies, step_name, []) |> length()
  end

  @doc """
  Get metadata for a step (initial_tasks, timeout, max_attempts).
  """
  @spec get_step_metadata(t(), atom()) :: step_metadata()
  def get_step_metadata(%__MODULE__{step_metadata: metadata}, step_name) do
    Map.get(metadata, step_name, %{initial_tasks: 1, timeout: nil, max_attempts: 3})
  end
end
