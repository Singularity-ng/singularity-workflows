defmodule Observer.DashboardMock do
  @moduledoc """
  Mock implementation of Observer.Dashboard for testing.

  This module provides a mock implementation that can be used in tests
  to control the behavior of dashboard data fetching without requiring
  the actual Singularity modules to be available.
  """

  @behaviour Observer.DashboardBehaviour

  @impl true
  def agent_performance do
    {:ok, %{
      total_agents: 5,
      active_agents: 3,
      success_rate: 0.92,
      avg_response_time: 1200
    }}
  end

  @impl true
  def code_quality do
    {:ok, %{
      overall_score: 0.88,
      issues_found: 12,
      critical_issues: 2,
      warnings: 10
    }}
  end

  @impl true
  def cost_analysis do
    {:ok, %{
      total_cost: 125.50,
      cost_trend: :increasing,
      top_provider: "anthropic",
      daily_average: 15.75
    }}
  end

  @impl true
  def rule_evolution do
    {:ok, %{
      total_rules: 25,
      active_rules: 20,
      rules_evolved: 3,
      success_rate: 0.95
    }}
  end

  @impl true
  def task_execution do
    {:ok, %{
      total_tasks: 150,
      completed_tasks: 142,
      failed_tasks: 8,
      success_rate: 0.947
    }}
  end

  @impl true
  def knowledge_base do
    {:ok, %{
      total_artifacts: 500,
      recent_artifacts: 25,
      search_queries: 1200,
      hit_rate: 0.85
    }}
  end

  @impl true
  def llm_health do
    {:ok, %{
      provider_health: %{
        overall_health: :healthy,
        providers: [
          %{name: "anthropic", status: :healthy},
          %{name: "openai", status: :healthy},
          %{name: "google", status: :warning}
        ]
      },
      performance: %{
        total_requests_per_minute: 45,
        average_error_rate: 0.02
      }
    }}
  end

  @impl true
  def validation_metrics do
    {:ok, %{
      kpis: %{
        accuracy: 0.92,
        execution_success_rate: 0.88,
        average_validation_time_ms: 150
      }
    }}
  end

  @impl true
  def validation_metrics_store do
    {:ok, %{
      validation_accuracy: 0.92,
      execution_success_rate: 0.88,
      avg_validation_time: 150,
      effectiveness_scores: %{
        "template_check" => 0.95,
        "quality_check" => 0.87,
        "security_check" => 0.91
      },
      aggregated_metrics: [
        %{
          model: "claude-3-5-sonnet",
          count: 25,
          cost_cents: 1250,
          avg_latency_ms: 1800,
          success_rate: 0.92
        }
      ]
    }}
  end

  @impl true
  def failure_patterns do
    {:ok, %{
      top_patterns: [
        %{
          failure_mode: "validation_error",
          total_frequency: 15,
          story_types: ["architect", "coder"],
          last_seen_at: DateTime.utc_now() |> DateTime.add(-1, :hour)
        }
      ],
      recent_failures: [
        %{
          failure_mode: "validation_error",
          story_type: "architect",
          frequency: 3,
          root_cause: "Invalid input parameters",
          execution_error: "Parameter validation failed",
          last_seen_at: DateTime.utc_now() |> DateTime.add(-30, :minute)
        }
      ],
      successful_fixes: [
        %{
          description: "Added input validation for required fields",
          applied_at: DateTime.utc_now() |> DateTime.add(-1, :day)
        }
      ]
    }}
  end

  @impl true
  def adaptive_threshold do
    {:ok, %{
      status: %{
        current_threshold: 0.85,
        actual_success_rate: 0.92,
        adjustment_direction: :increasing,
        convergence_status: :converged
      },
      convergence: %{
        iterations: 15,
        stability: 0.95
      }
    }}
  end

  @impl true
  def system_health do
    {:ok, %{
      llm: llm_health(),
      validation: validation_metrics(),
      adaptive_threshold: adaptive_threshold(),
      task_execution: task_execution(),
      cost: cost_analysis()
    }}
  end
end