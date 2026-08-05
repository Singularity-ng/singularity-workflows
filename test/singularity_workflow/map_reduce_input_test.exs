defmodule Singularity.Workflow.MapReduceInputTest do
  @moduledoc """
  Falsifier: a step depending on a map must receive all map task outputs
  (ordered by task_index), not a single arbitrary completed task.
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.{Executor, FlowBuilder, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Singularity.Workflow.TestClock.reset()
    {:ok, _} = Singularity.Workflow.TestWorkflowPrefix.cleanup_by_prefix("test_map_red_", Repo)
    :ok
  end

  test "save after map receives ordered array of all process outputs" do
    slug = "test_map_red_agg"
    assert {:ok, _} = FlowBuilder.create_flow(slug, Repo)

    assert {:ok, _} =
             FlowBuilder.add_step(slug, "fetch", [], Repo, step_type: "single", initial_tasks: 1)

    assert {:ok, _} =
             FlowBuilder.add_step(slug, "process", ["fetch"], Repo,
               step_type: "map",
               initial_tasks: 3
             )

    assert {:ok, _} =
             FlowBuilder.add_step(slug, "save", ["process"], Repo,
               step_type: "single",
               initial_tasks: 1
             )

    agent = start_supervised!({Agent, fn -> nil end})

    step_functions = %{
      fetch: fn _input -> {:ok, [1, 2, 3]} end,
      process: fn input -> {:ok, %{"item" => input}} end,
      save: fn input ->
        Agent.update(agent, fn _ -> input end)
        {:ok, %{"saved" => true, "n" => length(List.wrap(input["process"] || input))}}
      end
    }

    assert {:ok, _result} =
             Executor.execute_dynamic(slug, %{}, step_functions, Repo,
               timeout: 30_000,
               poll_interval: 50
             )

    received = Agent.get(agent, & &1)
    process_outputs = received["process"]

    assert is_list(process_outputs)
    assert Enum.map(process_outputs, & &1["item"]) == [1, 2, 3]
  end
end
