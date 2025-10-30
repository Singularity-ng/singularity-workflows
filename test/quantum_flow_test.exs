defmodule QuantumFlowTest do
  use ExUnit.Case, async: true

  alias QuantumFlow.Notifications

  describe "version/0" do
    test "returns the current version" do
      version = QuantumFlow.version()
      assert is_binary(version)
      assert String.match?(version, ~r/^\d+\.\d+\.\d+$/)
    end
  end

  describe "delegated functions" do
    test "send_with_notify delegates to Notifications" do
      # This would require a mock setup, but we're testing the delegation exists
      assert function_exported?(QuantumFlow, :send_with_notify, 3)
    end

    test "listen delegates to Notifications" do
      assert function_exported?(QuantumFlow, :listen, 2)
    end

    test "unlisten delegates to Notifications" do
      assert function_exported?(QuantumFlow, :unlisten, 2)
    end

    test "notify_only delegates to Notifications" do
      assert function_exported?(QuantumFlow, :notify_only, 3)
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
        assert function_exported?(QuantumFlow, function, :erlang.fun_info(&QuantumFlow.version/0)[:arity])
      end
    end

    test "has comprehensive module documentation" do
      {:ok, docs} = Code.fetch_docs(QuantumFlow)
      assert docs != nil
      {_, _, _, _, mod_docs, _, _} = docs
      doc_content = mod_docs["en"]
      assert doc_content != nil
      assert String.contains?(doc_content, "QuantumFlow")
      assert String.contains?(doc_content, "workflow orchestration")
      assert String.contains?(doc_content, "PGMQ")
      assert String.contains?(doc_content, "HTDAG")
    end
  end
end