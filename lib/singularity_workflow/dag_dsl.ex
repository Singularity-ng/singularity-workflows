defmodule Singularity.Workflow.DagDsl do
  @moduledoc """
  Compiles spine `graph_plan.v1` IR into FlowBuilder step specs.

  Ports the ACE compile-path *algorithm* (validated graph → ordered emit targets)
  without ACE `execution_tasks` / product queues. Live HTDAG SoR remains SW map
  fan-out (`initial_tasks` → `task_index` / `complete_task`).

  Contract home: `singularity-engine/engine/workflow/spine/fixtures/`.
  """

  alias Singularity.Workflow.FlowBuilder

  @schema "singularity.workflow.graph_plan.v1"

  @type step_spec :: %{
          slug: String.t(),
          depends_on: [String.t()],
          initial_tasks: pos_integer()
        }

  @type plan :: %{
          name: String.t(),
          steps: [step_spec()]
        }

  @doc """
  Compile a JSON `graph_plan.v1` document into topologically ordered step specs.

  Rejects `initial_tasks < 1` (would shrink map fan-out to zero) and unknown
  `depends_on` edges.
  """
  @spec compile_plan(String.t() | map()) :: {:ok, plan()} | {:error, String.t()}
  def compile_plan(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} -> compile_plan(map)
      {:error, err} -> {:error, "invalid json: #{Exception.message(err)}"}
    end
  end

  def compile_plan(%{} = map) do
    with :ok <- require_schema(map),
         {:ok, name} <- require_name(map),
         {:ok, nodes} <- require_nodes(map),
         {:ok, steps} <- parse_nodes(nodes),
         :ok <- validate_depends_on(steps),
         {:ok, ordered} <- topo_sort(steps) do
      {:ok, %{name: name, steps: ordered}}
    end
  end

  def compile_plan(_), do: {:error, "plan must be a JSON object"}

  @doc """
  Apply a compiled plan through FlowBuilder (`create_flow` + ordered `add_step`).

  Map fan-out: `initial_tasks > 1` → `step_type: "map"`. Never clears or shrinks
  `initial_tasks` below the plan value.
  """
  @spec apply_to_flow(plan(), module(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def apply_to_flow(%{name: name, steps: steps}, repo, opts \\ []) when is_list(steps) do
    workflow_slug = Keyword.get(opts, :workflow_slug, sanitize_slug(name))
    flow_opts = Keyword.take(opts, [:max_attempts, :timeout])

    with {:ok, _} <- FlowBuilder.create_flow(workflow_slug, repo, flow_opts),
         :ok <- add_steps(workflow_slug, steps, repo) do
      {:ok, workflow_slug}
    end
  end

  defp add_steps(workflow_slug, steps, repo) do
    Enum.reduce_while(steps, :ok, fn step, :ok ->
      step_opts = step_opts(step)

      case FlowBuilder.add_step(workflow_slug, step.slug, step.depends_on, repo, step_opts) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp step_opts(%{initial_tasks: n}) when is_integer(n) and n > 1 do
    [step_type: "map", initial_tasks: n]
  end

  defp step_opts(%{initial_tasks: n}) when is_integer(n) and n >= 1 do
    [initial_tasks: n]
  end

  defp sanitize_slug(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]+/, "_")
    |> String.replace(~r/^_+|_+$/, "")
    |> then(fn
      "" -> "dag_dsl_workflow"
      <<c::utf8, _::binary>> = s when c in ?a..?z or c == ?_ -> s
      s -> "w_" <> s
    end)
  end

  defp require_schema(%{"schema" => @schema}), do: :ok
  defp require_schema(%{"schema" => other}), do: {:error, "unsupported schema: #{inspect(other)}"}
  defp require_schema(_), do: {:error, "missing schema"}

  defp require_name(%{"name" => name}) when is_binary(name) and byte_size(name) > 0, do: {:ok, name}
  defp require_name(_), do: {:error, "missing or blank name"}

  defp require_nodes(%{"nodes" => nodes}) when is_list(nodes) and nodes != [], do: {:ok, nodes}
  defp require_nodes(_), do: {:error, "nodes must be a non-empty list"}

  defp parse_nodes(nodes) do
    Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, acc} ->
      case parse_node(node) do
        {:ok, step} -> {:cont, {:ok, [step | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, steps} -> {:ok, Enum.reverse(steps)}
      other -> other
    end
  end

  defp parse_node(%{"id" => id} = node) when is_binary(id) and byte_size(id) > 0 do
    depends_on = Map.get(node, "depends_on", [])
    initial_tasks = Map.get(node, "initial_tasks", 1)

    cond do
      not is_list(depends_on) or not Enum.all?(depends_on, &is_binary/1) ->
        {:error, "node #{id}: depends_on must be a list of strings"}

      not is_integer(initial_tasks) or initial_tasks < 1 ->
        {:error, "node #{id}: initial_tasks must be >= 1 (refuse shrinking map fan-out)"}

      true ->
        {:ok, %{slug: id, depends_on: depends_on, initial_tasks: initial_tasks}}
    end
  end

  defp parse_node(_), do: {:error, "each node requires a non-blank id"}

  defp validate_depends_on(steps) do
    ids = MapSet.new(Enum.map(steps, & &1.slug))

    Enum.reduce_while(steps, :ok, fn step, :ok ->
      case Enum.find(step.depends_on, &(not MapSet.member?(ids, &1))) do
        nil -> {:cont, :ok}
        missing -> {:halt, {:error, "node #{step.slug}: unknown depends_on #{missing}"}}
      end
    end)
  end

  defp topo_sort(steps) do
    by_slug = Map.new(steps, &{&1.slug, &1})

    indegree =
      Enum.reduce(steps, Map.new(steps, &{&1.slug, 0}), fn step, acc ->
        Enum.reduce(step.depends_on, acc, fn _dep, a ->
          Map.update!(a, step.slug, &(&1 + 1))
        end)
      end)

    queue =
      indegree
      |> Enum.filter(fn {_slug, d} -> d == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    do_topo(queue, indegree, by_slug, [])
  end

  defp do_topo([], indegree, _by_slug, ordered) do
    if map_size(indegree) == 0 do
      {:ok, Enum.reverse(ordered)}
    else
      {:error, "cycle detected in depends_on"}
    end
  end

  defp do_topo([slug | rest], indegree, by_slug, ordered) do
    step = Map.fetch!(by_slug, slug)
    indegree = Map.delete(indegree, slug)

    {indegree, newly_ready} =
      Enum.reduce(by_slug, {indegree, []}, fn {other_slug, other}, {ind, ready} ->
        if slug in other.depends_on and Map.has_key?(ind, other_slug) do
          new_d = Map.fetch!(ind, other_slug) - 1
          ind = Map.put(ind, other_slug, new_d)
          if new_d == 0, do: {ind, [other_slug | ready]}, else: {ind, ready}
        else
          {ind, ready}
        end
      end)

    do_topo(Enum.sort(rest ++ newly_ready), indegree, by_slug, [step | ordered])
  end
end
