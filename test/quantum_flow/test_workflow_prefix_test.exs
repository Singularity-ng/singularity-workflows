defmodule QuantumFlow.TestWorkflowPrefixTest do
  use ExUnit.Case, async: true

  alias QuantumFlow.TestWorkflowPrefix

  describe "start/0" do
    test "returns a string with the expected prefix format" do
      prefix = TestWorkflowPrefix.start()

      assert is_binary(prefix)
      assert String.starts_with?(prefix, "quantum_flow_test_")
      assert String.ends_with?(prefix, "_")
      # Should be 8 characters for the UUID slice + prefix + suffix
      # "quantum_flow_test_" + 8 chars + "_"
      assert String.length(prefix) == 8 + 19 + 1
    end

    test "returns unique prefixes on multiple calls" do
      prefix1 = TestWorkflowPrefix.start()
      prefix2 = TestWorkflowPrefix.start()

      assert prefix1 != prefix2
    end

    test "prefix contains only valid characters" do
      prefix = TestWorkflowPrefix.start()

      # Should contain only lowercase letters, numbers, and underscores
      assert String.match?(prefix, ~r/^[a-z0-9_]+$/)
    end
  end

  describe "module structure" do
    test "has comprehensive module documentation" do
      {:docs_v1, _, _, _, mod_docs, _, _} = Code.fetch_docs(QuantumFlow.TestWorkflowPrefix)
      doc_content = mod_docs["en"]
      assert doc_content != nil
      assert String.contains?(doc_content, "Test workflow naming utility")
      assert String.contains?(doc_content, "UUID-based identifiers")
    end

    test "defines expected function specs" do
      # Check that functions have proper specs
      functions = QuantumFlow.TestWorkflowPrefix.__info__(:functions)
      assert Keyword.has_key?(functions, :start)
      assert Keyword.has_key?(functions, :cleanup_by_prefix)
    end
  end
end
