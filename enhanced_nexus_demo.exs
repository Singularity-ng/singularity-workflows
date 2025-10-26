#!/usr/bin/env elixir

# Enhanced Nexus Demo Script
# Demonstrates the new model optimization, monitoring, and discovery features

Mix.install([
  {:ex_llm, path: "../../packages/ex_llm"}
])

defmodule EnhancedNexusDemo do
  def run do
    IO.puts("🚀 Enhanced Nexus LLM Router Demo")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("")

    # Start the demo
    start_demo()
  end

  defp start_demo do
    IO.puts("📋 Demo Overview:")
    IO.puts("-" |> String.duplicate(20))
    IO.puts("This demo shows the enhanced Nexus LLM Router with:")
    IO.puts("  ✅ YAML-based model optimization")
    IO.puts("  ✅ Performance monitoring and analytics")
    IO.puts("  ✅ Dynamic model discovery")
    IO.puts("  ✅ Cost-aware routing")
    IO.puts("  ✅ Capability-based model selection")
    IO.puts("  ✅ Intelligent fallback chains")
    IO.puts("")

    # Simulate the enhanced features
    demonstrate_model_optimization()
    demonstrate_performance_monitoring()
    demonstrate_dynamic_discovery()
    demonstrate_enhanced_routing()
    demonstrate_analytics()
  end

  defp demonstrate_model_optimization do
    IO.puts("🎯 Model Optimization Demo:")
    IO.puts("-" |> String.duplicate(30))

    # Simulate model optimization scenarios
    scenarios = [
      %{
        name: "Cost-Optimized Simple Task",
        complexity: :simple,
        requirements: %{max_cost: 1.0},
        description: "Find cheapest model for simple tasks"
      },
      %{
        name: "Performance-Optimized Complex Task",
        complexity: :complex,
        requirements: %{min_context: 100_000, capabilities: [:reasoning]},
        description: "Find high-performance model for complex reasoning"
      },
      %{
        name: "Vision + Function Calling Task",
        complexity: :medium,
        requirements: %{capabilities: [:vision, :function_calling]},
        description: "Find model with specific capabilities"
      }
    ]

    scenarios
    |> Enum.each(fn scenario ->
      IO.puts("\n  📋 #{scenario.name}:")
      IO.puts("    #{scenario.description}")
      
      # Simulate optimization results
      recommendations = simulate_model_optimization(scenario)
      
      IO.puts("    🎯 Recommended models:")
      recommendations
      |> Enum.take(3)
      |> Enum.each(fn model ->
        IO.puts("      • #{model.id} (#{model.provider})")
        IO.puts("        Cost: $#{model.pricing[:input] || 0}/1M tokens")
        IO.puts("        Context: #{format_number(model.context_window || 0)} tokens")
        IO.puts("        Capabilities: #{model.capabilities |> Enum.take(3) |> Enum.join(", ")}")
        IO.puts("        Optimization Score: #{Float.round(model.optimization_score || 0, 2)}")
      end)
    end)
  end

  defp demonstrate_performance_monitoring do
    IO.puts("\n📊 Performance Monitoring Demo:")
    IO.puts("-" |> String.duplicate(35))

    # Simulate monitoring data
    monitoring_data = %{
      total_requests: 1250,
      success_rate: 0.94,
      total_cost: 45.67,
      avg_response_time: 2.3,
      most_used_models: [
        %{model_id: "claude-3-5-sonnet-20241022", requests: 450, cost: 18.50},
        %{model_id: "gpt-4o", requests: 320, cost: 12.30},
        %{model_id: "gemini-2.0-flash-exp", requests: 280, cost: 2.10}
      ],
      provider_breakdown: [
        %{provider: "anthropic", requests: 450, cost: 18.50, percentage: 0.36},
        %{provider: "openai", requests: 320, cost: 12.30, percentage: 0.26},
        %{provider: "gemini", requests: 280, cost: 2.10, percentage: 0.22}
      ]
    }

    IO.puts("  📈 Overall Metrics:")
    IO.puts("    Total Requests: #{monitoring_data.total_requests}")
    IO.puts("    Success Rate: #{(monitoring_data.success_rate * 100) |> Float.round(1)}%")
    IO.puts("    Total Cost: $#{monitoring_data.total_cost}")
    IO.puts("    Avg Response Time: #{monitoring_data.avg_response_time}s")

    IO.puts("\n  🏆 Most Used Models:")
    monitoring_data.most_used_models
    |> Enum.each(fn model ->
      IO.puts("    • #{model.model_id}: #{model.requests} requests, $#{model.cost}")
    end)

    IO.puts("\n  🏢 Provider Breakdown:")
    monitoring_data.provider_breakdown
    |> Enum.each(fn provider ->
      percentage = (provider.percentage * 100) |> Float.round(1)
      IO.puts("    • #{provider.provider}: #{provider.requests} requests (#{percentage}%), $#{provider.cost}")
    end)
  end

  defp demonstrate_dynamic_discovery do
    IO.puts("\n🔍 Dynamic Model Discovery Demo:")
    IO.puts("-" |> String.duplicate(35))

    # Simulate discovery results
    discovery_results = %{
      providers_discovered: 7,
      total_models: 1247,
      new_models_found: 23,
      discovery_status: %{
        anthropic: %{status: :success, models: 19, last_updated: "2 minutes ago"},
        openai: %{status: :success, models: 110, last_updated: "5 minutes ago"},
        gemini: %{status: :success, models: 42, last_updated: "3 minutes ago"},
        groq: %{status: :success, models: 29, last_updated: "1 minute ago"},
        mistral: %{status: :success, models: 29, last_updated: "4 minutes ago"},
        perplexity: %{status: :error, error: "API rate limit", last_updated: "10 minutes ago"},
        xai: %{status: :success, models: 26, last_updated: "6 minutes ago"}
      }
    }

    IO.puts("  📊 Discovery Summary:")
    IO.puts("    Providers Discovered: #{discovery_results.providers_discovered}")
    IO.puts("    Total Models: #{discovery_results.total_models}")
    IO.puts("    New Models Found: #{discovery_results.new_models_found}")

    IO.puts("\n  🔄 Provider Status:")
    discovery_results.discovery_status
    |> Enum.each(fn {provider, status} ->
      case status.status do
        :success ->
          IO.puts("    ✅ #{provider}: #{status.models} models (#{status.last_updated})")
        :error ->
          IO.puts("    ❌ #{provider}: Error - #{status.error} (#{status.last_updated})")
      end
    end)

    # Simulate model availability check
    IO.puts("\n  🔍 Model Availability Check:")
    availability_example = %{
      model_id: "claude-3-5-sonnet-20241022",
      available: true,
      providers: [:anthropic],
      alternatives: [
        %{model_id: "claude-3-5-sonnet-latest", provider: :anthropic, similarity: 0.95},
        %{model_id: "gpt-4o", provider: :openai, similarity: 0.78}
      ]
    }

    IO.puts("    Model: #{availability_example.model_id}")
    IO.puts("    Available: #{if availability_example.available, do: "✅ Yes", else: "❌ No"}")
    IO.puts("    Providers: #{availability_example.providers |> Enum.join(", ")}")
    IO.puts("    Alternatives:")
    availability_example.alternatives
    |> Enum.each(fn alt ->
      IO.puts("      • #{alt.model_id} (#{alt.provider}) - #{Float.round(alt.similarity, 2)} similarity")
    end)
  end

  defp demonstrate_enhanced_routing do
    IO.puts("\n🚀 Enhanced Routing Demo:")
    IO.puts("-" |> String.duplicate(30))

    # Simulate routing scenarios
    routing_scenarios = [
      %{
        name: "Simple Task (Cost-Optimized)",
        request: %{
          complexity: :simple,
          messages: [%{role: "user", content: "Classify this text"}],
          requirements: %{max_cost: 1.0}
        },
        result: %{
          selected_model: "gemini-2.0-flash-exp",
          provider: :gemini,
          cost: 0.075,
          optimization_score: 0.92,
          response_time: 1.2
        }
      },
      %{
        name: "Complex Architecture Task",
        request: %{
          complexity: :complex,
          messages: [%{role: "user", content: "Design a microservices architecture"}],
          task_type: :architect,
          requirements: %{capabilities: [:reasoning, :function_calling]}
        },
        result: %{
          selected_model: "claude-3-5-sonnet-20241022",
          provider: :anthropic,
          cost: 3.0,
          optimization_score: 0.88,
          response_time: 3.5
        }
      },
      %{
        name: "Vision Task with Fallback",
        request: %{
          complexity: :medium,
          messages: [%{role: "user", content: "Analyze this image"}],
          task_type: :vision,
          requirements: %{capabilities: [:vision]}
        },
        result: %{
          selected_model: "gpt-4o",
          provider: :openai,
          cost: 2.5,
          optimization_score: 0.85,
          response_time: 2.8,
          fallback_used: false
        }
      }
    ]

    routing_scenarios
    |> Enum.each(fn scenario ->
      IO.puts("\n  📋 #{scenario.name}:")
      IO.puts("    Request: #{scenario.request.messages |> hd() |> Map.get(:content)}")
      IO.puts("    Complexity: #{scenario.request.complexity}")
      IO.puts("    Requirements: #{inspect(scenario.request.requirements)}")
      
      result = scenario.result
      IO.puts("\n    🎯 Routing Result:")
      IO.puts("      Selected Model: #{result.selected_model} (#{result.provider})")
      IO.puts("      Cost: $#{result.cost}/1M tokens")
      IO.puts("      Optimization Score: #{Float.round(result.optimization_score, 2)}")
      IO.puts("      Response Time: #{result.response_time}s")
      
      if result.fallback_used do
        IO.puts("      ⚠️  Fallback Used: Yes")
      end
    end)
  end

  defp demonstrate_analytics do
    IO.puts("\n📈 Analytics Dashboard Demo:")
    IO.puts("-" |> String.duplicate(35))

    # Simulate analytics data
    analytics = %{
      cost_trends: %{
        daily_spending: [2.1, 3.4, 2.8, 4.2, 3.9, 2.7, 3.1],
        weekly_average: 3.2,
        monthly_projection: 96.0
      },
      performance_metrics: %{
        avg_response_time: 2.3,
        success_rate: 0.94,
        error_rate: 0.06,
        timeout_rate: 0.02
      },
      model_recommendations: [
        %{
          use_case: "High-volume text processing",
          recommended_model: "gemini-2.0-flash-exp",
          cost_savings: "75%",
          reason: "Cheapest model with good performance"
        },
        %{
          use_case: "Complex reasoning tasks",
          recommended_model: "claude-3-5-sonnet-20241022",
          cost_savings: "15%",
          reason: "Best cost-performance ratio for reasoning"
        }
      ],
      alerts: [
        %{type: :cost, message: "Daily spending exceeded budget by 20%", severity: :warning},
        %{type: :performance, message: "Response time increased by 15%", severity: :info}
      ]
    }

    IO.puts("  💰 Cost Trends:")
    IO.puts("    Daily Spending: $#{analytics.cost_trends.daily_spending |> Enum.join(", $")}")
    IO.puts("    Weekly Average: $#{analytics.cost_trends.weekly_average}")
    IO.puts("    Monthly Projection: $#{analytics.cost_trends.monthly_projection}")

    IO.puts("\n  ⚡ Performance Metrics:")
    IO.puts("    Avg Response Time: #{analytics.performance_metrics.avg_response_time}s")
    IO.puts("    Success Rate: #{(analytics.performance_metrics.success_rate * 100) |> Float.round(1)}%")
    IO.puts("    Error Rate: #{(analytics.performance_metrics.error_rate * 100) |> Float.round(1)}%")
    IO.puts("    Timeout Rate: #{(analytics.performance_metrics.timeout_rate * 100) |> Float.round(1)}%")

    IO.puts("\n  💡 Model Recommendations:")
    analytics.model_recommendations
    |> Enum.each(fn rec ->
      IO.puts("    • #{rec.use_case}")
      IO.puts("      Recommended: #{rec.recommended_model}")
      IO.puts("      Cost Savings: #{rec.cost_savings}")
      IO.puts("      Reason: #{rec.reason}")
    end)

    IO.puts("\n  🚨 Alerts:")
    analytics.alerts
    |> Enum.each(fn alert ->
      severity_icon = case alert.severity do
        :warning -> "⚠️"
        :error -> "❌"
        :info -> "ℹ️"
      end
      IO.puts("    #{severity_icon} #{alert.message}")
    end)
  end

  defp simulate_model_optimization(scenario) do
    # Simulate optimization results based on scenario
    case scenario.complexity do
      :simple ->
        [
          %{
            id: "gemini-2.0-flash-exp",
            provider: :gemini,
            pricing: %{input: 0.075},
            context_window: 1048576,
            capabilities: [:streaming, :function_calling, :vision],
            optimization_score: 0.95
          },
          %{
            id: "gpt-4o-mini",
            provider: :openai,
            pricing: %{input: 0.15},
            context_window: 128000,
            capabilities: [:streaming, :function_calling],
            optimization_score: 0.88
          }
        ]
      :medium ->
        [
          %{
            id: "claude-3-5-sonnet-20241022",
            provider: :anthropic,
            pricing: %{input: 3.0},
            context_window: 200000,
            capabilities: [:streaming, :function_calling, :vision, :reasoning],
            optimization_score: 0.92
          },
          %{
            id: "gpt-4o",
            provider: :openai,
            pricing: %{input: 2.5},
            context_window: 128000,
            capabilities: [:streaming, :function_calling, :vision],
            optimization_score: 0.85
          }
        ]
      :complex ->
        [
          %{
            id: "claude-3-5-sonnet-20241022",
            provider: :anthropic,
            pricing: %{input: 3.0},
            context_window: 200000,
            capabilities: [:streaming, :function_calling, :vision, :reasoning],
            optimization_score: 0.94
          },
          %{
            id: "gpt-4o",
            provider: :openai,
            pricing: %{input: 2.5},
            context_window: 128000,
            capabilities: [:streaming, :function_calling, :vision],
            optimization_score: 0.87
          }
        ]
    end
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.replace(~r/(\d)(?=(\d{3})+(?!\d))/, "\\1,")
  end

  defp format_number(num), do: to_string(num)
end

# Run the demo
EnhancedNexusDemo.run()