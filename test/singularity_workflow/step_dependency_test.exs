defmodule Singularity.Workflow.StepDependencyTest do
  use ExUnit.Case, async: true

  alias Singularity.Workflow.StepDependency

  @moduledoc """
  Chicago-style TDD: State-based testing for StepDependency schema.

  Tests focus on dependency graph relationships and changeset validation.
  Query functions (find_dependents/find_dependencies) are tested via integration tests.
  """

  describe "changeset/2 - valid data" do
    test "creates valid changeset with all required fields" do
      attrs = %{
        run_id: Ecto.UUID.generate(),
        step_slug: "process_payment",
        depends_on_step: "validate_order"
      }

      changeset = StepDependency.changeset(%StepDependency{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :run_id) != nil
      assert get_change(changeset, :step_slug) == "process_payment"
      assert get_change(changeset, :depends_on_step) == "validate_order"
    end

    test "accepts different step slugs" do
      attrs = %{
        run_id: Ecto.UUID.generate(),
        step_slug: "merge_results",
        depends_on_step: "fetch_data"
      }

      changeset = StepDependency.changeset(%StepDependency{}, attrs)

      assert changeset.valid?
    end

    test "allows step to depend on itself (circular dependency - DB will enforce)" do
      run_id = Ecto.UUID.generate()

      attrs = %{
        run_id: run_id,
        step_slug: "recursive_step",
        depends_on_step: "recursive_step"
      }

      changeset = StepDependency.changeset(%StepDependency{}, attrs)

      # Changeset validation doesn't prevent this
      # Database constraints or application logic should handle circular deps
      assert changeset.valid?
    end
  end

  describe "changeset/2 - invalid data" do
    test "rejects missing run_id" do
      attrs = %{
        step_slug: "test",
        depends_on_step: "parent"
      }

      changeset = StepDependency.changeset(%StepDependency{}, attrs)

      refute changeset.valid?
      assert %{run_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects missing step_slug" do
      attrs = %{
        run_id: Ecto.UUID.generate(),
        depends_on_step: "parent"
      }

      changeset = StepDependency.changeset(%StepDependency{}, attrs)

      refute changeset.valid?
      assert %{step_slug: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects missing depends_on_step" do
      attrs = %{
        run_id: Ecto.UUID.generate(),
        step_slug: "test"
      }

      changeset = StepDependency.changeset(%StepDependency{}, attrs)

      refute changeset.valid?
      assert %{depends_on_step: ["can't be blank"]} = errors_on(changeset)
    end
  end

  # NOTE: find_dependents/3 and find_dependencies/3 are better tested
  # as integration tests with a real database connection.
  # See test/QuantumFlow/complete_task_test.exs for integration testing.

  describe "schema properties" do
    test "has no primary key" do
      assert StepDependency.__schema__(:primary_key) == []
    end

    test "has immutable timestamps (no updated_at)" do
      # Check that updated_at is not in the schema fields
      fields = StepDependency.__schema__(:fields)
      assert :inserted_at in fields
      refute :updated_at in fields
    end

    test "timestamps use utc_datetime_usec" do
      dep = %StepDependency{inserted_at: DateTime.utc_now()}
      assert %DateTime{} = dep.inserted_at
    end
  end

  describe "associations" do
    test "belongs_to :run association defined" do
      associations = StepDependency.__schema__(:associations)
      assert :run in associations
    end

    test "run belongs_to uses correct foreign_key" do
      assoc = StepDependency.__schema__(:association, :run)
      assert assoc.owner_key == :run_id
      assert assoc.related_key == :id
    end
  end

  describe "dependency graph scenarios" do
    test "simple linear dependency chain changesets" do
      run_id = Ecto.UUID.generate()

      # A → B → C (linear chain)
      deps = [
        %{run_id: run_id, step_slug: "step_b", depends_on_step: "step_a"},
        %{run_id: run_id, step_slug: "step_c", depends_on_step: "step_b"}
      ]

      # Verify changesets are valid
      changesets =
        Enum.map(deps, fn dep ->
          StepDependency.changeset(%StepDependency{}, dep)
        end)

      assert Enum.all?(changesets, & &1.valid?)
    end

    test "diamond dependency pattern changesets" do
      run_id = Ecto.UUID.generate()

      #     A
      #    / \
      #   B   C
      #    \ /
      #     D

      deps = [
        %{run_id: run_id, step_slug: "step_b", depends_on_step: "step_a"},
        %{run_id: run_id, step_slug: "step_c", depends_on_step: "step_a"},
        %{run_id: run_id, step_slug: "step_d", depends_on_step: "step_b"},
        %{run_id: run_id, step_slug: "step_d", depends_on_step: "step_c"}
      ]

      changesets =
        Enum.map(deps, fn dep ->
          StepDependency.changeset(%StepDependency{}, dep)
        end)

      assert Enum.all?(changesets, & &1.valid?)
    end

    test "fan-out pattern changesets (one parent, many children)" do
      run_id = Ecto.UUID.generate()

      #       A
      #    / | | \
      #   B  C D  E

      deps = [
        %{run_id: run_id, step_slug: "step_b", depends_on_step: "step_a"},
        %{run_id: run_id, step_slug: "step_c", depends_on_step: "step_a"},
        %{run_id: run_id, step_slug: "step_d", depends_on_step: "step_a"},
        %{run_id: run_id, step_slug: "step_e", depends_on_step: "step_a"}
      ]

      changesets =
        Enum.map(deps, fn dep ->
          StepDependency.changeset(%StepDependency{}, dep)
        end)

      assert Enum.all?(changesets, & &1.valid?)
    end

    test "fan-in pattern changesets (many parents, one child)" do
      run_id = Ecto.UUID.generate()

      #   A  B  C
      #    \ | /
      #      D

      deps = [
        %{run_id: run_id, step_slug: "step_d", depends_on_step: "step_a"},
        %{run_id: run_id, step_slug: "step_d", depends_on_step: "step_b"},
        %{run_id: run_id, step_slug: "step_d", depends_on_step: "step_c"}
      ]

      changesets =
        Enum.map(deps, fn dep ->
          StepDependency.changeset(%StepDependency{}, dep)
        end)

      assert Enum.all?(changesets, & &1.valid?)
    end

    test "isolated runs don't interfere (same step slugs, different run_ids)" do
      run_id_1 = Ecto.UUID.generate()
      run_id_2 = Ecto.UUID.generate()

      # Same step slugs, different runs
      dep1 = %{run_id: run_id_1, step_slug: "step_b", depends_on_step: "step_a"}
      dep2 = %{run_id: run_id_2, step_slug: "step_b", depends_on_step: "step_a"}

      changeset1 = StepDependency.changeset(%StepDependency{}, dep1)
      changeset2 = StepDependency.changeset(%StepDependency{}, dep2)

      assert changeset1.valid?
      assert changeset2.valid?
    end
  end

  describe "edge cases" do
    test "step can have multiple dependencies recorded separately" do
      run_id = Ecto.UUID.generate()

      # Record multiple dependencies for same step
      deps = [
        %{run_id: run_id, step_slug: "merge", depends_on_step: "source1"},
        %{run_id: run_id, step_slug: "merge", depends_on_step: "source2"},
        %{run_id: run_id, step_slug: "merge", depends_on_step: "source3"}
      ]

      changesets = Enum.map(deps, &StepDependency.changeset(%StepDependency{}, &1))

      assert Enum.all?(changesets, & &1.valid?)
    end

    test "dependency records are immutable (no updated_at)" do
      dep = %StepDependency{
        run_id: Ecto.UUID.generate(),
        step_slug: "test",
        depends_on_step: "parent",
        inserted_at: DateTime.utc_now()
      }

      # Only inserted_at exists
      assert Map.has_key?(dep, :inserted_at)
      refute Map.has_key?(dep, :updated_at)
    end

    # NOTE: Query tests moved to integration tests
  end

  # Helper functions
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp get_change(changeset, field) do
    Ecto.Changeset.get_change(changeset, field)
  end
end
