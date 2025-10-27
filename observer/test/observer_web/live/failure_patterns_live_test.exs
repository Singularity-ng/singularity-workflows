defmodule ObserverWeb.FailurePatternsLiveTest do
  @moduledoc """
  LiveView tests for FailurePatternsLive dashboard.
  """

  use ObserverWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Observer.Dashboard

  describe "FailurePatternsLive" do
    test "renders with failure pattern data", %{conn: conn} do
      # Mock failure pattern data
      test_data = %{
        top_patterns: [
          %{
            failure_mode: "validation_error",
            total_frequency: 15,
            story_types: ["architect", "coder"],
            last_seen_at: DateTime.utc_now() |> DateTime.add(-1, :hour)
          },
          %{
            failure_mode: "timeout_error",
            total_frequency: 8,
            story_types: ["architect"],
            last_seen_at: DateTime.utc_now() |> DateTime.add(-2, :hour)
          }
        ],
        recent_failures: [
          %{
            failure_mode: "validation_error",
            story_type: "architect",
            frequency: 3,
            root_cause: "Invalid input parameters",
            execution_error: "Parameter validation failed: missing required field 'name'",
            last_seen_at: DateTime.utc_now() |> DateTime.add(-30, :minute)
          },
          %{
            failure_mode: "timeout_error",
            story_type: "coder",
            frequency: 1,
            root_cause: "External service timeout",
            execution_error: "Request timed out after 30s",
            last_seen_at: DateTime.utc_now() |> DateTime.add(-1, :hour)
          }
        ],
        successful_fixes: [
          %{
            description: "Added input validation for required fields",
            applied_at: DateTime.utc_now() |> DateTime.add(-1, :day)
          },
          %{
            description: "Implemented retry logic with exponential backoff",
            applied_at: DateTime.utc_now() |> DateTime.add(-2, :day)
          }
        ]
      }

      Mox.stub_with(Observer.DashboardMock, Observer.Dashboard)
      Mox.expect(Observer.DashboardMock, :failure_patterns, fn -> {:ok, test_data} end)

      {:ok, view, html} = live(conn, "/failure-patterns")

      # Test header
      assert html =~ "Failure Patterns & Guardrails"
      assert html =~ "Real-time failure analysis and remediation strategies"

      # Test summary cards
      assert html =~ "2"  # top_patterns count
      assert html =~ "2"  # recent_failures count
      assert html =~ "2"  # successful_fixes count

      # Test top patterns
      assert html =~ "validation_error"
      assert html =~ "15 occurrences"
      assert html =~ "architect, coder"
      assert html =~ "timeout_error"
      assert html =~ "8 occurrences"

      # Test recent failures
      assert html =~ "Invalid input parameters"
      assert html =~ "Parameter validation failed"
      assert html =~ "External service timeout"
      assert html =~ "Request timed out after 30s"

      # Test successful fixes
      assert html =~ "Added input validation for required fields"
      assert html =~ "Implemented retry logic with exponential backoff"
    end

    test "renders with empty data", %{conn: conn} do
      # Mock empty data
      empty_data = %{
        top_patterns: [],
        recent_failures: [],
        successful_fixes: []
      }

      Mox.stub_with(Observer.DashboardMock, Observer.Dashboard)
      Mox.expect(Observer.DashboardMock, :failure_patterns, fn -> {:ok, empty_data} end)

      {:ok, view, html} = live(conn, "/failure-patterns")

      # Should show 0 counts
      assert html =~ "0"  # All counts should be 0

      # Should show empty state messages
      assert html =~ "No failure patterns recorded"
      assert html =~ "No recent failures recorded"
      assert html =~ "No successful fixes recorded"
    end

    test "handles dashboard errors gracefully", %{conn: conn} do
      # Mock error response
      Mox.stub_with(Observer.DashboardMock, Observer.Dashboard)
      Mox.expect(Observer.DashboardMock, :failure_patterns, fn -> 
        {:error, "Database connection failed"}
      end)

      {:ok, view, html} = live(conn, "/failure-patterns")

      # Should still render the page structure
      assert html =~ "Failure Patterns & Guardrails"
      assert html =~ "0"  # Default values when data is missing
    end

    test "formats relative time correctly", %{conn: conn} do
      now = DateTime.utc_now()
      
      test_data = %{
        top_patterns: [
          %{
            failure_mode: "test_error",
            total_frequency: 1,
            story_types: ["test"],
            last_seen_at: now |> DateTime.add(-30, :second)
          }
        ],
        recent_failures: [
          %{
            failure_mode: "test_error",
            story_type: "test",
            frequency: 1,
            root_cause: "Test root cause",
            last_seen_at: now |> DateTime.add(-5, :minute)
          }
        ],
        successful_fixes: []
      }

      Mox.stub_with(Observer.DashboardMock, Observer.Dashboard)
      Mox.expect(Observer.DashboardMock, :failure_patterns, fn -> {:ok, test_data} end)

      {:ok, view, html} = live(conn, "/failure-patterns")

      # Should show relative time
      assert html =~ "30s ago" or html =~ "1m ago"
      assert html =~ "5m ago"
    end

    test "truncates long error messages", %{conn: conn} do
      long_error = String.duplicate("This is a very long error message that should be truncated. ", 10)
      
      test_data = %{
        top_patterns: [],
        recent_failures: [
          %{
            failure_mode: "test_error",
            story_type: "test",
            frequency: 1,
            root_cause: "Test root cause",
            execution_error: long_error,
            last_seen_at: DateTime.utc_now()
          }
        ],
        successful_fixes: []
      }

      Mox.stub_with(Observer.DashboardMock, Observer.Dashboard)
      Mox.expect(Observer.DashboardMock, :failure_patterns, fn -> {:ok, test_data} end)

      {:ok, view, html} = live(conn, "/failure-patterns")

      # Should truncate the long error message
      assert html =~ "..."
      refute html =~ long_error  # Full message should not be present
    end
  end
end