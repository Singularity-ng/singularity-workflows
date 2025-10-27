defmodule Singularity.Regression.TaskGraphLLMAssistanceTest do
  @moduledoc """
  Regression tests for TaskGraph plans that depend on LLM assistance.

  These tests ensure that TaskGraph execution continues to work correctly
  with LLM assistance after system changes and updates.
  """

  use Singularity.DataCase, async: false
  use ExUnit.Case, async: false

  alias Singularity.Execution.Planning.TaskGraph
  alias Singularity.LLM.Service

  @moduletag :regression
  @moduletag :taskgraph
  @moduletag :llm_assistance

  setup do
    # Ensure clean state for each test
    :ok = cleanup_test_data()
    :ok
  end

  describe "TaskGraph LLM Assistance Regression Tests" do
    test "architect task with LLM assistance completes successfully" do
      # Test a complex architectural task that requires LLM assistance
      task_description = "Design a microservice architecture for an e-commerce platform with user management, product catalog, order processing, and payment handling"

      # Create TaskGraph plan
      {:ok, plan} = TaskGraph.create_plan(%{
        description: task_description,
        task_type: :architect,
        complexity: :high,
        requirements: %{
          services: ["user-service", "product-service", "order-service", "payment-service"],
          database: "PostgreSQL with Redis caching",
          messaging: "RabbitMQ or Apache Kafka",
          monitoring: "Prometheus + Grafana"
        }
      })

      assert plan != nil
      assert plan.task_type == :architect
      assert plan.complexity == :high

      # Execute the plan with LLM assistance
      {:ok, execution_result} = TaskGraph.execute_plan(plan, %{
        use_llm_assistance: true,
        max_iterations: 3,
        timeout: 30000
      })

      # Verify execution completed successfully
      assert execution_result.status == :completed
      assert execution_result.llm_assistance_used == true
      assert execution_result.iterations > 0
      assert execution_result.final_plan != nil

      # Verify the final plan contains expected architectural elements
      final_plan = execution_result.final_plan
      assert is_map(final_plan)
      assert final_plan.services != nil
      assert is_list(final_plan.services)
      assert length(final_plan.services) >= 4  # At least the required services

      # Verify each service has required fields
      for service <- final_plan.services do
        assert service.name != nil
        assert service.description != nil
        assert service.endpoints != nil
        assert is_list(service.endpoints)
      end
    end

    test "coder task with LLM assistance generates working code" do
      # Test a coding task that requires LLM assistance
      task_description = "Implement a REST API for user authentication with JWT tokens, password hashing, and rate limiting"

      # Create TaskGraph plan
      {:ok, plan} = TaskGraph.create_plan(%{
        description: task_description,
        task_type: :coder,
        complexity: :medium,
        language: "elixir",
        framework: "phoenix",
        requirements: %{
          endpoints: ["POST /auth/login", "POST /auth/register", "GET /auth/profile"],
          security: ["JWT tokens", "bcrypt password hashing", "rate limiting"],
          database: "PostgreSQL with Ecto"
        }
      })

      assert plan != nil
      assert plan.task_type == :coder
      assert plan.language == "elixir"

      # Execute the plan with LLM assistance
      {:ok, execution_result} = TaskGraph.execute_plan(plan, %{
        use_llm_assistance: true,
        max_iterations: 2,
        timeout: 20000
      })

      # Verify execution completed successfully
      assert execution_result.status == :completed
      assert execution_result.llm_assistance_used == true
      assert execution_result.generated_code != nil

      # Verify generated code contains expected elements
      generated_code = execution_result.generated_code
      assert is_binary(generated_code)
      assert String.contains?(generated_code, "defmodule")
      assert String.contains?(generated_code, "plug")
      assert String.contains?(generated_code, "JWT")
      assert String.contains?(generated_code, "bcrypt")
    end

    test "refactoring task with LLM assistance improves code quality" do
      # Test a refactoring task that requires LLM assistance
      existing_code = """
      defmodule UserService do
        def get_user(id) do
          case Repo.get(User, id) do
            nil -> {:error, "User not found"}
            user -> {:ok, user}
          end
        end

        def create_user(params) do
          changeset = User.changeset(%User{}, params)
          case Repo.insert(changeset) do
            {:ok, user} -> {:ok, user}
            {:error, changeset} -> {:error, changeset}
          end
        end
      end
      """

      task_description = "Refactor this code to improve error handling, add input validation, and follow Elixir best practices"

      # Create TaskGraph plan
      {:ok, plan} = TaskGraph.create_plan(%{
        description: task_description,
        task_type: :refactoring,
        complexity: :medium,
        language: "elixir",
        existing_code: existing_code,
        requirements: %{
          improvements: ["better error handling", "input validation", "Elixir best practices"],
          maintain: ["existing API", "function signatures"]
        }
      })

      assert plan != nil
      assert plan.task_type == :refactoring

      # Execute the plan with LLM assistance
      {:ok, execution_result} = TaskGraph.execute_plan(plan, %{
        use_llm_assistance: true,
        max_iterations: 2,
        timeout: 15000
      })

      # Verify execution completed successfully
      assert execution_result.status == :completed
      assert execution_result.llm_assistance_used == true
      assert execution_result.refactored_code != nil

      # Verify refactored code is improved
      refactored_code = execution_result.refactored_code
      assert is_binary(refactored_code)
      assert String.contains?(refactored_code, "defmodule UserService")
      
      # Should have better error handling
      assert String.contains?(refactored_code, "with") or 
             String.contains?(refactored_code, "case") or
             String.contains?(refactored_code, "try")
    end

    test "planning task with LLM assistance creates comprehensive plan" do
      # Test a planning task that requires LLM assistance
      task_description = "Plan the development of a real-time chat application with WebSocket support, message persistence, and user presence"

      # Create TaskGraph plan
      {:ok, plan} = TaskGraph.create_plan(%{
        description: task_description,
        task_type: :planning,
        complexity: :high,
        requirements: %{
          features: ["real-time messaging", "WebSocket support", "message history", "user presence"],
          technology: "Elixir/Phoenix with LiveView",
          timeline: "4 weeks"
        }
      })

      assert plan != nil
      assert plan.task_type == :planning

      # Execute the plan with LLM assistance
      {:ok, execution_result} = TaskGraph.execute_plan(plan, %{
        use_llm_assistance: true,
        max_iterations: 3,
        timeout: 25000
      })

      # Verify execution completed successfully
      assert execution_result.status == :completed
      assert execution_result.llm_assistance_used == true
      assert execution_result.detailed_plan != nil

      # Verify detailed plan contains expected elements
      detailed_plan = execution_result.detailed_plan
      assert is_map(detailed_plan)
      assert detailed_plan.phases != nil
      assert is_list(detailed_plan.phases)
      assert length(detailed_plan.phases) > 0

      # Verify each phase has required fields
      for phase <- detailed_plan.phases do
        assert phase.name != nil
        assert phase.description != nil
        assert phase.tasks != nil
        assert is_list(phase.tasks)
        assert phase.estimated_duration != nil
      end
    end

    test "handles LLM service unavailability gracefully" do
      # Test that TaskGraph handles LLM service failures gracefully
      task_description = "Simple task that should work without LLM assistance"

      # Create TaskGraph plan
      {:ok, plan} = TaskGraph.create_plan(%{
        description: task_description,
        task_type: :coder,
        complexity: :simple,
        language: "elixir"
      })

      # Mock LLM service failure
      Mox.stub_with(ServiceMock, Service)
      Mox.expect(ServiceMock, :call_with_prompt, fn _complexity, _prompt, _opts ->
        {:error, "LLM service unavailable"}
      end)

      # Execute the plan with LLM assistance (should fallback gracefully)
      {:ok, execution_result} = TaskGraph.execute_plan(plan, %{
        use_llm_assistance: true,
        fallback_to_simple: true,
        max_iterations: 1,
        timeout: 5000
      })

      # Should complete with fallback behavior
      assert execution_result.status in [:completed, :partial]
      assert execution_result.llm_assistance_used == false or execution_result.llm_assistance_used == nil
    end

    test "maintains consistency across multiple executions" do
      # Test that similar tasks produce consistent results
      task_description = "Create a simple user model with name, email, and age fields"

      # Execute the same task multiple times
      results = for i <- 1..3 do
        {:ok, plan} = TaskGraph.create_plan(%{
          description: task_description,
          task_type: :coder,
          complexity: :simple,
          language: "elixir",
          run_id: "consistency_test_#{i}"
        })

        {:ok, execution_result} = TaskGraph.execute_plan(plan, %{
          use_llm_assistance: true,
          max_iterations: 1,
          timeout: 10000
        })

        execution_result
      end

      # All executions should complete successfully
      assert Enum.all?(results, &(&1.status == :completed))
      assert Enum.all?(results, &(&1.llm_assistance_used == true))

      # Results should be similar (same structure, similar content)
      for result <- results do
        assert result.generated_code != nil
        assert is_binary(result.generated_code)
        assert String.contains?(result.generated_code, "defmodule")
        assert String.contains?(result.generated_code, "schema")
      end
    end

    test "respects timeout constraints" do
      # Test that TaskGraph respects timeout constraints
      task_description = "Complex task that might take a long time"

      {:ok, plan} = TaskGraph.create_plan(%{
        description: task_description,
        task_type: :architect,
        complexity: :high
      })

      # Execute with very short timeout
      start_time = System.monotonic_time(:millisecond)
      
      {:ok, execution_result} = TaskGraph.execute_plan(plan, %{
        use_llm_assistance: true,
        max_iterations: 1,
        timeout: 1000  # 1 second timeout
      })

      end_time = System.monotonic_time(:millisecond)
      execution_time = end_time - start_time

      # Should respect timeout (allow some margin for overhead)
      assert execution_time < 2000  # 2 seconds max
      
      # Should either complete quickly or timeout gracefully
      assert execution_result.status in [:completed, :timeout, :partial]
    end
  end

  # Helper functions

  defp cleanup_test_data do
    # Clean up any test data that might interfere with tests
    try do
      # This would clean up any test data if needed
      :ok
    rescue
      _ -> :ok
    end
  end
end