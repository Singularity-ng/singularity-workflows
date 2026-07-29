defmodule Singularity.Workflow.DagDslTest do
  @moduledoc """
  RED→GREEN proof: spine graph_plan.v1 IR compiles to FlowBuilder step specs
  without shrinking map fan-out (initial_tasks preserved).
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.{DagDsl, FlowBuilder}

  @fixture_path Path.expand(
                   "../../../singularity-engine/engine/workflow/spine/fixtures/map_fanout.plan.json",
                   __DIR__
                 )

  describe "compile_plan/1 — graph_plan.v1 → FlowBuilder step specs" do
    test "preserves map fan-out initial_tasks and depends_on from spine fixture" do
      json = File.read!(@fixture_path)

      assert {:ok, plan} = DagDsl.compile_plan(json)
      assert plan.name == "c19_map_fanout_fixture"
      assert length(plan.steps) == 3

      process = Enum.find(plan.steps, &(&1.slug == "process"))
      assert process != nil
      assert process.depends_on == ["fetch"]
      assert process.initial_tasks == 3

      save = Enum.find(plan.steps, &(&1.slug == "save"))
      assert save.depends_on == ["process"]
      assert save.initial_tasks == 1

      # Topological order: fetch before process before save
      slugs = Enum.map(plan.steps, & &1.slug)
      assert Enum.find_index(slugs, &(&1 == "fetch")) < Enum.find_index(slugs, &(&1 == "process"))
      assert Enum.find_index(slugs, &(&1 == "process")) < Enum.find_index(slugs, &(&1 == "save"))
    end

    test "rejects missing map fan-out (initial_tasks < 1) and unknown depends_on" do
      bad = ~s({"schema":"singularity.workflow.graph_plan.v1","name":"bad","nodes":[{"id":"a","depends_on":["ghost"],"initial_tasks":0}]})
      assert {:error, reason} = DagDsl.compile_plan(bad)
      assert is_binary(reason) or is_atom(reason)
    end
  end

  describe "apply_to_flow/3 — FlowBuilder DB round-trip" do
    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Singularity.Workflow.Repo)
      Singularity.Workflow.TestClock.reset()
      {:ok, _} = Singularity.Workflow.TestWorkflowPrefix.cleanup_by_prefix("test_dag_dsl_", Singularity.Workflow.Repo)
      :ok
    end

    test "persists map initial_tasks from spine fixture without shrink" do
      json = File.read!(@fixture_path)
      assert {:ok, plan} = DagDsl.compile_plan(json)

      assert {:ok, slug} =
               DagDsl.apply_to_flow(plan, Singularity.Workflow.Repo,
                 workflow_slug: "test_dag_dsl_map_fanout"
               )

      assert {:ok, workflow} = FlowBuilder.get_flow(slug, Singularity.Workflow.Repo)
      process = Enum.find(workflow["steps"], &(&1["step_slug"] == "process"))
      assert process["step_type"] == "map"
      assert process["initial_tasks"] == 3
      assert Enum.sort(process["depends_on"]) == ["fetch"]
    end

    test "loader+initializer preserve map initial_tasks without shrink" do
      alias Singularity.Workflow.{Repo, StepState}
      alias Singularity.Workflow.DAG.{DynamicWorkflowLoader, RunInitializer}

      json = File.read!(@fixture_path)
      assert {:ok, plan} = DagDsl.compile_plan(json)

      assert {:ok, slug} =
               DagDsl.apply_to_flow(plan, Repo, workflow_slug: "test_dag_dsl_map_init")

      step_functions = %{
        fetch: fn _input -> {:ok, [1, 2, 3]} end,
        process: fn input -> {:ok, input} end,
        save: fn input -> {:ok, input} end
      }

      assert {:ok, definition} = DynamicWorkflowLoader.load(slug, step_functions, Repo)
      assert {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      process_state = Repo.get_by!(StepState, run_id: run_id, step_slug: "process")
      assert process_state.initial_tasks == 3
    end

    test "execute_dynamic fans out map process to task_index 0..2" do
      import Ecto.Query

      alias Singularity.Workflow.{Executor, Repo, StepTask}

      json = File.read!(@fixture_path)
      assert {:ok, plan} = DagDsl.compile_plan(json)

      assert {:ok, slug} =
               DagDsl.apply_to_flow(plan, Repo, workflow_slug: "test_dag_dsl_map_exec")

      # Parent of a map step must return a JSON array (complete_task contract).
      seen_save = start_supervised!({Agent, fn -> nil end}, id: :dag_dsl_save_seen)

      step_functions = %{
        fetch: fn _input -> {:ok, [1, 2, 3]} end,
        process: fn input -> {:ok, %{"item" => input}} end,
        save: fn input ->
          Agent.update(seen_save, fn _ -> input end)
          {:ok, Map.put(input, "saved", true)}
        end
      }

      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      assert {:ok, _result} =
               Executor.execute_dynamic(slug, %{}, step_functions, Repo,
                 timeout: 60_000,
                 poll_interval: 50
               )

      task_indexes =
        from(t in StepTask,
          where: t.workflow_slug == ^slug and t.step_slug == "process",
          select: t.task_index,
          order_by: [asc: t.task_index],
          distinct: true
        )
        |> Repo.all()

      assert Enum.sort(task_indexes) == [0, 1, 2]

      # Reduce/save must see the full ordered map aggregate (not one child).
      save_in = Agent.get(seen_save, & &1)
      process_out = save_in["process"] || save_in[:process]
      assert is_list(process_out)
      assert length(process_out) == 3

      items =
        Enum.map(process_out, fn
          %{"item" => v} -> v
          %{item: v} -> v
          other -> other
        end)

      assert items == [1, 2, 3]
    end
  end
end
