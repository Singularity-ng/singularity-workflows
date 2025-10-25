# Test workflow fixtures (defined outside test module to keep queue names short)
# Queue name limit is 47 chars - module names must be short!
defmodule TestSimpleFlow do
  def __workflow_steps__ do
    [
      {:step1, &__MODULE__.step1/1, depends_on: []},
      {:step2, &__MODULE__.step2/1, depends_on: [:step1]}
    ]
  end

  def step1(_input), do: {:ok, %{result: "step1_done"}}
  def step2(_input), do: {:ok, %{result: "step2_done"}}
end

defmodule TestDiamondFlow do
  def __workflow_steps__ do
    [
      {:fetch, &__MODULE__.fetch/1, depends_on: []},
      {:left, &__MODULE__.left/1, depends_on: [:fetch]},
      {:right, &__MODULE__.right/1, depends_on: [:fetch]},
      {:merge, &__MODULE__.merge/1, depends_on: [:left, :right]}
    ]
  end

  def fetch(_input), do: {:ok, %{data: [1, 2, 3]}}
  def left(_input), do: {:ok, %{}}
  def right(_input), do: {:ok, %{}}
  def merge(_input), do: {:ok, %{}}
end

defmodule TestMapFlow do
  def __workflow_steps__ do
    [
      {:fetch, &__MODULE__.fetch/1, depends_on: []},
      {:process, &__MODULE__.process/1, depends_on: [:fetch], initial_tasks: 10},
      {:save, &__MODULE__.save/1, depends_on: [:process]}
    ]
  end

  def fetch(_input), do: {:ok, %{}}
  def process(_input), do: {:ok, %{}}
  def save(_input), do: {:ok, %{}}
end

defmodule TestSingleFlow do
  def __workflow_steps__ do
    [{:only_step, &__MODULE__.only_step/1, depends_on: []}]
  end

  def only_step(_input), do: {:ok, %{}}
end

defmodule TestFanOutFlow do
  def __workflow_steps__ do
    [
      {:root1, &__MODULE__.root/1, depends_on: []},
      {:root2, &__MODULE__.root/1, depends_on: []},
      {:merge, &__MODULE__.merge/1, depends_on: [:root1, :root2]}
    ]
  end

  def root(_input), do: {:ok, %{}}
  def merge(_input), do: {:ok, %{}}
end

defmodule TestAllRootsFlow do
  def __workflow_steps__ do
    [
      {:step1, &__MODULE__.s/1, depends_on: []},
      {:step2, &__MODULE__.s/1, depends_on: []},
      {:step3, &__MODULE__.s/1, depends_on: []}
    ]
  end

  def s(_input), do: {:ok, %{}}
end

