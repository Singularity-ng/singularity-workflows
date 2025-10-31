defmodule Singularity.Workflow.WorkflowSupervisorTest do
  use ExUnit.Case, async: true

  alias Singularity.Workflow.WorkflowSupervisor

  describe "child_spec/1" do
    test "returns proper supervisor child spec" do
      opts = [workflow: TestWorkflow, repo: TestRepo, name: :test_supervisor]

      spec = WorkflowSupervisor.child_spec(opts)

      assert spec.id == :test_supervisor
      assert spec.start == {WorkflowSupervisor, :start_link, [opts]}
      assert spec.type == :supervisor
      assert spec.shutdown == 5000
    end

    test "uses default name when not specified" do
      opts = [workflow: TestWorkflow, repo: TestRepo]

      spec = WorkflowSupervisor.child_spec(opts)

      assert spec.id == WorkflowSupervisor
    end
  end

  describe "start_link/1" do
    test "returns :ignore when enabled is false" do
      opts = [workflow: TestWorkflow, repo: TestRepo, enabled: false]

      result = WorkflowSupervisor.start_link(opts)

      assert result == :ignore
    end

    test "defaults to enabled when not specified" do
      opts = [workflow: TestWorkflow, repo: TestRepo]

      # Should attempt to start (and fail due to missing workflow implementation)
      # but not return :ignore
      result = WorkflowSupervisor.start_link(opts)
      assert result != :ignore
    end
  end

  describe "module structure" do
    test "has comprehensive module documentation" do
      {:ok, docs} = Code.fetch_docs(Singularity.Workflow.WorkflowSupervisor)
      assert docs != nil
      {_, _, _, _, mod_docs, _, _} = docs
      doc_content = mod_docs["en"]
      assert doc_content != nil
      assert String.contains?(doc_content, "Supervisor")
      assert String.contains?(doc_content, "backwards compatibility")
    end

    test "defines expected types" do
      # Check that the module defines types
      types = Code.Typespec.fetch_types(Singularity.Workflow.WorkflowSupervisor)
      assert {:ok, types} = types
      # Should have at least some types defined
      assert length(types) > 0
    end
  end
end
