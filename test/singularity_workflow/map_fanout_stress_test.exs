defmodule Singularity.Workflow.MapFanoutStressTest do
  @moduledoc """
  Falsifier: map fan-out at SpaceX scale (N=32) must slice each parent array
  element by task_index, complete every child, and aggregate all outputs for
  the reduce/save successor — without duplicate claims or dropped indexes.
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.{Executor, FlowBuilder, Repo, StepTask}
  import Ecto.Query

  @n 128

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Singularity.Workflow.TestClock.reset()
    {:ok, _} = Singularity.Workflow.TestWorkflowPrefix.cleanup_by_prefix("test_map_stress_", Repo)
    :ok
  end

  test "map fan-out N=#{@n} slices, completes, and aggregates every index" do
    slug = "test_map_stress_n#{@n}"
    items = Enum.to_list(1..@n)

    assert {:ok, _} = FlowBuilder.create_flow(slug, Repo)

    assert {:ok, _} =
             FlowBuilder.add_step(slug, "fetch", [], Repo, step_type: "single", initial_tasks: 1)

    assert {:ok, _} =
             FlowBuilder.add_step(slug, "process", ["fetch"], Repo,
               step_type: "map",
               initial_tasks: @n
             )

    assert {:ok, _} =
             FlowBuilder.add_step(slug, "save", ["process"], Repo,
               step_type: "single",
               initial_tasks: 1
             )

    seen = start_supervised!({Agent, fn -> MapSet.new() end}, id: :map_stress_seen)
    save_input = start_supervised!({Agent, fn -> nil end}, id: :map_stress_save)

    step_functions = %{
      fetch: fn _input -> {:ok, items} end,
      process: fn input ->
        Agent.update(seen, &MapSet.put(&1, input))
        {:ok, %{"item" => input}}
      end,
      save: fn input ->
        Agent.update(save_input, fn _ -> input end)
        {:ok, %{"saved" => true}}
      end
    }

    assert {:ok, _result} =
             Executor.execute_dynamic(slug, %{}, step_functions, Repo,
               timeout: 120_000,
               poll_interval: 25
             )

    assert Agent.get(seen, & &1) == MapSet.new(items)

    indexes =
      from(t in StepTask,
        where: t.workflow_slug == ^slug and t.step_slug == "process",
        select: {t.task_index, t.status},
        order_by: [asc: t.task_index]
      )
      |> Repo.all()

    assert length(indexes) == @n
    assert Enum.map(indexes, &elem(&1, 0)) == Enum.to_list(0..(@n - 1))
    assert Enum.all?(indexes, fn {_i, status} -> status == "completed" end)

    # Reduce/save must see the full ordered map aggregate, not one child.
    save = Agent.get(save_input, & &1)
    process_out = save["process"] || save[:process]
    assert is_list(process_out)
    assert length(process_out) == @n

    asserted =
      process_out
      |> Enum.map(fn
        %{"item" => v} -> v
        %{item: v} -> v
        other -> other
      end)

    assert asserted == items
  end
end
