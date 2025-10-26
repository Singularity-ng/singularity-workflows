#!/usr/bin/env elixir

# Advanced Models Optimization Script
# Demonstrates YAML-based optimization strategies using ex_llm

Mix.install([
  {:ex_llm, path: "../../packages/ex_llm"}
])

defmodule ModelsOptimizer do
  @moduledoc """
  Advanced models optimization using ex_llm YAML configuration.
  
  This script demonstrates:
  1. YAML-based model selection strategies
  2. Cost optimization algorithms
  3. Capability-based filtering
  4. Performance vs cost trade-offs
  5. Provider-specific optimizations
  """

  alias ExLLM.Core.Models
  alias ExLLM.Infrastructure.Config.ModelConfig

  # Optimization strategies
  @strategies %{
    cost_optimized: "Minimize cost while meeting requirements",
    performance_optimized: "Maximize performance regardless of cost", 
    balanced: "Balance cost and performance",
    capability_optimized: "Maximize capabilities for specific use case"
  }

  def run do
    IO.puts("🚀 ExLLM Models Optimization Engine")
    IO.puts("=" |> String.duplicate(50))
    IO.puts()

    case Models.list_all() do
      {:ok, models} ->
        IO.puts("📊 Analyzing #{length(models)} models...")
        IO.puts()

        # Show optimization strategies
        show_optimization_strategies()

        # Demonstrate different optimization approaches
        demonstrate_optimizations(models)

        # Show provider-specific optimizations
        show_provider_optimizations()

        # Interactive model selection
        interactive_model_selection(models)

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end

  defp show_optimization_strategies do
    IO.puts("🎯 Available Optimization Strategies:")
    IO.puts("-" |> String.duplicate(40))

    @strategies
    |> Enum.each(fn {strategy, description} ->
      IO.puts("  #{strategy |> Atom.to_string() |> String.upcase()}")
      IO.puts("    #{description}")
      IO.puts()
    end)
  end

  defp demonstrate_optimizations(models) do
    IO.puts("🔬 Optimization Demonstrations:")
    IO.puts("-" |> String.duplicate(35))

    # Cost optimization
    cost_optimized = optimize_for_cost(models, max_cost: 5.0)
    IO.puts("💰 Cost Optimized (max $5/1M input tokens):")
    show_model_recommendations(cost_optimized, 3)

    # Performance optimization  
    performance_optimized = optimize_for_performance(models, min_context: 100_000)
    IO.puts("\n⚡ Performance Optimized (min 100K context):")
    show_model_recommendations(performance_optimized, 3)

    # Capability optimization
    vision_optimized = optimize_for_capabilities(models, [:vision, :function_calling])
    IO.puts("\n👁️ Vision + Function Calling Optimized:")
    show_model_recommendations(vision_optimized, 3)

    # Balanced optimization
    balanced = optimize_balanced(models, cost_weight: 0.6, performance_weight: 0.4)
    IO.puts("\n⚖️ Balanced Optimization (60% cost, 40% performance):")
    show_model_recommendations(balanced, 3)
  end

  defp show_provider_optimizations do
    IO.puts("\n🏢 Provider-Specific Optimizations:")
    IO.puts("-" |> String.duplicate(40))

    providers = [:anthropic, :openai, :gemini, :groq, :mistral]

    providers
    |> Enum.each(fn provider ->
      case ModelConfig.get_default_model(provider) do
        {:ok, default_model} ->
          case ModelConfig.get_model_config(provider, default_model) do
            nil ->
              IO.puts("  #{provider}: No configuration available")
            config ->
              show_provider_analysis(provider, default_model, config)
          end
        {:error, _} ->
          IO.puts("  #{provider}: No default model configured")
      end
    end)
  end

  defp show_provider_analysis(provider, default_model, config) do
    pricing = config[:pricing] || %{}
    context_window = config[:context_window] || "Unknown"
    capabilities = config[:capabilities] || []
    
    IO.puts("  #{provider |> Atom.to_string() |> String.upcase()}:")
    IO.puts("    Default: #{default_model}")
    IO.puts("    Context: #{format_number(context_window)} tokens")
    IO.puts("    Cost: $#{pricing[:input] || 0}/$#{pricing[:output] || 0} (input/output)")
    IO.puts("    Capabilities: #{capabilities |> Enum.join(", ")}")
    
    # Provider-specific recommendations
    recommendations = get_provider_recommendations(provider, config)
    if recommendations != [] do
      IO.puts("    💡 Recommendations: #{recommendations |> Enum.join(", ")}")
    end
    IO.puts()
  end

  defp get_provider_recommendations(provider, config) do
    recommendations = []
    
    # Cost-based recommendations
    pricing = config[:pricing] || %{}
    input_cost = pricing[:input] || 0
    
    recommendations = 
      if input_cost < 1.0 do
        ["Great for high-volume tasks"] ++ recommendations
      else
        recommendations
      end

    # Capability-based recommendations
    capabilities = config[:capabilities] || []
    
    recommendations = 
      if :vision in capabilities do
        ["Perfect for image analysis"] ++ recommendations
      else
        recommendations
      end

    recommendations = 
      if :function_calling in capabilities do
        ["Ideal for tool integration"] ++ recommendations
      else
        recommendations
      end

    recommendations = 
      if :reasoning in capabilities do
        ["Excellent for complex reasoning"] ++ recommendations
      else
        recommendations
      end

    recommendations
  end

  defp interactive_model_selection(models) do
    IO.puts("\n🎮 Interactive Model Selection:")
    IO.puts("-" |> String.duplicate(35))
    IO.puts("Enter your requirements (or 'quit' to exit):")
    IO.puts()

    # Simulate some common use cases
    use_cases = [
      %{
        name: "Simple text classification",
        requirements: %{max_cost: 1.0, capabilities: [:streaming]},
        description: "Low-cost model for basic text processing"
      },
      %{
        name: "Code generation with tools",
        requirements: %{capabilities: [:function_calling, :streaming], min_context: 50_000},
        description: "Model that can generate code and use tools"
      },
      %{
        name: "Image analysis and reasoning",
        requirements: %{capabilities: [:vision, :reasoning], min_context: 100_000},
        description: "Advanced model for complex visual reasoning"
      },
      %{
        name: "High-volume data processing",
        requirements: %{max_cost: 0.5, capabilities: [:streaming]},
        description: "Very cheap model for processing large amounts of data"
      }
    ]

    use_cases
    |> Enum.each(fn use_case ->
      IO.puts("📋 #{use_case.name}:")
      IO.puts("   #{use_case.description}")
      
      recommendations = find_models_for_requirements(models, use_case.requirements)
      
      if recommendations != [] do
        IO.puts("   🎯 Recommended models:")
        recommendations
        |> Enum.take(3)
        |> Enum.each(fn model ->
          cost = model.pricing[:input] || 0
          IO.puts("     • #{model.id} (#{model.provider}) - $#{cost}/1M tokens")
        end)
      else
        IO.puts("   ❌ No models match these requirements")
      end
      IO.puts()
    end)
  end

  # Optimization functions

  defp optimize_for_cost(models, opts) do
    max_cost = Keyword.get(opts, :max_cost, Float.infinity())
    
    models
    |> Enum.filter(fn model ->
      pricing = model.pricing || %{}
      input_cost = pricing[:input] || Float.infinity()
      input_cost <= max_cost
    end)
    |> Enum.sort_by(fn model ->
      model.pricing[:input] || Float.infinity()
    end)
  end

  defp optimize_for_performance(models, opts) do
    min_context = Keyword.get(opts, :min_context, 0)
    
    models
    |> Enum.filter(fn model ->
      context_window = model.context_window || 0
      is_integer(context_window) and context_window >= min_context
    end)
    |> Enum.sort_by(& &1.context_window, :desc)
  end

  defp optimize_for_capabilities(models, required_capabilities) do
    models
    |> Enum.filter(fn model ->
      model_capabilities = model.capabilities || []
      Enum.all?(required_capabilities, fn cap -> cap in model_capabilities end)
    end)
    |> Enum.sort_by(fn model ->
      # Sort by number of capabilities (more capabilities = better)
      -(model.capabilities || [] |> length())
    end)
  end

  defp optimize_balanced(models, opts) do
    cost_weight = Keyword.get(opts, :cost_weight, 0.5)
    performance_weight = Keyword.get(opts, :performance_weight, 0.5)
    
    models
    |> Enum.map(fn model ->
      cost_score = calculate_cost_score(model)
      performance_score = calculate_performance_score(model)
      
      combined_score = cost_weight * cost_score + performance_weight * performance_score
      
      {model, combined_score}
    end)
    |> Enum.sort_by(fn {_model, score} -> -score end)
    |> Enum.map(fn {model, _score} -> model end)
  end

  defp find_models_for_requirements(models, requirements) do
    models
    |> Enum.filter(fn model ->
      # Check cost requirements
      max_cost = Map.get(requirements, :max_cost, Float.infinity())
      pricing = model.pricing || %{}
      input_cost = pricing[:input] || Float.infinity()
      
      cost_ok = input_cost <= max_cost
      
      # Check capability requirements
      required_capabilities = Map.get(requirements, :capabilities, [])
      model_capabilities = model.capabilities || []
      capabilities_ok = Enum.all?(required_capabilities, fn cap -> cap in model_capabilities end)
      
      # Check context requirements
      min_context = Map.get(requirements, :min_context, 0)
      context_window = model.context_window || 0
      context_ok = is_integer(context_window) and context_window >= min_context
      
      cost_ok and capabilities_ok and context_ok
    end)
    |> Enum.sort_by(fn model ->
      # Sort by cost (cheapest first)
      model.pricing[:input] || Float.infinity()
    end)
  end

  defp calculate_cost_score(model) do
    pricing = model.pricing || %{}
    input_cost = pricing[:input] || Float.infinity()
    
    # Lower cost = higher score (inverted)
    if input_cost == Float.infinity() do
      0.0
    else
      1.0 / (1.0 + input_cost)
    end
  end

  defp calculate_performance_score(model) do
    context_window = model.context_window || 0
    capabilities = model.capabilities || []
    
    # Higher context window and more capabilities = higher score
    context_score = if is_integer(context_window) do
      min(context_window / 1_000_000, 1.0)  # Normalize to 0-1
    else
      0.0
    end
    
    capability_score = min(length(capabilities) / 10.0, 1.0)  # Normalize to 0-1
    
    (context_score + capability_score) / 2.0
  end

  defp show_model_recommendations(models, count) do
    models
    |> Enum.take(count)
    |> Enum.each(fn model ->
      pricing = model.pricing || %{}
      input_cost = pricing[:input] || 0
      context_window = model.context_window || "Unknown"
      capabilities = model.capabilities || []
      
      IO.puts("  • #{model.id} (#{model.provider})")
      IO.puts("    Cost: $#{input_cost}/1M tokens | Context: #{format_number(context_window)} | Capabilities: #{capabilities |> Enum.take(3) |> Enum.join(", ")}")
    end)
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.replace(~r/(\d)(?=(\d{3})+(?!\d))/, "\\1,")
  end

  defp format_number(num), do: to_string(num)
end

# Run the optimizer
ModelsOptimizer.run()