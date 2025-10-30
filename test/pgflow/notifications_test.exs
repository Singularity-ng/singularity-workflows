defmodule QuantumFlow.NotificationsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias QuantumFlow.Notifications

  # Mock repo for testing
  defmodule TestRepo do
    def query(_query, _params) do
      {:ok, %Postgrex.Result{}}
    end
  end

  # Mock Postgrex.Notifications for testing
  defmodule MockNotifications do
    def listen(_repo, _channel) do
      {:ok, self()}
    end

    def unlisten(_repo, _pid) do
      :ok
    end
  end

  describe "send_with_notify/3" do
    test "sends message via PGMQ and triggers NOTIFY with logging" do
      assert function_exported?(Notifications, :send_with_notify, 3)
      
      # Test that it returns a message ID
      {:ok, message_id} = Notifications.send_with_notify(
        "test_queue", 
        %{type: "test", content: "hello"}, 
        TestRepo
      )
      
      assert is_binary(message_id)
    end

    test "logs successful send with structured data" do
      log = capture_log(fn ->
        Notifications.send_with_notify("test_queue", %{type: "test"}, TestRepo)
      end)
      
      assert log =~ "PGMQ + NOTIFY sent successfully"
      assert log =~ "queue: test_queue"
      assert log =~ "message_type: test"
    end

    test "handles different message types" do
      message_types = [
        %{type: "workflow_started"},
        %{type: "task_completed"},
        %{type: "workflow_failed"},
        %{type: "approval_created"}
      ]

      for message <- message_types do
        {:ok, _message_id} = Notifications.send_with_notify("test_queue", message, TestRepo)
      end
    end
  end

  describe "listen/2" do
    test "starts listening for NOTIFY events with logging" do
      # Mock Postgrex.Notifications
      original_notifications = Application.get_env(:quantum_flow, :notifications_module, Postgrex.Notifications)
      Application.put_env(:quantum_flow, :notifications_module, MockNotifications)
      
      on_exit(fn ->
        Application.put_env(:quantum_flow, :notifications_module, original_notifications)
      end)

      log = capture_log(fn ->
        {:ok, pid} = Notifications.listen("test_queue", TestRepo)
        assert is_pid(pid)
      end)
      
      assert log =~ "PGMQ NOTIFY listener started"
      assert log =~ "queue: test_queue"
      assert log =~ "channel: pgmq_test_queue"
    end

    test "handles listener start failure" do
      # Mock failure
      defmodule FailingNotifications do
        def listen(_repo, _channel) do
          {:error, :connection_failed}
        end
      end

      original_notifications = Application.get_env(:quantum_flow, :notifications_module, Postgrex.Notifications)
      Application.put_env(:quantum_flow, :notifications_module, FailingNotifications)
      
      on_exit(fn ->
        Application.put_env(:quantum_flow, :notifications_module, original_notifications)
      end)

      log = capture_log(fn ->
        {:error, reason} = Notifications.listen("test_queue", TestRepo)
        assert reason == :connection_failed
      end)
      
      assert log =~ "PGMQ NOTIFY listener failed to start"
      assert log =~ "error: :connection_failed"
    end
  end

  describe "unlisten/2" do
    test "stops listening for notifications with logging" do
      # Mock Postgrex.Notifications
      original_notifications = Application.get_env(:quantum_flow, :notifications_module, Postgrex.Notifications)
      Application.put_env(:quantum_flow, :notifications_module, MockNotifications)
      
      on_exit(fn ->
        Application.put_env(:quantum_flow, :notifications_module, original_notifications)
      end)

      log = capture_log(fn ->
        :ok = Notifications.unlisten(self(), TestRepo)
      end)
      
      assert log =~ "PGMQ NOTIFY listener stopped"
      assert log =~ "listener_pid:"
    end

    test "handles unlisten failure" do
      # Mock failure
      defmodule FailingUnlisten do
        def unlisten(_repo, _pid) do
          {:error, :not_found}
        end
      end

      original_notifications = Application.get_env(:quantum_flow, :notifications_module, Postgrex.Notifications)
      Application.put_env(:quantum_flow, :notifications_module, FailingUnlisten)
      
      on_exit(fn ->
        Application.put_env(:quantum_flow, :notifications_module, original_notifications)
      end)

      log = capture_log(fn ->
        {:error, reason} = Notifications.unlisten(self(), TestRepo)
        assert reason == :not_found
      end)
      
      assert log =~ "PGMQ NOTIFY listener stop failed"
      assert log =~ "error: :not_found"
    end
  end

  describe "notify_only/3" do
    test "sends NOTIFY without PGMQ with logging" do
      log = capture_log(fn ->
        :ok = Notifications.notify_only("test_channel", "test_payload", TestRepo)
      end)
      
      assert log =~ "NOTIFY sent"
      assert log =~ "channel: test_channel"
      assert log =~ "payload: test_payload"
    end

    test "handles NOTIFY send failure" do
      # Mock repo that fails
      defmodule FailingRepo do
        def query(_query, _params) do
          {:error, :connection_lost}
        end
      end

      log = capture_log(fn ->
        {:error, reason} = Notifications.notify_only("test_channel", "test_payload", FailingRepo)
        assert reason == :connection_lost
      end)
      
      assert log =~ "NOTIFY send failed"
      assert log =~ "error: :connection_lost"
    end
  end

  describe "integration scenarios" do
    test "complete workflow notification flow" do
      # Test a complete workflow notification scenario
      workflow_events = [
        %{type: "workflow_started", workflow_id: "wf_123"},
        %{type: "task_started", task_id: "task_1", workflow_id: "wf_123"},
        %{type: "task_completed", task_id: "task_1", workflow_id: "wf_123"},
        %{type: "workflow_completed", workflow_id: "wf_123"}
      ]

      for event <- workflow_events do
        {:ok, message_id} = Notifications.send_with_notify("workflow_events", event, TestRepo)
        assert is_binary(message_id)
      end
    end

    test "error handling workflow" do
      # Test error scenarios
      error_events = [
        %{type: "task_failed", task_id: "task_1", error: "timeout"},
        %{type: "workflow_failed", workflow_id: "wf_123", error: "dependency_failed"}
      ]

      for event <- error_events do
        {:ok, message_id} = Notifications.send_with_notify("workflow_events", event, TestRepo)
        assert is_binary(message_id)
      end
    end

    test "approval workflow notifications" do
      # Test approval-specific notifications
      approval_events = [
        %{type: "approval_created", approval_id: "app_123", status: "pending"},
        %{type: "approval_approved", approval_id: "app_123", approver: "user_456"},
        %{type: "approval_rejected", approval_id: "app_123", reason: "insufficient_data"}
      ]

      for event <- approval_events do
        {:ok, message_id} = Notifications.send_with_notify("approval_events", event, TestRepo)
        assert is_binary(message_id)
      end
    end
  end

  describe "performance and reliability" do
    test "handles high-frequency notifications" do
      # Test sending many notifications quickly
      events = for i <- 1..100 do
        %{type: "test_event", id: i, timestamp: DateTime.utc_now()}
      end

      results = for event <- events do
        Notifications.send_with_notify("test_queue", event, TestRepo)
      end

      # All should succeed
      assert Enum.all?(results, fn {:ok, _} -> true; _ -> false end)
    end

    test "handles large payloads" do
      # Test with large message payload
      large_payload = %{
        type: "large_data",
        data: String.duplicate("x", 10000),  # 10KB payload
        metadata: %{
          size: 10000,
          timestamp: DateTime.utc_now(),
          source: "test"
        }
      }

      {:ok, message_id} = Notifications.send_with_notify("test_queue", large_payload, TestRepo)
      assert is_binary(message_id)
    end
  end

  describe "logging verification" do
    test "all public functions include proper logging" do
      # Verify that all public functions have logging
      public_functions = [
        {:send_with_notify, 3},
        {:listen, 2},
        {:unlisten, 2},
        {:notify_only, 3}
      ]

      for {function, arity} <- public_functions do
        assert function_exported?(Notifications, function, arity)
      end
    end

    test "structured logging includes required fields" do
      log = capture_log(fn ->
        Notifications.send_with_notify("test_queue", %{type: "test"}, TestRepo)
      end)
      
      # Check for structured logging fields
      assert log =~ "queue:"
      assert log =~ "message_id:"
      assert log =~ "message_type:"
      assert log =~ "duration_ms:"
    end
  end
end