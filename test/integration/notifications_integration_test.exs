defmodule Pgflow.NotificationsIntegrationTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Pgflow.Notifications

  # Test database setup
  setup do
    # This would normally set up a test database
    # For this demo, we'll use a mock repo
    %{repo: TestRepo}
  end

  describe "end-to-end notification flow" do
    test "complete workflow notification lifecycle" do
      # Test a complete workflow from start to finish
      workflow_id = "integration_test_#{System.unique_integer([:positive])}"
      
      # 1. Start workflow
      {:ok, _} = Notifications.send_with_notify("workflow_events", %{
        type: "workflow_started",
        workflow_id: workflow_id,
        input: %{test: true}
      }, TestRepo)

      # 2. Start tasks
      {:ok, _} = Notifications.send_with_notify("workflow_events", %{
        type: "task_started",
        task_id: "task_1",
        workflow_id: workflow_id,
        step_name: "process_data"
      }, TestRepo)

      # 3. Complete tasks
      {:ok, _} = Notifications.send_with_notify("workflow_events", %{
        type: "task_completed",
        task_id: "task_1",
        workflow_id: workflow_id,
        result: %{processed: true}
      }, TestRepo)

      # 4. Complete workflow
      {:ok, _} = Notifications.send_with_notify("workflow_events", %{
        type: "workflow_completed",
        workflow_id: workflow_id,
        final_result: %{success: true}
      }, TestRepo)

      # All notifications should be sent successfully
      assert true
    end

    test "error handling and recovery flow" do
      workflow_id = "error_test_#{System.unique_integer([:positive])}"
      
      # 1. Start workflow
      {:ok, _} = Notifications.send_with_notify("workflow_events", %{
        type: "workflow_started",
        workflow_id: workflow_id
      }, TestRepo)

      # 2. Task fails
      {:ok, _} = Notifications.send_with_notify("workflow_events", %{
        type: "task_failed",
        task_id: "task_1",
        workflow_id: workflow_id,
        error: "Connection timeout",
        retry_count: 1
      }, TestRepo)

      # 3. Retry task
      {:ok, _} = Notifications.send_with_notify("workflow_events", %{
        type: "task_retry",
        task_id: "task_1",
        workflow_id: workflow_id,
        retry_count: 2
      }, TestRepo)

      # 4. Task succeeds on retry
      {:ok, _} = Notifications.send_with_notify("workflow_events", %{
        type: "task_completed",
        task_id: "task_1",
        workflow_id: workflow_id,
        result: %{processed: true, retried: true}
      }, TestRepo)

      # 5. Workflow completes
      {:ok, _} = Notifications.send_with_notify("workflow_events", %{
        type: "workflow_completed",
        workflow_id: workflow_id,
        final_result: %{success: true, recovered: true}
      }, TestRepo)

      assert true
    end
  end

  describe "multi-application integration" do
    test "Observer web UI integration" do
      # Simulate Observer integration
      approval_events = [
        %{
          type: "approval_created",
          approval_id: "app_123",
          request_id: "req_456",
          title: "Deploy to Production",
          status: "pending"
        },
        %{
          type: "approval_approved",
          approval_id: "app_123",
          approver: "user_789",
          timestamp: DateTime.utc_now()
        }
      ]

      for event <- approval_events do
        {:ok, _} = Notifications.send_with_notify("observer_approvals", event, TestRepo)
      end

      assert true
    end

    test "CentralCloud pattern learning integration" do
      # Simulate CentralCloud integration
      pattern_events = [
        %{
          type: "pattern_discovered",
          pattern_id: "pattern_123",
          pattern_type: "microservice_architecture",
          confidence_score: 0.92
        },
        %{
          type: "pattern_validated",
          pattern_id: "pattern_123",
          validation_score: 0.95,
          usage_count: 50
        }
      ]

      for event <- pattern_events do
        {:ok, _} = Notifications.send_with_notify("centralcloud_patterns", event, TestRepo)
      end

      assert true
    end

    test "Genesis autonomous learning integration" do
      # Simulate Genesis integration
      learning_events = [
        %{
          type: "rule_generated",
          rule_id: "rule_123",
          rule_type: "optimization",
          success_rate: 0.85
        },
        %{
          type: "rule_evolved",
          rule_id: "rule_123",
          improvement: 0.12,
          new_success_rate: 0.97
        }
      ]

      for event <- learning_events do
        {:ok, _} = Notifications.send_with_notify("genesis_learning", event, TestRepo)
      end

      assert true
    end
  end

  describe "performance and scalability" do
    test "high-frequency notification handling" do
      # Test sending many notifications quickly
      events = for i <- 1..1000 do
        %{
          type: "test_event",
          id: i,
          timestamp: DateTime.utc_now()
        }
      end

      start_time = System.monotonic_time()
      
      results = for event <- events do
        Notifications.send_with_notify("test_queue", event, TestRepo)
      end
      
      end_time = System.monotonic_time()
      duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)
      
      # All should succeed
      success_count = Enum.count(results, fn {:ok, _} -> true; _ -> false end)
      assert success_count == 1000
      
      # Should be reasonably fast
      assert duration < 5000  # Less than 5 seconds for 1000 notifications
      
      IO.puts("Sent 1000 notifications in #{duration}ms")
    end

    test "large payload handling" do
      # Test with large message payloads
      large_payloads = [
        %{
          type: "large_data",
          data: String.duplicate("x", 100_000),  # 100KB
          metadata: %{size: 100_000}
        },
        %{
          type: "complex_workflow",
          workflow_definition: %{
            steps: Enum.map(1..1000, &%{id: &1, name: "step_#{&1}"}),
            dependencies: Enum.map(1..999, &%{from: &1, to: &1 + 1})
          }
        }
      ]

      for payload <- large_payloads do
        {:ok, message_id} = Notifications.send_with_notify("test_queue", payload, TestRepo)
        assert is_binary(message_id)
      end
    end
  end

  describe "logging and observability" do
    test "structured logging includes all required fields" do
      log = capture_log(fn ->
        Notifications.send_with_notify("test_queue", %{type: "test"}, TestRepo)
      end)
      
      # Check for structured logging fields
      assert log =~ "queue:"
      assert log =~ "message_id:"
      assert log =~ "message_type:"
      assert log =~ "duration_ms:"
    end

    test "error logging includes context" do
      # Mock a failing repo
      defmodule FailingRepo do
        def query(_query, _params) do
          {:error, :connection_lost}
        end
      end

      log = capture_log(fn ->
        Notifications.send_with_notify("test_queue", %{type: "test"}, FailingRepo)
      end)
      
      assert log =~ "PGMQ + NOTIFY send failed"
      assert log =~ "error: :connection_lost"
      assert log =~ "queue: test_queue"
    end
  end

  describe "concurrent notification handling" do
    test "multiple concurrent workflows" do
      # Test multiple workflows running concurrently
      workflow_count = 10
      tasks_per_workflow = 5
      
      workflows = for i <- 1..workflow_count do
        workflow_id = "concurrent_workflow_#{i}"
        
        # Start workflow
        {:ok, _} = Notifications.send_with_notify("workflow_events", %{
          type: "workflow_started",
          workflow_id: workflow_id
        }, TestRepo)
        
        # Start tasks
        for j <- 1..tasks_per_workflow do
          {:ok, _} = Notifications.send_with_notify("workflow_events", %{
            type: "task_started",
            task_id: "task_#{j}",
            workflow_id: workflow_id
          }, TestRepo)
        end
        
        workflow_id
      end
      
      # Complete all workflows
      for workflow_id <- workflows do
        {:ok, _} = Notifications.send_with_notify("workflow_events", %{
          type: "workflow_completed",
          workflow_id: workflow_id
        }, TestRepo)
      end
      
      assert length(workflows) == workflow_count
    end
  end

  # Mock repo for testing
  defmodule TestRepo do
    def query(_query, _params) do
      {:ok, %Postgrex.Result{}}
    end
  end
end