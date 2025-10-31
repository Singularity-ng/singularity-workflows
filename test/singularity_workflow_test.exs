defmodule Singularity.Workflow.Test do
  use ExUnit.Case, async: true

  alias Singularity.Workflow.Notifications

  describe "version/0" do
    test "returns the current version" do
      version = Singularity.Workflow.version()
      assert is_binary(version)
      assert String.match?(version, ~r/^\d+\.\d+\.\d+$/)
    end
  end

  describe "delegated functions" do
    test "send_with_notify delegates to Notifications" do
      # This would require a mock setup, but we're testing the delegation exists
      assert function_exported?(Singularity.Workflow, :send_with_notify, 3)
    end

    test "listen delegates to Notifications" do
      assert function_exported?(Singularity.Workflow, :listen, 2)
    end

    test "unlisten delegates to Notifications" do
      assert function_exported?(Singularity.Workflow, :unlisten, 2)
    end

    test "notify_only delegates to Notifications" do
      assert function_exported?(Singularity.Workflow, :notify_only, 3)
    end
  end

  describe "module structure" do
    test "exports expected public functions" do
      expected_functions = [
        :version,
        :send_with_notify,
        :listen,
        :unlisten,
        :notify_only
      ]

      for function <- expected_functions do
        assert function_exported?(
                 Singularity.Workflow,
                 function,
                 :erlang.fun_info(&Singularity.Workflow.version/0)[:arity]
               )
      end
    end

    test "has comprehensive module documentation" do
      {:ok, docs} = Code.fetch_docs(Singularity.Workflow)
      assert docs != nil
      {_, _, _, _, mod_docs, _, _} = docs
      doc_content = mod_docs["en"]
      assert doc_content != nil
      assert String.contains?(doc_content, "Singularity.Workflow")
      assert String.contains?(doc_content, "workflow orchestration")
      assert String.contains?(doc_content, "PGMQ")
      assert String.contains?(doc_content, "HTDAG")
    end
  end
end
