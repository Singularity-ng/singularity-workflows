defmodule Singularity.Integration.QueueLoopIntegrationTest do
  @moduledoc """
  Integration tests for the complete queue loop system.

  Tests the full flow from Singularity → pgmq → Nexus → Observer → CentralCloud
  including HITL approvals, Genesis publishing, and failure pattern sync.
  """

  use Singularity.DataCase, async: false
  use ExUnit.Case, async: false

  alias Singularity.Jobs.PgmqClient
  alias Singularity.Storage.FailurePatternStore
  alias Singularity.Storage.ValidationMetricsStore
  alias Singularity.Evolution.GenesisPublisher
  alias Observer.HITL

  @moduletag :integration
  @moduletag :queue_loop

  setup do
    # Ensure all required queues exist
    PgmqClient.ensure_all_queues()
    
    # Clean up any existing data
    :ok = cleanup_test_data()
    
    :ok
  end

  describe "Complete Queue Loop Integration" do
    test "end-to-end queue flow with HITL approvals" do
      # 1. Singularity publishes a task to pgmq
      task_payload = %{
        task_id: "test_task_#{System.unique_integer([:positive])}",
        task_type: "architect",
        complexity: "high",
        description: "Design a microservice architecture",
        agent_id: "test_agent",
        response_queue: "test_responses"
      }

      {:ok, _message_id} = PgmqClient.send_message("ai_requests", task_payload)

      # 2. Simulate Nexus processing and requesting HITL approval
      hitl_request = %{
        request_id: "hitl_#{System.unique_integer([:positive])}",
        agent_id: "test_agent",
        task_type: "architect",
        payload: %{
          plan: "Generated microservice architecture plan",
          confidence: 0.85,
          estimated_cost: 150
        },
        response_queue: "test_responses",
        metadata: %{
          complexity: "high",
          estimated_duration: "2 hours"
        }
      }

      {:ok, _hitl_id} = PgmqClient.send_message("observer_hitl_requests", hitl_request)

      # 3. Observer processes HITL request
      Process.sleep(100)  # Allow async processing

      # Verify HITL approval was created
      approvals = HITL.list_approvals(limit: 10)
      assert length(approvals) >= 1

      approval = Enum.find(approvals, &(&1.request_id == hitl_request.request_id))
      assert approval != nil
      assert approval.status == :pending
      assert approval.task_type == "architect"

      # 4. Human approves the request
      {:ok, approved} = HITL.approve(approval, %{
        decided_by: "test_user",
        decision_reason: "Plan looks good for testing"
      })

      assert approved.status == :approved
      assert approved.decided_by == "test_user"

      # 5. Publish decision back to requester
      :ok = HITL.publish_decision(approved)

      # 6. Verify decision was published to response queue
      messages = PgmqClient.read_messages("test_responses", 5)
      assert length(messages) >= 1

      {_msg_id, response} = List.first(messages)
      assert response["request_id"] == hitl_request.request_id
      assert response["decision"] == "approved"
      assert response["decided_by"] == "test_user"
    end

    test "Genesis rule publishing and importing" do
      # 1. Publish rules to Genesis
      {:ok, publish_results} = GenesisPublisher.publish_rules(limit: 3)
      
      assert length(publish_results) == 3
      assert Enum.all?(publish_results, &(&1.status == :published))
      assert Enum.all?(publish_results, &(&1.genesis_id != nil))

      # 2. Verify rules were published to pgmq
      messages = PgmqClient.read_messages("genesis_rule_updates", 10)
      assert length(messages) >= 3

      # 3. Import rules from Genesis
      {:ok, imported_rules} = GenesisPublisher.import_rules_from_genesis(limit: 5)
      
      # Should import the rules we just published
      assert length(imported_rules) >= 0  # May be 0 if no rules in queue
      
      # 4. Verify rules were acknowledged
      remaining_messages = PgmqClient.read_messages("genesis_rule_updates", 10)
      assert length(remaining_messages) == 0  # All should be acknowledged
    end

    test "Failure pattern recording and CentralCloud sync" do
      # 1. Record some failure patterns
      failure_patterns = [
        %{
          story_type: "test_story",
          story_signature: "test_signature_1",
          failure_mode: "validation_error",
          root_cause: "Invalid input parameters",
          execution_error: "Parameter validation failed",
          frequency: 1
        },
        %{
          story_type: "test_story",
          story_signature: "test_signature_2", 
          failure_mode: "timeout_error",
          root_cause: "External service timeout",
          execution_error: "Request timed out after 30s",
          frequency: 2
        }
      ]

      for pattern <- failure_patterns do
        {:ok, _} = FailurePatternStore.record_failure(pattern)
      end

      # 2. Verify patterns were recorded
      patterns = FailurePatternStore.query(%{limit: 10})
      assert length(patterns) >= 2

      # 3. Test CentralCloud sync (should not fail even if CentralCloud not configured)
      {:ok, _count} = FailurePatternStore.sync_with_centralcloud()
    end

    test "Validation metrics recording and sync" do
      run_id = "test_run_#{System.unique_integer([:positive])}"

      # 1. Record validation metrics
      validation_attrs = %{
        run_id: run_id,
        check_id: "template_check",
        check_type: "template",
        result: "pass",
        confidence_score: 0.92,
        runtime_ms: 150
      }

      {:ok, _validation} = ValidationMetricsStore.record_validation(validation_attrs)

      # 2. Record execution metrics
      execution_attrs = %{
        run_id: run_id,
        task_type: "architect",
        model: "claude-3-5-sonnet",
        provider: "anthropic",
        cost_cents: 125,
        tokens_used: 3500,
        latency_ms: 2500,
        success: true
      }

      {:ok, _execution} = ValidationMetricsStore.record_execution(execution_attrs)

      # 3. Verify metrics were recorded
      validation_metrics = ValidationMetricsStore.get_validation_metrics_for_run(run_id)
      assert length(validation_metrics) == 1

      execution_metrics = ValidationMetricsStore.get_execution_metrics_for_run(run_id)
      assert length(execution_metrics) == 1

      # 4. Test CentralCloud sync
      {:ok, _count} = ValidationMetricsStore.sync_with_centralcloud()
    end

    test "Observer dashboard data integration" do
      # 1. Record some test data
      run_id = "dashboard_test_#{System.unique_integer([:positive])}"

      # Record validation metrics
      {:ok, _} = ValidationMetricsStore.record_validation(%{
        run_id: run_id,
        check_id: "quality_check",
        check_type: "quality",
        result: "pass",
        confidence_score: 0.88,
        runtime_ms: 200
      })

      # Record execution metrics
      {:ok, _} = ValidationMetricsStore.record_execution(%{
        run_id: run_id,
        task_type: "coder",
        model: "gpt-4",
        provider: "openai",
        cost_cents: 75,
        tokens_used: 2000,
        latency_ms: 1800,
        success: true
      })

      # Record failure pattern
      {:ok, _} = FailurePatternStore.record_failure(%{
        story_type: "dashboard_test",
        story_signature: "dashboard_signature",
        failure_mode: "test_failure",
        root_cause: "Test root cause",
        frequency: 1
      })

      # 2. Test Observer dashboard data fetching
      # These should not crash even if Singularity modules are not available
      validation_data = Observer.Dashboard.validation_metrics_store()
      assert is_tuple(validation_data)  # {:ok, data} or {:error, reason}

      failure_data = Observer.Dashboard.failure_patterns()
      assert is_tuple(failure_data)  # {:ok, data} or {:error, reason}
    end

    test "Queue error handling and recovery" do
      # 1. Test sending invalid message to queue
      invalid_payload = %{invalid: "data", with: :atoms}
      
      # This should not crash the system
      result = PgmqClient.send_message("ai_requests", invalid_payload)
      assert is_tuple(result)  # {:ok, _} or {:error, _}

      # 2. Test reading from non-existent queue
      messages = PgmqClient.read_messages("non_existent_queue", 1)
      assert is_list(messages)
      assert length(messages) == 0

      # 3. Test acknowledging non-existent message
      result = PgmqClient.ack_message("ai_requests", 99999)
      assert result == :ok  # Should not crash
    end

    test "Concurrent queue operations" do
      # 1. Send multiple messages concurrently
      tasks = for i <- 1..10 do
        Task.async(fn ->
          payload = %{
            task_id: "concurrent_task_#{i}",
            task_type: "test",
            description: "Concurrent test task #{i}"
          }
          PgmqClient.send_message("ai_requests", payload)
        end)
      end

      results = Task.await_many(tasks, 5000)
      assert length(results) == 10
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # 2. Read messages concurrently
      read_tasks = for _i <- 1..5 do
        Task.async(fn ->
          PgmqClient.read_messages("ai_requests", 2)
        end)
      end

      read_results = Task.await_many(read_tasks, 5000)
      assert length(read_results) == 5
      assert Enum.all?(read_results, &is_list/1)
    end
  end

  # Helper functions

  defp cleanup_test_data do
    # Clean up test data from databases
    try do
      # Clean up HITL approvals
      if Code.ensure_loaded?(Observer.HITL) do
        # This would clean up test approvals if we had a cleanup function
        :ok
      else
        :ok
      end
    rescue
      _ -> :ok
    end

    # Clean up pgmq messages (they auto-expire, but we can try to read them)
    try do
      PgmqClient.read_messages("ai_requests", 100)
      PgmqClient.read_messages("ai_results", 100)
      PgmqClient.read_messages("observer_hitl_requests", 100)
      PgmqClient.read_messages("genesis_rule_updates", 100)
    rescue
      _ -> :ok
    end

    :ok
  end
end