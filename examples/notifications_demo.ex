#!/usr/bin/env elixir

# Pgflow.Notifications Demo
# Demonstrates real-time notification capabilities with comprehensive logging
# Run with: elixir examples/notifications_demo.ex

# This demo shows how to use Pgflow.Notifications for real-time workflow events
# with structured logging and error handling.

defmodule NotificationsDemo do
  @moduledoc """
  Comprehensive demo of Pgflow.Notifications functionality.
  
  This demo shows:
  - Sending workflow events with NOTIFY
  - Listening for real-time events
  - Structured logging for debugging
  - Error handling and recovery
  - Integration patterns
  """

  require Logger

  # Mock repo for demo
  defmodule DemoRepo do
    def query(_query, _params) do
      {:ok, %Postgrex.Result{}}
    end
  end

  def run do
    IO.puts("🚀 Pgflow.Notifications Demo")
    IO.puts("=" |> String.duplicate(50))
    
    # Start the demo
    setup_demo()
    |> send_workflow_events()
    |> demonstrate_listening()
    |> show_error_handling()
    |> demonstrate_integration_patterns()
    |> cleanup_demo()
    
    IO.puts("\n✅ Demo completed successfully!")
  end

  defp setup_demo do
    IO.puts("\n📋 Setting up demo environment...")
    
    # Configure logging for demo
    Logger.configure(level: :info)
    
    IO.puts("✅ Demo environment ready")
    %{repo: DemoRepo}
  end

  defp send_workflow_events(context) do
    IO.puts("\n📤 Sending workflow events...")
    
    # Simulate a complete workflow execution
    workflow_events = [
      %{
        type: "workflow_started",
        workflow_id: "demo_workflow_#{System.unique_integer([:positive])}",
        input: %{data: "demo_data"},
        timestamp: DateTime.utc_now()
      },
      %{
        type: "task_started",
        task_id: "task_1",
        workflow_id: "demo_workflow",
        step_name: "data_processing",
        timestamp: DateTime.utc_now()
      },
      %{
        type: "task_completed",
        task_id: "task_1",
        workflow_id: "demo_workflow",
        result: %{processed: true, count: 100},
        duration_ms: 1500,
        timestamp: DateTime.utc_now()
      },
      %{
        type: "workflow_completed",
        workflow_id: "demo_workflow",
        final_result: %{success: true, processed_items: 100},
        total_duration_ms: 3000,
        timestamp: DateTime.utc_now()
      }
    ]

    # Send each event with NOTIFY
    for event <- workflow_events do
      IO.puts("  📨 Sending: #{event.type}")
      
      case Pgflow.Notifications.send_with_notify("workflow_events", event, context.repo) do
        {:ok, message_id} ->
          IO.puts("    ✅ Sent successfully (ID: #{message_id})")
        {:error, reason} ->
          IO.puts("    ❌ Failed: #{inspect(reason)}")
      end
      
      # Small delay to show timing
      Process.sleep(100)
    end

    context
  end

  defp demonstrate_listening(context) do
    IO.puts("\n👂 Demonstrating event listening...")
    
    # Show how to set up a listener (in real app, this would be in a GenServer)
    IO.puts("  📡 Setting up NOTIFY listener...")
    
    case Pgflow.Notifications.listen("workflow_events", context.repo) do
      {:ok, listener_pid} ->
        IO.puts("    ✅ Listener started (PID: #{inspect(listener_pid)})")
        
        # In a real application, you would handle notifications like this:
        IO.puts("  💡 In a real app, you would handle notifications like:")
        IO.puts("    receive do")
        IO.puts("      {:notification, ^listener_pid, channel, message_id} ->")
        IO.puts("        Logger.info(\"Received notification: #{channel} -> #{message_id}\")")
        IO.puts("        # Process the notification...")
        IO.puts("    end")
        
        # Clean up listener
        Pgflow.Notifications.unlisten(listener_pid, context.repo)
        IO.puts("    🧹 Listener cleaned up")
        
      {:error, reason} ->
        IO.puts("    ❌ Failed to start listener: #{inspect(reason)}")
    end

    context
  end

  defp show_error_handling(context) do
    IO.puts("\n⚠️  Demonstrating error handling...")
    
    # Show error scenarios
    error_events = [
      %{
        type: "task_failed",
        task_id: "task_2",
        workflow_id: "demo_workflow",
        error: "Connection timeout",
        retry_count: 3,
        timestamp: DateTime.utc_now()
      },
      %{
        type: "workflow_failed",
        workflow_id: "demo_workflow",
        error: "Dependency failed",
        failed_task: "task_2",
        timestamp: DateTime.utc_now()
      }
    ]

    for event <- error_events do
      IO.puts("  🚨 Sending error event: #{event.type}")
      
      case Pgflow.Notifications.send_with_notify("workflow_events", event, context.repo) do
        {:ok, message_id} ->
          IO.puts("    ✅ Error event sent (ID: #{message_id})")
        {:error, reason} ->
          IO.puts("    ❌ Failed to send error event: #{inspect(reason)}")
      end
    end

    context
  end

  defp demonstrate_integration_patterns(context) do
    IO.puts("\n🔗 Demonstrating integration patterns...")
    
    # Show different integration scenarios
    integration_scenarios = [
      {
        "Observer Web UI Integration",
        fn ->
          # Simulate Observer integration
          approval_event = %{
            type: "approval_created",
            approval_id: "app_#{System.unique_integer([:positive])}",
            request_id: "req_123",
            title: "Deploy to Production",
            description: "Deploy version 1.2.3 to production environment",
            status: "pending",
            requester: "user_456",
            timestamp: DateTime.utc_now()
          }
          
          Pgflow.Notifications.send_with_notify("observer_approvals", approval_event, context.repo)
        end
      },
      {
        "CentralCloud Pattern Learning",
        fn ->
          # Simulate CentralCloud integration
          pattern_event = %{
            type: "pattern_learned",
            pattern_id: "pattern_#{System.unique_integer([:positive])}",
            pattern_type: "microservice_architecture",
            confidence_score: 0.95,
            usage_count: 150,
            source: "workflow_execution",
            timestamp: DateTime.utc_now()
          }
          
          Pgflow.Notifications.send_with_notify("centralcloud_patterns", pattern_event, context.repo)
        end
      },
      {
        "Genesis Autonomous Learning",
        fn ->
          # Simulate Genesis integration
          learning_event = %{
            type: "rule_evolved",
            rule_id: "rule_#{System.unique_integer([:positive])}",
            rule_type: "optimization",
            old_rule: "retry_3_times",
            new_rule: "retry_5_times_with_backoff",
            success_rate_improvement: 0.15,
            timestamp: DateTime.utc_now()
          }
          
          Pgflow.Notifications.send_with_notify("genesis_learning", learning_event, context.repo)
        end
      }
    ]

    for {scenario_name, send_fn} <- integration_scenarios do
      IO.puts("  🔄 #{scenario_name}...")
      
      case send_fn.() do
        {:ok, message_id} ->
          IO.puts("    ✅ Integration event sent (ID: #{message_id})")
        {:error, reason} ->
          IO.puts("    ❌ Integration failed: #{inspect(reason)}")
      end
    end

    context
  end

  defp cleanup_demo(context) do
    IO.puts("\n🧹 Cleaning up demo...")
    IO.puts("  ✅ Demo cleanup completed")
    context
  end
end

# Run the demo
if __FILE__ == Path.expand(__FILE__) do
  NotificationsDemo.run()
end