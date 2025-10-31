defmodule Singularity.Workflow.Orchestrator.ExampleDecomposerTest do
  use ExUnit.Case, async: true

  alias Singularity.Workflow.Orchestrator.ExampleDecomposer

  describe "simple_decompose/1" do
    test "decomposes authentication goal into tasks" do
      goal = "Build user authentication system"

      {:ok, tasks} = ExampleDecomposer.simple_decompose(goal)

      assert length(tasks) == 4
      assert Enum.find(tasks, &(&1.id == "validate_input"))
      assert Enum.find(tasks, &(&1.id == "hash_password"))
      assert Enum.find(tasks, &(&1.id == "create_user"))
      assert Enum.find(tasks, &(&1.id == "send_welcome"))

      # Check dependencies
      hash_password = Enum.find(tasks, &(&1.id == "hash_password"))
      assert hash_password.depends_on == ["validate_input"]

      create_user = Enum.find(tasks, &(&1.id == "create_user"))
      assert create_user.depends_on == ["hash_password"]

      send_welcome = Enum.find(tasks, &(&1.id == "send_welcome"))
      assert send_welcome.depends_on == ["create_user"]
    end

    test "decomposes deployment goal into tasks" do
      goal = "Deploy application to production"

      {:ok, tasks} = ExampleDecomposer.simple_decompose(goal)

      assert length(tasks) == 5
      assert Enum.find(tasks, &(&1.id == "check_prerequisites"))
      assert Enum.find(tasks, &(&1.id == "build_artifacts"))
      assert Enum.find(tasks, &(&1.id == "deploy_services"))
      assert Enum.find(tasks, &(&1.id == "run_tests"))
      assert Enum.find(tasks, &(&1.id == "verify_deployment"))
    end

    test "handles unknown goals gracefully" do
      goal = "Do something completely unknown"

      {:ok, tasks} = ExampleDecomposer.simple_decompose(goal)

      assert length(tasks) == 4
      assert Enum.find(tasks, &(&1.id == "analyze_goal"))
      assert Enum.find(tasks, &(&1.id == "plan_execution"))
      assert Enum.find(tasks, &(&1.id == "execute_plan"))
      assert Enum.find(tasks, &(&1.id == "verify_completion"))
    end

    test "handles non-string goals" do
      goal = %{action: "build auth system"}

      {:ok, tasks} = ExampleDecomposer.simple_decompose(goal)

      assert length(tasks) == 4
      # Should normalize the goal and treat it as unknown
      assert Enum.find(tasks, &(&1.id == "analyze_goal"))
    end
  end

  describe "microservices_decompose/1" do
    test "decomposes microservices goal" do
      goal = "Build microservices architecture"

      {:ok, tasks} = ExampleDecomposer.microservices_decompose(goal)

      assert length(tasks) >= 8
      # Should contain service-related tasks
      task_ids = Enum.map(tasks, & &1.id)
      assert Enum.any?(task_ids, &String.contains?(&1, "service"))
      assert Enum.any?(task_ids, &String.contains?(&1, "setup"))
    end

    test "handles non-matching goals" do
      goal = "Build a sandwich"

      {:ok, tasks} = ExampleDecomposer.microservices_decompose(goal)

      assert length(tasks) == 4
      assert Enum.find(tasks, &(&1.id == "analyze_goal"))
    end
  end

  describe "data_pipeline_decompose/1" do
    test "decomposes data pipeline goals" do
      goal = "Build data pipeline for analytics"

      {:ok, tasks} = ExampleDecomposer.data_pipeline_decompose(goal)

      assert length(tasks) >= 9
      # Should have extraction, transformation, and loading tasks
      task_ids = Enum.map(tasks, & &1.id)
      assert Enum.any?(task_ids, &String.contains?(&1, "extract"))
      assert Enum.any?(task_ids, &String.contains?(&1, "transform"))
      assert Enum.any?(task_ids, &String.contains?(&1, "load"))
    end
  end

  describe "ml_pipeline_decompose/1" do
    test "decomposes ML pipeline goals" do
      goal = "Build machine learning model"

      {:ok, tasks} = ExampleDecomposer.ml_pipeline_decompose(goal)

      assert length(tasks) >= 9
      # Should have data prep, training, and deployment tasks
      task_ids = Enum.map(tasks, & &1.id)
      assert Enum.any?(task_ids, &String.contains?(&1, "train"))
      assert Enum.any?(task_ids, &String.contains?(&1, "model"))
      assert Enum.any?(task_ids, &String.contains?(&1, "deploy"))
    end
  end

  describe "module structure" do
    test "has comprehensive module documentation" do
      {:docs_v1, _, _, _, mod_docs, _, _} =
        Code.fetch_docs(Singularity.Workflow.Orchestrator.ExampleDecomposer)

      doc_content = mod_docs["en"]
      assert doc_content != nil
      assert String.contains?(doc_content, "Example decomposer")
      assert String.contains?(doc_content, "HTDAG")
    end

    test "defines expected function specs" do
      # Check that functions have proper specs
      assert function_exported?(ExampleDecomposer, :simple_decompose, 1)
      assert function_exported?(ExampleDecomposer, :microservices_decompose, 1)
      assert function_exported?(ExampleDecomposer, :data_pipeline_decompose, 1)
      assert function_exported?(ExampleDecomposer, :ml_pipeline_decompose, 1)
    end
  end
end