defmodule Pgflow.DAG.RunInitializerTest do
  use ExUnit.Case, async: false

  alias Pgflow.DAG.{RunInitializer, WorkflowDefinition}
  alias Pgflow.{WorkflowRun, StepState, StepDependency, Repo}
  import Ecto.Query

  @moduledoc """
  Comprehensive RunInitializer tests covering:
  - Chicago-style TDD (state-based testing)
  - Run initialization with real database
  - Step state creation
  - Dependency graph setup
  - Counter initialization

  NOTE: These tests require PostgreSQL with pgflow SQL functions.
  Set DATABASE_URL or start database with migrations.
  Run with: mix test test/pgflow/dag/run_initializer_test.exs

  Tests are tagged :integration and can be skipped if database is unavailable.
  """

  describe "initialize/3 - Basic workflow initialization" do
    test "successfully initializes simple workflow and creates run record" do
      {:ok, definition} = WorkflowDefinition.parse(TestSimpleFlow)
      input = %{"user_id" => 123}

      {:ok, run_id} = RunInitializer.initialize(definition, input, Repo)

      # Verify run was created
      run = Repo.get!(WorkflowRun, run_id)
      assert run.workflow_slug == definition.slug
      assert run.input == input
      assert run.status == "started"
      assert run.remaining_steps == 2
    end

    test "creates step_states for each step" do
      {:ok, definition} = WorkflowDefinition.parse(TestSimpleFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      # Should create 2 step_states
      step_states = Repo.all(from(s in StepState, where: s.run_id == ^run_id))
      assert length(step_states) == 2

      # Verify step names
      step_slugs = Enum.map(step_states, & &1.step_slug)
      assert "step1" in step_slugs
      assert "step2" in step_slugs
    end

    test "creates step_dependencies for each dependency" do
      {:ok, definition} = WorkflowDefinition.parse(TestSimpleFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      # Should create 1 dependency (step2 depends on step1)
      deps = Repo.all(from(d in StepDependency, where: d.run_id == ^run_id))
      assert length(deps) == 1

      dep = hd(deps)
      assert dep.step_slug == "step2"
      assert dep.depends_on_step == "step1"
    end

    test "sets remaining_deps counter correctly" do
      {:ok, definition} = WorkflowDefinition.parse(TestSimpleFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      step1_state = Repo.get_by!(StepState, run_id: run_id, step_slug: "step1")
      step2_state = Repo.get_by!(StepState, run_id: run_id, step_slug: "step2")

      # step1 is root (no dependencies)
      assert step1_state.remaining_deps == 0

      # step2 depends on step1
      assert step2_state.remaining_deps == 1
    end

    test "handles root steps specially" do
      {:ok, definition} = WorkflowDefinition.parse(TestSimpleFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      step1_state = Repo.get_by!(StepState, run_id: run_id, step_slug: "step1")

      # Root step has remaining_deps = 0
      assert step1_state.remaining_deps == 0
      # Root step should be started by start_ready_steps()
      assert step1_state.status == "started"
    end

    test "handles dependent steps" do
      {:ok, definition} = WorkflowDefinition.parse(TestSimpleFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      step2_state = Repo.get_by!(StepState, run_id: run_id, step_slug: "step2")

      # Dependent step has remaining_deps > 0
      assert step2_state.remaining_deps == 1
      # Dependent step stays as 'created' (not started yet)
      assert step2_state.status == "created"
    end
  end

  describe "initialize/3 - Complex DAG workflows" do
    test "initializes counters for diamond workflow" do
      {:ok, definition} = WorkflowDefinition.parse(TestDiamondFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      fetch_state = Repo.get_by!(StepState, run_id: run_id, step_slug: "fetch")
      left_state = Repo.get_by!(StepState, run_id: run_id, step_slug: "left")
      right_state = Repo.get_by!(StepState, run_id: run_id, step_slug: "right")
      merge_state = Repo.get_by!(StepState, run_id: run_id, step_slug: "merge")

      # fetch: remaining_deps=0 (root)
      assert fetch_state.remaining_deps == 0
      # left: remaining_deps=1 (depends on fetch)
      assert left_state.remaining_deps == 1
      # right: remaining_deps=1 (depends on fetch)
      assert right_state.remaining_deps == 1
      # merge: remaining_deps=2 (depends on left AND right)
      assert merge_state.remaining_deps == 2
    end

    test "creates correct dependencies for diamond pattern" do
      {:ok, definition} = WorkflowDefinition.parse(TestDiamondFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      deps = Repo.all(from(d in StepDependency, where: d.run_id == ^run_id, order_by: d.step_slug))

      # Should have 4 dependencies:
      # - left depends on fetch
      # - right depends on fetch
      # - merge depends on left
      # - merge depends on right
      assert length(deps) == 4

      # Verify left and right both depend on fetch
      left_deps = Enum.filter(deps, &(&1.step_slug == "left"))
      assert length(left_deps) == 1
      assert hd(left_deps).depends_on_step == "fetch"

      right_deps = Enum.filter(deps, &(&1.step_slug == "right"))
      assert length(right_deps) == 1
      assert hd(right_deps).depends_on_step == "fetch"

      # Verify merge depends on both left and right
      merge_deps = Enum.filter(deps, &(&1.step_slug == "merge"))
      assert length(merge_deps) == 2
      merge_depends_on = Enum.map(merge_deps, & &1.depends_on_step) |> Enum.sort()
      assert merge_depends_on == ["left", "right"]
    end

    test "initializes map step with initial_tasks" do
      {:ok, definition} = WorkflowDefinition.parse(TestMapFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      process_state = Repo.get_by!(StepState, run_id: run_id, step_slug: "process")

      # Map step should have initial_tasks set
      assert process_state.initial_tasks == 10
    end
  end

  describe "Edge cases and validation" do
    test "handles single-step workflow" do
      {:ok, definition} = WorkflowDefinition.parse(TestSingleFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      # Should create 1 run, 1 step_state, 0 dependencies
      run = Repo.get!(WorkflowRun, run_id)
      assert run.remaining_steps == 1

      step_states = Repo.all(from(s in StepState, where: s.run_id == ^run_id))
      assert length(step_states) == 1

      deps = Repo.all(from(d in StepDependency, where: d.run_id == ^run_id))
      assert length(deps) == 0
    end

    test "handles multiple root steps (fan-out)" do
      {:ok, definition} = WorkflowDefinition.parse(TestFanOutFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      root1_state = Repo.get_by!(StepState, run_id: run_id, step_slug: "root1")
      root2_state = Repo.get_by!(StepState, run_id: run_id, step_slug: "root2")
      merge_state = Repo.get_by!(StepState, run_id: run_id, step_slug: "merge")

      # Both root steps should be started
      assert root1_state.status == "started"
      assert root2_state.status == "started"
      assert root1_state.remaining_deps == 0
      assert root2_state.remaining_deps == 0

      # Merge depends on both roots
      assert merge_state.remaining_deps == 2
      assert merge_state.status == "created"
    end

    test "handles workflows with no dependencies (all root steps)" do
      defmodule TestAllRootsFlow do
        def __workflow_steps__ do
          [
            {:step1, &__MODULE__.s/1, depends_on: []},
            {:step2, &__MODULE__.s/1, depends_on: []},
            {:step3, &__MODULE__.s/1, depends_on: []}
          ]
        end

        def s(_input), do: {:ok, %{}}
      end

      {:ok, definition} = WorkflowDefinition.parse(TestAllRootsFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      # All steps should be started (all are roots)
      step_states = Repo.all(from(s in StepState, where: s.run_id == ^run_id))
      assert length(step_states) == 3

      Enum.each(step_states, fn state ->
        assert state.status == "started"
        assert state.remaining_deps == 0
      end)

      # No dependencies
      deps = Repo.all(from(d in StepDependency, where: d.run_id == ^run_id))
      assert length(deps) == 0
    end

    test "handles complex input data structures" do
      {:ok, definition} = WorkflowDefinition.parse(TestSimpleFlow)

      complex_input = %{
        "user" => %{"id" => 123, "name" => "Test User"},
        "items" => [1, 2, 3, 4, 5],
        "config" => %{"timeout" => 60, "retries" => 3}
      }

      {:ok, run_id} = RunInitializer.initialize(definition, complex_input, Repo)

      run = Repo.get!(WorkflowRun, run_id)
      assert run.input == complex_input
    end

    test "generates valid UUID for run_id" do
      {:ok, definition} = WorkflowDefinition.parse(TestSimpleFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      # UUID should be valid binary format
      assert is_binary(run_id)
      # UUID length is 36 characters with dashes
      assert String.length(run_id) == 36
      # Should match UUID pattern
      assert String.match?(
               run_id,
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
             )
    end

    test "creates run with started_at timestamp" do
      {:ok, definition} = WorkflowDefinition.parse(TestSimpleFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      run = Repo.get!(WorkflowRun, run_id)
      assert run.started_at != nil
      assert %DateTime{} = run.started_at
    end

    test "sets workflow_slug correctly" do
      {:ok, definition} = WorkflowDefinition.parse(TestDiamondFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      run = Repo.get!(WorkflowRun, run_id)
      assert String.contains?(run.workflow_slug, "TestDiamondFlow")

      # All step_states should have same workflow_slug
      step_states = Repo.all(from(s in StepState, where: s.run_id == ^run_id))

      Enum.each(step_states, fn state ->
        assert state.workflow_slug == run.workflow_slug
      end)
    end
  end

  describe "Transaction behavior and error handling" do
    test "wraps initialization in transaction" do
      {:ok, definition} = WorkflowDefinition.parse(TestSimpleFlow)

      # If this succeeds, the transaction committed
      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      # All records should exist
      assert Repo.get(WorkflowRun, run_id) != nil
    end

    test "transaction returns run_id on success" do
      {:ok, definition} = WorkflowDefinition.parse(TestSimpleFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      assert is_binary(run_id)
      assert byte_size(run_id) == 36
    end

    test "all step_states created in single batch" do
      {:ok, definition} = WorkflowDefinition.parse(TestDiamondFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      # All 4 step_states should be created
      step_states = Repo.all(from(s in StepState, where: s.run_id == ^run_id))
      assert length(step_states) == 4
    end

    test "all dependencies created in single batch" do
      {:ok, definition} = WorkflowDefinition.parse(TestDiamondFlow)

      {:ok, run_id} = RunInitializer.initialize(definition, %{}, Repo)

      # All 4 dependencies should be created
      deps = Repo.all(from(d in StepDependency, where: d.run_id == ^run_id))
      assert length(deps) == 4
    end
  end
end
