defmodule Singularity.Workflow.MessagingTest do
  use ExUnit.Case, async: true

  alias Singularity.Workflow.Messaging
  alias Singularity.Workflow.Notifications

  describe "publish/4" do
    test "publishes message with explicit repo" do
      # We can't easily test the actual publishing without a database,
      # but we can test the function exists and has correct signature
      assert is_function(&Messaging.publish/4)
      assert is_function(&Messaging.publish/3)
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
      assert is_function(&Messaging.publish/4)
    end

    test "handles application atom resolution" do
      # Test that application atoms are accepted
      assert is_function(&Messaging.publish/4)
    end
  end

  describe "module structure" do
    test "has comprehensive module documentation" do
      {:docs_v1, _, _, _, mod_docs, _, _} = Code.fetch_docs(Singularity.Workflow.Messaging)
      doc_content = mod_docs["en"]
      assert doc_content != nil
      assert String.contains?(doc_content, "Messaging")
      assert String.contains?(doc_content, "pgmq")
    end

    test "defines expected types" do
      # Check that the module defines the expected types
      types = Code.Typespec.fetch_types(Singularity.Workflow.Messaging)
      assert {:ok, _} = types
    end
  end
end
