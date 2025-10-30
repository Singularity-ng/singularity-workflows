defmodule QuantumFlow.DAG.WorkflowDefinitionTest do
  use ExUnit.Case, async: true

  alias QuantumFlow.DAG.WorkflowDefinition

  @moduledoc """
  Comprehensive WorkflowDefinition tests covering:
  - Chicago-style TDD (state-based testing)
  - Sequential vs DAG syntax parsing
  - Dependency validation
  - Cycle detection
  - Root step identification
  - Error handling
  """

  # Test workflows for sequential execution
  defmodule SequentialWorkflow do
    def __workflow_steps__ do
      [
        {:step1, &__MODULE__.step1/1},
        {:step2, &__MODULE__.step2/1},
        {:step3, &__MODULE__.step3/1}
      ]
    end

    def step1(_input), do: {:ok, %{}}
    def step2(_input), do: {:ok, %{}}
    def step3(_input), do: {:ok, %{}}
  end

  # Test workflows for DAG execution
  defmodule ParallelDAGWorkflow do
    def __workflow_steps__ do
      [
        {:fetch, &__MODULE__.fetch/1, depends_on: []},
        {:analyze, &__MODULE__.analyze/1, depends_on: [:fetch]},
        {:summarize, &__MODULE__.summarize/1, depends_on: [:fetch]},
        {:save, &__MODULE__.save/1, depends_on: [:analyze, :summarize]}
      ]
    end

    def fetch(_input), do: {:ok, %{}}
    def analyze(_input), do: {:ok, %{}}
    def summarize(_input), do: {:ok, %{}}
    def save(_input), do: {:ok, %{}}
  end

  # Test workflows for cycle detection
  defmodule CyclicWorkflow do
    def __workflow_steps__ do
      [
        {:step1, &__MODULE__.step1/1, depends_on: [:step2]},
        {:step2, &__MODULE__.step2/1, depends_on: [:step1]}
      ]
    end

    def step1(_input), do: {:ok, %{}}
    def step2(_input), do: {:ok, %{}}
  end

  # Self-referential cycle
  defmodule SelfCycleWorkflow do
    def __workflow_steps__ do
      [
        {:recursive, &__MODULE__.recursive/1, depends_on: [:recursive]}
      ]
    end

    def recursive(_input), do: {:ok, %{}}
  end

  # Missing dependency reference
  defmodule MissingDependencyWorkflow do
    def __workflow_steps__ do
      [
        {:step1, &__MODULE__.step1/1, depends_on: [:non_existent]}
      ]
    end

    def step1(_input), do: {:ok, %{}}
  end

  # No steps workflow
  defmodule EmptyWorkflow do
    def __workflow_steps__, do: []
  end

  describe "parse/1 - Sequential Workflow" do
    test "parses sequential workflow correctly" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      # Should have 3 steps
      assert map_size(definition.steps) == 3
      assert Map.has_key?(definition.steps, :step1)
      assert Map.has_key?(definition.steps, :step2)
      assert Map.has_key?(definition.steps, :step3)
    end

    test "identifies root steps in sequential workflow" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      # Only step1 is root (no dependencies)
      assert definition.root_steps == [:step1]
    end

    test "creates dependencies for sequential steps" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      # step2 depends on step1
      assert definition.dependencies[:step2] == [:step1]
      # step3 depends on step2
      assert definition.dependencies[:step3] == [:step2]
    end

    test "sequential workflow slug is snake_case module name" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      # Should end with sequential_workflow (may have full module path prefix)
      assert String.ends_with?(definition.slug, "sequential_workflow")
    end
  end

  describe "parse/1 - DAG Workflow" do
    test "parses DAG workflow correctly" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      # Should have 4 steps
      assert map_size(definition.steps) == 4
    end

    test "identifies root step in DAG" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      # Only fetch is root
      assert definition.root_steps == [:fetch]
    end

    test "preserves parallel dependencies" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      # Both analyze and summarize depend on fetch
      assert definition.dependencies[:analyze] == [:fetch]
      assert definition.dependencies[:summarize] == [:fetch]
    end

    test "handles multiple dependencies" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      # Focused assertions for critical properties
      deps = definition.dependencies[:save]
      assert :analyze in deps
      assert :summarize in deps
      assert length(deps) == 2

      # Snapshot for complete DAG structure regression detection
      snapshot_data = %{
        steps: Map.keys(definition.steps),
        root_steps: definition.root_steps,
        dependencies: definition.dependencies
      }

      QuantumFlow.Test.Snapshot.assert_snapshot(snapshot_data, "workflow_definition_parallel_dag")
    end
  end

  describe "Cycle Detection" do
    test "detects direct cycles" do
      result = WorkflowDefinition.parse(CyclicWorkflow)

      assert match?({:error, {:cycle_detected, _}}, result)
    end

    test "detects self-referential cycles" do
      result = WorkflowDefinition.parse(SelfCycleWorkflow)

      assert match?({:error, {:cycle_detected, _}}, result)
    end

    test "detects indirect cycles (A→B→C→A)" do
      defmodule IndirectCycleWorkflow do
        def __workflow_steps__ do
          [
            {:a, &__MODULE__.a/1, depends_on: [:c]},
            {:b, &__MODULE__.b/1, depends_on: [:a]},
            {:c, &__MODULE__.c/1, depends_on: [:b]}
          ]
        end

        def a(_input), do: {:ok, %{}}
        def b(_input), do: {:ok, %{}}
        def c(_input), do: {:ok, %{}}
      end

      result = WorkflowDefinition.parse(IndirectCycleWorkflow)

      assert match?({:error, {:cycle_detected, _}}, result)
    end
  end

  describe "Dependency Validation" do
    test "rejects missing dependencies" do
      result = WorkflowDefinition.parse(MissingDependencyWorkflow)

      assert match?({:error, {:invalid_dependencies, _}}, result) or
               match?({:error, :dependency_not_found}, result)
    end

    test "validates all dependencies reference existing steps" do
      defmodule InvalidDepsWorkflow do
        def __workflow_steps__ do
          [
            {:step1, &__MODULE__.step1/1, depends_on: []},
            {:step2, &__MODULE__.step2/1, depends_on: [:step1, :missing]}
          ]
        end

        def step1(_input), do: {:ok, %{}}
        def step2(_input), do: {:ok, %{}}
      end

      result = WorkflowDefinition.parse(InvalidDepsWorkflow)

      # Should error because :missing step doesn't exist
      assert {:error, _} = result
    end

    test "accepts empty dependency list for root steps" do
      defmodule RootStepWorkflow do
        def __workflow_steps__ do
          [
            {:root, &__MODULE__.root/1, depends_on: []}
          ]
        end

        def root(_input), do: {:ok, %{}}
      end

      {:ok, definition} = WorkflowDefinition.parse(RootStepWorkflow)

      assert definition.root_steps == [:root]
    end
  end

  describe "Root Step Identification" do
    test "single root step workflow" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      assert length(definition.root_steps) == 1
      assert :step1 in definition.root_steps
    end

    test "multiple root steps in fan-out workflow" do
      defmodule FanOutWorkflow do
        def __workflow_steps__ do
          [
            {:root1, &__MODULE__.root1/1, depends_on: []},
            {:root2, &__MODULE__.root2/1, depends_on: []},
            {:merge, &__MODULE__.merge/1, depends_on: [:root1, :root2]}
          ]
        end

        def root1(_input), do: {:ok, %{}}
        def root2(_input), do: {:ok, %{}}
        def merge(_input), do: {:ok, %{}}
      end

      {:ok, definition} = WorkflowDefinition.parse(FanOutWorkflow)

      assert length(definition.root_steps) == 2
      assert :root1 in definition.root_steps
      assert :root2 in definition.root_steps
    end

    test "rejects workflows with no root steps" do
      defmodule NoRootWorkflow do
        def __workflow_steps__ do
          [
            {:step1, &__MODULE__.step1/1, depends_on: [:step2]},
            {:step2, &__MODULE__.step2/1, depends_on: [:step1]}
          ]
        end

        def step1(_input), do: {:ok, %{}}
        def step2(_input), do: {:ok, %{}}
      end

      result = WorkflowDefinition.parse(NoRootWorkflow)

      # Should error because all steps have dependencies (cycle)
      assert {:error, _} = result
    end
  end

  describe "Empty and Edge Cases" do
    test "rejects empty workflow" do
      result = WorkflowDefinition.parse(EmptyWorkflow)

      assert match?({:error, :no_root_steps}, result) or
               match?({:error, :no_steps}, result) or
               match?({:error, :empty_workflow}, result)
    end

    test "single step workflow" do
      defmodule SingleStepWorkflow do
        def __workflow_steps__ do
          [{:only_step, &__MODULE__.only_step/1, depends_on: []}]
        end

        def only_step(_input), do: {:ok, %{}}
      end

      {:ok, definition} = WorkflowDefinition.parse(SingleStepWorkflow)

      assert map_size(definition.steps) == 1
      assert definition.root_steps == [:only_step]
    end

    test "duplicate step slugs are rejected or handled" do
      defmodule DuplicateStepsWorkflow do
        def __workflow_steps__ do
          [
            {:step, &__MODULE__.step/1, depends_on: []},
            {:step, &__MODULE__.step/1, depends_on: [:step]}
          ]
        end

        def step(_input), do: {:ok, %{}}
      end

      result = WorkflowDefinition.parse(DuplicateStepsWorkflow)

      # Should error because steps must be unique
      assert {:error, _} = result
    end
  end

  describe "Complex Workflow Patterns" do
    test "diamond dependency pattern" do
      defmodule DiamondWorkflow do
        def __workflow_steps__ do
          [
            {:fetch, &__MODULE__.fetch/1, depends_on: []},
            {:left, &__MODULE__.left/1, depends_on: [:fetch]},
            {:right, &__MODULE__.right/1, depends_on: [:fetch]},
            {:merge, &__MODULE__.merge/1, depends_on: [:left, :right]}
          ]
        end

        def fetch(_input), do: {:ok, %{}}
        def left(_input), do: {:ok, %{}}
        def right(_input), do: {:ok, %{}}
        def merge(_input), do: {:ok, %{}}
      end

      {:ok, definition} = WorkflowDefinition.parse(DiamondWorkflow)

      assert definition.root_steps == [:fetch]

      assert definition.dependencies[:merge] == [:left, :right] or
               definition.dependencies[:merge] == [:right, :left]
    end

    test "long linear chain" do
      defmodule LongChainWorkflow do
        def __workflow_steps__ do
          [
            {:s1, &__MODULE__.s/1, depends_on: []},
            {:s2, &__MODULE__.s/1, depends_on: [:s1]},
            {:s3, &__MODULE__.s/1, depends_on: [:s2]},
            {:s4, &__MODULE__.s/1, depends_on: [:s3]},
            {:s5, &__MODULE__.s/1, depends_on: [:s4]}
          ]
        end

        def s(_input), do: {:ok, %{}}
      end

      {:ok, definition} = WorkflowDefinition.parse(LongChainWorkflow)

      assert definition.root_steps == [:s1]
      # Verify chain: s5 depends on s4 which depends on s3...
      assert definition.dependencies[:s5] == [:s4]
      assert definition.dependencies[:s4] == [:s3]
      assert definition.dependencies[:s3] == [:s2]
      assert definition.dependencies[:s2] == [:s1]
    end

    test "complex fan-out fan-in pattern" do
      defmodule ComplexFanWorkflow do
        def __workflow_steps__ do
          [
            {:start, &__MODULE__.start/1, depends_on: []},
            {:w1, &__MODULE__.w/1, depends_on: [:start]},
            {:w2, &__MODULE__.w/1, depends_on: [:start]},
            {:w3, &__MODULE__.w/1, depends_on: [:start]},
            {:gather, &__MODULE__.gather/1, depends_on: [:w1, :w2, :w3]},
            {:finish, &__MODULE__.finish/1, depends_on: [:gather]}
          ]
        end

        def start(_input), do: {:ok, %{}}
        def w(_input), do: {:ok, %{}}
        def gather(_input), do: {:ok, %{}}
        def finish(_input), do: {:ok, %{}}
      end

      {:ok, definition} = WorkflowDefinition.parse(ComplexFanWorkflow)

      assert definition.root_steps == [:start]
      assert length(definition.dependencies[:gather]) == 3
    end
  end

  describe "Metadata extraction" do
    test "extracts step metadata from DAG definition" do
      defmodule MetadataWorkflow do
        def __workflow_steps__ do
          [
            {:step1, &__MODULE__.step1/1, depends_on: [], max_attempts: 5, timeout: 120}
          ]
        end

        def step1(_input), do: {:ok, %{}}
      end

      {:ok, definition} = WorkflowDefinition.parse(MetadataWorkflow)

      # Should preserve metadata if available
      assert definition.step_metadata != nil
    end
  end

  describe "Type and validation" do
    test "returns valid WorkflowDefinition struct" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      # Should be proper struct
      assert is_struct(definition, WorkflowDefinition)
      assert Map.has_key?(definition, :steps)
      assert Map.has_key?(definition, :dependencies)
      assert Map.has_key?(definition, :root_steps)
      assert Map.has_key?(definition, :slug)
    end

    test "steps field is a map of atoms to functions" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      assert is_map(definition.steps)

      Enum.each(definition.steps, fn {key, value} ->
        assert is_atom(key)
        assert is_function(value)
      end)
    end

    test "dependencies field is a map of atoms to lists" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      assert is_map(definition.dependencies)

      Enum.each(definition.dependencies, fn {key, value} ->
        assert is_atom(key)
        assert is_list(value)
        Enum.each(value, &assert(is_atom(&1)))
      end)
    end

    test "root_steps is a list of atoms" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      assert is_list(definition.root_steps)
      Enum.each(definition.root_steps, &assert(is_atom(&1)))
    end

    test "slug is a string" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      assert is_binary(definition.slug)
    end
  end

  describe "get_dependents/2 - Forward Dependencies" do
    test "returns steps that depend on given step" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      # Both analyze and summarize depend on fetch
      dependents = WorkflowDefinition.get_dependents(definition, :fetch)
      assert :analyze in dependents
      assert :summarize in dependents
      assert length(dependents) == 2
    end

    test "returns empty list for terminal steps" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      # Save is terminal (no steps depend on it)
      dependents = WorkflowDefinition.get_dependents(definition, :save)
      assert dependents == []
    end

    test "handles multiple levels of dependents" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      # Analyze has save as dependent
      dependents = WorkflowDefinition.get_dependents(definition, :analyze)
      assert :save in dependents
    end
  end

  describe "get_dependencies/2 - Reverse Dependencies" do
    test "returns steps that given step depends on" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      # Save depends on both analyze and summarize
      deps = WorkflowDefinition.get_dependencies(definition, :save)
      assert :analyze in deps
      assert :summarize in deps
      assert length(deps) == 2
    end

    test "returns empty list for root steps" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      # Fetch is root (no dependencies)
      deps = WorkflowDefinition.get_dependencies(definition, :fetch)
      assert deps == []
    end

    test "returns single dependency" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      # Analyze depends only on fetch
      deps = WorkflowDefinition.get_dependencies(definition, :analyze)
      assert deps == [:fetch]
    end
  end

  describe "get_step_function/2" do
    test "returns function for valid step" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      step_fn = WorkflowDefinition.get_step_function(definition, :step1)
      assert is_function(step_fn)
      assert is_function(step_fn, 1)
    end

    test "returns nil for non-existent step" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      step_fn = WorkflowDefinition.get_step_function(definition, :non_existent)
      assert step_fn == nil
    end

    test "returned function is callable" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      step_fn = WorkflowDefinition.get_step_function(definition, :step1)
      assert {:ok, %{}} = step_fn.(%{})
    end
  end

  describe "dependency_count/2" do
    test "counts dependencies correctly" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      # Save has 2 dependencies
      assert WorkflowDefinition.dependency_count(definition, :save) == 2
    end

    test "returns zero for root steps" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      # Fetch has no dependencies
      assert WorkflowDefinition.dependency_count(definition, :fetch) == 0
    end

    test "returns one for single dependency" do
      {:ok, definition} = WorkflowDefinition.parse(ParallelDAGWorkflow)

      # Analyze has 1 dependency
      assert WorkflowDefinition.dependency_count(definition, :analyze) == 1
    end

    test "returns zero for non-existent step" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      # Non-existent step has no dependencies
      assert WorkflowDefinition.dependency_count(definition, :non_existent) == 0
    end
  end

  describe "get_step_metadata/2" do
    test "returns metadata for step with explicit metadata" do
      defmodule MetadataTestWorkflow do
        def __workflow_steps__ do
          [
            {:step1, &__MODULE__.step1/1,
             depends_on: [], initial_tasks: 10, timeout: 300, max_attempts: 5}
          ]
        end

        def step1(_input), do: {:ok, %{}}
      end

      {:ok, definition} = WorkflowDefinition.parse(MetadataTestWorkflow)

      metadata = WorkflowDefinition.get_step_metadata(definition, :step1)
      assert metadata.initial_tasks == 10
      assert metadata.timeout == 300
      assert metadata.max_attempts == 5
    end

    test "returns defaults for step with no explicit metadata" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      metadata = WorkflowDefinition.get_step_metadata(definition, :step1)
      assert metadata.initial_tasks == 1
      assert metadata.timeout == nil
      assert metadata.max_attempts == 3
    end

    test "returns defaults for non-existent step" do
      {:ok, definition} = WorkflowDefinition.parse(SequentialWorkflow)

      metadata = WorkflowDefinition.get_step_metadata(definition, :non_existent)
      assert metadata.initial_tasks == 1
      assert metadata.timeout == nil
      assert metadata.max_attempts == 3
    end

    test "handles partial metadata" do
      defmodule PartialMetadataWorkflow do
        def __workflow_steps__ do
          [
            {:step1, &__MODULE__.step1/1, depends_on: [], timeout: 120}
          ]
        end

        def step1(_input), do: {:ok, %{}}
      end

      {:ok, definition} = WorkflowDefinition.parse(PartialMetadataWorkflow)

      metadata = WorkflowDefinition.get_step_metadata(definition, :step1)
      assert metadata.timeout == 120
      # Defaults should still apply
      assert metadata.initial_tasks == 1
      assert metadata.max_attempts == 3
    end
  end
end
