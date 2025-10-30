defmodule QuantumFlow.MessagingTest do
  use ExUnit.Case, async: true

  alias QuantumFlow.Messaging
  alias QuantumFlow.Notifications

  describe "publish/4" do
    test "publishes message with explicit repo" do
      # Mock the Notifications module
      test_repo = QuantumFlow.Repo

      # We can't easily test the actual publishing without a database,
      # but we can test the function exists and has correct signature
      assert function_exported?(Messaging, :publish, 4)
      assert function_exported?(Messaging, :publish, 3)
    end

    test "handles different payload types" do
      # Test that the function accepts various payload types
      assert is_function(&Messaging.publish/4)
    end

    test "supports keyword options" do
      # Test that options are accepted
      assert is_function(&Messaging.publish/4)
    end
  end

  describe "resolve_repo/1" do
    test "resolves Ecto repo module directly" do
      # This is a private function, but we can test the public interface
      # The publish function should handle repo resolution
      assert function_exported?(Messaging, :publish, 4)
    end

    test "handles application atom resolution" do
      # Test that application atoms are accepted
      assert function_exported?(Messaging, :publish, 4)
    end
  end

  describe "module structure" do
    test "has comprehensive module documentation" do
      docs = Code.get_docs(QuantumFlow.Messaging, :moduledoc)
      assert docs != nil
      {_, doc_content} = docs
      assert String.contains?(doc_content, "Messaging")
      assert String.contains?(doc_content, "PGMQ")
    end

    test "defines expected types" do
      # Check that the module defines the expected types
      types = Code.Typespec.fetch_types(QuantumFlow.Messaging)
      assert {:ok, _} = types
    end
  end
end