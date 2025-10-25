defmodule Pgflow.StepDependencyIntegrationTest do
  use ExUnit.Case, async: false

  alias Pgflow.{StepDependency, Executor, Repo}

  @moduledoc """
  Integration tests for StepDependency query functions:
  - find_dependents/3
  - find_dependencies/3

  Tests use real database with workflow execution to verify
  dependency tracking and resolution.
  """

  # Test workflow modules for dependency testing
  defmodule DiamondFlow do
    @moduledoc false
    def __workflow_steps__ do
      [
        {:root, &__MODULE__.root/1, depends_on: []},
        {:left, &__MODULE__.left/1, depends_on: [:root]},
        {:right, &__MODULE__.right/1, depends_on: [:root]},
        {:merge, &__MODULE__.merge/1, depends_on: [:left, :right]}
      ]
    end

    def root(_input), do: {:ok, %{root: true}}
    def left(input), do: {:ok, Map.put(input, :left, true)}
    def right(input), do: {:ok, Map.put(input, :right, true)}
    def merge(input), do: {:ok, Map.put(input, :merged, true)}
  end

  defmodule FanOutFlow do
    @moduledoc false
    def __workflow_steps__ do
      [
        {:source, &__MODULE__.source/1, depends_on: []},
        {:branch_a, &__MODULE__.branch/1, depends_on: [:source]},
        {:branch_b, &__MODULE__.branch/1, depends_on: [:source]},
        {:branch_c, &__MODULE__.branch/1, depends_on: [:source]}
      ]
    end

    def source(_input), do: {:ok, %{data: "source"}}
    def branch(input), do: {:ok, input}
  end

  defmodule LinearFlow do
    @moduledoc false
    def __workflow_steps__ do
      [
        {:step1, &__MODULE__.step/1, depends_on: []},
        {:step2, &__MODULE__.step/1, depends_on: [:step1]},
        {:step3, &__MODULE__.step/1, depends_on: [:step2]},
        {:step4, &__MODULE__.step/1, depends_on: [:step3]}
      ]
    end

    def step(input), do: {:ok, input}
  end

  setup do
    # Clean up any existing workflow runs
    Repo.delete_all(Pgflow.WorkflowRun)
    :ok
  end

  describe "find_dependents/3 - with repo module" do
    test "finds dependent steps in diamond pattern" do
      {:ok, _result} = Executor.execute(DiamondFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # Find steps that depend on :root
      dependents = StepDependency.find_dependents(run.id, "root", Repo)

      assert "left" in dependents
      assert "right" in dependents
      assert length(dependents) == 2
    end

    test "finds single dependent step" do
      {:ok, _result} = Executor.execute(DiamondFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # Find steps that depend on :left (should be :merge)
      dependents = StepDependency.find_dependents(run.id, "left", Repo)

      assert dependents == ["merge"]
    end

    test "returns empty list when no dependents" do
      {:ok, _result} = Executor.execute(DiamondFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # :merge has no dependents (it's the final step)
      dependents = StepDependency.find_dependents(run.id, "merge", Repo)

      assert dependents == []
    end

    test "finds multiple dependents in fan-out pattern" do
      {:ok, _result} = Executor.execute(FanOutFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # :source should have 3 dependents
      dependents = StepDependency.find_dependents(run.id, "source", Repo)

      assert length(dependents) == 3
      assert "branch_a" in dependents
      assert "branch_b" in dependents
      assert "branch_c" in dependents
    end

    test "returns empty list for root step with no dependents" do
      defmodule SingleStepFlow do
        @moduledoc false
        def __workflow_steps__ do
          [{:only, fn input -> {:ok, input} end, depends_on: []}]
        end
      end

      {:ok, _result} = Executor.execute(SingleStepFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      dependents = StepDependency.find_dependents(run.id, "only", Repo)

      assert dependents == []
    end

    test "isolates runs (same step names, different run_ids)" do
      # Execute same workflow twice
      {:ok, _result1} = Executor.execute(DiamondFlow, %{}, Repo)
      {:ok, _result2} = Executor.execute(DiamondFlow, %{}, Repo)

      runs = Repo.all(Pgflow.WorkflowRun)
      [run1, run2] = runs

      # Each run should have its own dependency graph
      dependents1 = StepDependency.find_dependents(run1.id, "root", Repo)
      dependents2 = StepDependency.find_dependents(run2.id, "root", Repo)

      assert length(dependents1) == 2
      assert length(dependents2) == 2
    end
  end

  describe "find_dependents/3 - with function" do
    test "works with custom query function" do
      {:ok, _result} = Executor.execute(DiamondFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # Use custom function instead of repo
      query_fn = fn query -> Repo.all(query) end

      dependents = StepDependency.find_dependents(run.id, "root", query_fn)

      assert "left" in dependents
      assert "right" in dependents
    end

    test "custom function can filter results" do
      {:ok, _result} = Executor.execute(FanOutFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # Custom function that limits results
      query_fn = fn query ->
        import Ecto.Query
        limited = limit(query, 2)
        Repo.all(limited)
      end

      dependents = StepDependency.find_dependents(run.id, "source", query_fn)

      # Should return only 2 results due to limit
      assert length(dependents) == 2
    end
  end

  describe "find_dependencies/3 - with repo module" do
    test "finds dependencies in diamond pattern" do
      {:ok, _result} = Executor.execute(DiamondFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # :merge depends on both :left and :right
      dependencies = StepDependency.find_dependencies(run.id, "merge", Repo)

      assert "left" in dependencies
      assert "right" in dependencies
      assert length(dependencies) == 2
    end

    test "finds single dependency" do
      {:ok, _result} = Executor.execute(DiamondFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # :left depends only on :root
      dependencies = StepDependency.find_dependencies(run.id, "left", Repo)

      assert dependencies == ["root"]
    end

    test "returns empty list for root step" do
      {:ok, _result} = Executor.execute(DiamondFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # :root has no dependencies
      dependencies = StepDependency.find_dependencies(run.id, "root", Repo)

      assert dependencies == []
    end

    test "finds dependencies in linear chain" do
      {:ok, _result} = Executor.execute(LinearFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # :step4 depends on :step3
      dependencies = StepDependency.find_dependencies(run.id, "step4", Repo)

      assert dependencies == ["step3"]

      # :step3 depends on :step2
      dependencies = StepDependency.find_dependencies(run.id, "step3", Repo)

      assert dependencies == ["step2"]

      # :step2 depends on :step1
      dependencies = StepDependency.find_dependencies(run.id, "step2", Repo)

      assert dependencies == ["step1"]

      # :step1 has no dependencies
      dependencies = StepDependency.find_dependencies(run.id, "step1", Repo)

      assert dependencies == []
    end

    test "isolates runs for find_dependencies" do
      {:ok, _result1} = Executor.execute(DiamondFlow, %{}, Repo)
      {:ok, _result2} = Executor.execute(DiamondFlow, %{}, Repo)

      runs = Repo.all(Pgflow.WorkflowRun)
      [run1, run2] = runs

      # Each run should have its own dependency graph
      deps1 = StepDependency.find_dependencies(run1.id, "merge", Repo)
      deps2 = StepDependency.find_dependencies(run2.id, "merge", Repo)

      assert length(deps1) == 2
      assert length(deps2) == 2
    end
  end

  describe "find_dependencies/3 - with function" do
    test "works with custom query function" do
      {:ok, _result} = Executor.execute(DiamondFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      query_fn = fn query -> Repo.all(query) end

      dependencies = StepDependency.find_dependencies(run.id, "merge", query_fn)

      assert "left" in dependencies
      assert "right" in dependencies
    end

    test "custom function can transform results" do
      {:ok, _result} = Executor.execute(DiamondFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # Custom function that sorts results
      query_fn = fn query ->
        query
        |> Repo.all()
        |> Enum.sort()
      end

      dependencies = StepDependency.find_dependencies(run.id, "merge", query_fn)

      # Results should be sorted
      assert dependencies == Enum.sort(dependencies)
    end
  end

  describe "Integration with workflow execution" do
    test "dependency tracking during workflow execution" do
      {:ok, _result} = Executor.execute(DiamondFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # Verify complete dependency graph
      import Ecto.Query

      all_deps =
        from(d in StepDependency,
          where: d.run_id == ^run.id,
          select: {d.step_slug, d.depends_on_step}
        )
        |> Repo.all()

      # Should have 4 dependency records:
      # left -> root, right -> root, merge -> left, merge -> right
      assert length(all_deps) == 4

      assert {"left", "root"} in all_deps
      assert {"right", "root"} in all_deps
      assert {"merge", "left"} in all_deps
      assert {"merge", "right"} in all_deps
    end

    test "bidirectional navigation of dependency graph" do
      {:ok, _result} = Executor.execute(DiamondFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # Navigate forward: root -> dependents
      forward = StepDependency.find_dependents(run.id, "root", Repo)
      assert length(forward) == 2

      # Navigate backward: merge -> dependencies
      backward = StepDependency.find_dependencies(run.id, "merge", Repo)
      assert length(backward) == 2
    end

    test "complex workflow dependency resolution" do
      defmodule ComplexFlow do
        @moduledoc false
        def __workflow_steps__ do
          [
            {:init, fn input -> {:ok, input} end, depends_on: []},
            {:fetch_a, fn input -> {:ok, input} end, depends_on: [:init]},
            {:fetch_b, fn input -> {:ok, input} end, depends_on: [:init]},
            {:process_a, fn input -> {:ok, input} end, depends_on: [:fetch_a]},
            {:process_b, fn input -> {:ok, input} end, depends_on: [:fetch_b]},
            {:validate, fn input -> {:ok, input} end, depends_on: [:process_a, :process_b]},
            {:save, fn input -> {:ok, input} end, depends_on: [:validate]}
          ]
        end
      end

      {:ok, _result} = Executor.execute(ComplexFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # Verify multiple dependency patterns
      init_dependents = StepDependency.find_dependents(run.id, "init", Repo)
      assert length(init_dependents) == 2

      validate_deps = StepDependency.find_dependencies(run.id, "validate", Repo)
      assert length(validate_deps) == 2

      save_deps = StepDependency.find_dependencies(run.id, "save", Repo)
      assert save_deps == ["validate"]
    end
  end

  describe "Edge cases" do
    test "handles non-existent run_id" do
      fake_run_id = Ecto.UUID.generate()

      dependents = StepDependency.find_dependents(fake_run_id, "any_step", Repo)
      dependencies = StepDependency.find_dependencies(fake_run_id, "any_step", Repo)

      assert dependents == []
      assert dependencies == []
    end

    test "handles non-existent step_slug" do
      {:ok, _result} = Executor.execute(DiamondFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      dependents = StepDependency.find_dependents(run.id, "nonexistent", Repo)
      dependencies = StepDependency.find_dependencies(run.id, "nonexistent", Repo)

      assert dependents == []
      assert dependencies == []
    end

    test "returns consistent results on repeated calls" do
      {:ok, _result} = Executor.execute(DiamondFlow, %{}, Repo)

      run = Repo.one!(Pgflow.WorkflowRun)

      # Call multiple times
      deps1 = StepDependency.find_dependencies(run.id, "merge", Repo)
      deps2 = StepDependency.find_dependencies(run.id, "merge", Repo)
      deps3 = StepDependency.find_dependencies(run.id, "merge", Repo)

      assert Enum.sort(deps1) == Enum.sort(deps2)
      assert Enum.sort(deps2) == Enum.sort(deps3)
    end
  end
end
