defmodule Singularity.Workflow.MapTaskInputTest do
  @moduledoc """
  Falsifier: map step start_tasks input must be the parent array element at
  task_index (not the whole nested dep payload for every fan-out worker).
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.{Executor, FlowBuilder, Repo, StepTask}
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Singularity.Workflow.TestClock.reset()
    {:ok, _} = Singularity.Workflow.TestWorkflowPrefix.cleanup_by_prefix("test_map_in_", Repo)
    :ok
  end

  test "map process task_index i receives parent array element i" do
    slug = "test_map_in_slice"
    assert {:ok, _} = FlowBuilder.create_flow(slug, Repo)

    assert {:ok, _} =
             FlowBuilder.add_step(slug, "fetch", [], Repo, step_type: "single", initial_tasks: 1)

    assert {:ok, _} =
             FlowBuilder.add_step(slug, "process", ["fetch"], Repo,
               step_type: "map",
               initial_tasks: 3
             )

    agent = start_supervised!({Agent, fn -> [] end})

    step_functions = %{
      fetch: fn _input -> {:ok, [10, 20, 30]} end,
      process: fn input ->
        Agent.update(agent, &[input | &1])
        {:ok, %{"item" => input}}
      end
    }

    assert {:ok, _result} =
             Executor.execute_dynamic(slug, %{}, step_functions, Repo,
               timeout: 30_000,
               poll_interval: 50
             )

    received = Agent.get(agent, & &1) |> Enum.sort()
    assert received == [10, 20, 30]

    indexes =
      from(t in StepTask,
        where: t.workflow_slug == ^slug and t.step_slug == "process",
        select: t.task_index,
        order_by: [asc: t.task_index]
      )
      |> Repo.all()

    assert indexes == [0, 1, 2]
  end
end
