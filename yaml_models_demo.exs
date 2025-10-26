#!/usr/bin/env elixir

# YAML Models Demo Script
# Demonstrates ex_llm YAML configuration without live provider connections

Mix.install([
  {:ex_llm, path: "../../packages/ex_llm"}
])

defmodule YAMLModelsDemo do
  def run do
    IO.puts("📋 ExLLM YAML Models Configuration Demo")
    IO.puts("=" |> String.duplicate(45))
    IO.puts("")

    # List available providers from YAML files
    show_available_providers()

    # Show model configurations
    show_model_configurations()

    # Demonstrate optimization strategies
    demonstrate_optimization_strategies()
  end

  defp show_available_providers do
    IO.puts("🏢 Available Providers (from YAML configs):")
    IO.puts("-" |> String.duplicate(40))

    providers = [
      :anthropic, :openai, :gemini, :groq, :mistral, 
      :openrouter, :perplexity, :xai, :ollama, :lmstudio, 
      :bedrock, :bumblebee
    ]

    providers
    |> Enum.each(fn provider ->
      case ExLLM.Infrastructure.Config.ModelConfig.get_all_models(provider) do
        %{} = models when map_size(models) > 0 ->
          model_count = map_size(models)
          case ExLLM.Infrastructure.Config.ModelConfig.get_default_model(provider) do
            {:ok, default} ->
              IO.puts("  ✅ #{provider}: #{model_count} models (default: #{default})")
            {:error, _} ->
              IO.puts("  ✅ #{provider}: #{model_count} models (no default)")
          end

        _ ->
          IO.puts("  ❌ #{provider}: No models configured")
      end
    end)
    IO.puts("")
  end

  defp show_model_configurations do
    IO.puts("🔍 Model Configuration Examples:")
    IO.puts("-" |> String.duplicate(35))

    # Show Anthropic models
    show_provider_models(:anthropic, "Anthropic Claude")

    # Show OpenAI models  
    show_provider_models(:openai, "OpenAI GPT")

    # Show Gemini models
    show_provider_models(:gemini, "Google Gemini")
  end

  defp show_provider_models(provider, display_name) do
    models = ExLLM.Infrastructure.Config.ModelConfig.get_all_models(provider)
    
    if map_size(models) > 0 do
      IO.puts("\n#{display_name} Models:")
      
      models
      |> Enum.take(5)  # Show first 5 models
      |> Enum.each(fn {model_id, config} ->
        pricing = config[:pricing] || %{}
        context_window = config[:context_window] || "Unknown"
        capabilities = config[:capabilities] || []
        
        IO.puts("  📋 #{model_id}")
        IO.puts("     Context: #{format_number(context_window)} tokens")
        IO.puts("     Cost: $#{pricing[:input] || 0}/$#{pricing[:output] || 0} (input/output per 1M)")
        IO.puts("     Capabilities: #{capabilities |> Enum.take(3) |> Enum.join(", ")}")
      end)

      if map_size(models) > 5 do
        IO.puts("     ... and #{map_size(models) - 5} more models")
      end
    else
      IO.puts("\n#{display_name}: No models configured")
    end
  end

  defp demonstrate_optimization_strategies do
    IO.puts("\n💡 YAML-Based Optimization Strategies:")
    IO.puts("-" |> String.duplicate(40))

    # Cost optimization example
    show_cost_optimization()

    # Capability optimization example
    show_capability_optimization()

    # Context window optimization example
    show_context_optimization()
  end

  defp show_cost_optimization do
    IO.puts("\n💰 Cost Optimization Example:")
    IO.puts("Finding cheapest models across all providers...")

    all_models = get_all_models_with_pricing()
    
    if length(all_models) > 0 do
      cheapest = all_models |> Enum.min_by(fn {_model, cost} -> cost end)
      {model_info, cost} = cheapest
      
      IO.puts("  🏆 Cheapest: #{model_info.id} (#{model_info.provider})")
      IO.puts("     Cost: $#{cost}/1M input tokens")
    else
      IO.puts("  No models with pricing information found")
    end
  end

  defp show_capability_optimization do
    IO.puts("\n🎯 Capability Optimization Example:")
    IO.puts("Finding models with vision and function calling...")

    vision_models = find_models_with_capabilities([:vision, :function_calling])
    
    if length(vision_models) > 0 do
      IO.puts("  Found #{length(vision_models)} models with vision + function calling:")
      vision_models
      |> Enum.take(3)
      |> Enum.each(fn model ->
        pricing = model.pricing || %{}
        IO.puts("    • #{model.id} (#{model.provider}) - $#{pricing[:input] || 0}/1M tokens")
      end)
    else
      IO.puts("  No models found with both vision and function calling")
    end
  end

  defp show_context_optimization do
    IO.puts("\n🧠 Context Window Optimization Example:")
    IO.puts("Finding models with largest context windows...")

    large_context_models = find_models_with_large_context(100_000)
    
    if length(large_context_models) > 0 do
      IO.puts("  Found #{length(large_context_models)} models with 100K+ context:")
      large_context_models
      |> Enum.take(3)
      |> Enum.each(fn model ->
        IO.puts("    • #{model.id} (#{model.provider}) - #{format_number(model.context_window)} tokens")
      end)
    else
      IO.puts("  No models found with 100K+ context window")
    end
  end

  # Helper functions

  defp get_all_models_with_pricing do
    providers = [:anthropic, :openai, :gemini, :groq, :mistral]
    
    providers
    |> Enum.flat_map(fn provider ->
      models = ExLLM.Infrastructure.Config.ModelConfig.get_all_models(provider)
      
      models
      |> Enum.map(fn {model_id, config} ->
        pricing = config[:pricing] || %{}
        input_cost = pricing[:input]
        
        if input_cost do
          model_info = %{
            id: model_id,
            provider: provider,
            pricing: pricing,
            context_window: config[:context_window],
            capabilities: config[:capabilities] || []
          }
          {model_info, input_cost}
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    end)
  end

  defp find_models_with_capabilities(required_capabilities) do
    providers = [:anthropic, :openai, :gemini, :groq, :mistral]
    
    providers
    |> Enum.flat_map(fn provider ->
      models = ExLLM.Infrastructure.Config.ModelConfig.get_all_models(provider)
      
      models
      |> Enum.map(fn {model_id, config} ->
        capabilities = config[:capabilities] || []
        
        if Enum.all?(required_capabilities, fn cap -> cap in capabilities end) do
          %{
            id: model_id,
            provider: provider,
            pricing: config[:pricing] || %{},
            context_window: config[:context_window],
            capabilities: capabilities
          }
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    end)
  end

  defp find_models_with_large_context(min_context) do
    providers = [:anthropic, :openai, :gemini, :groq, :mistral]
    
    providers
    |> Enum.flat_map(fn provider ->
      models = ExLLM.Infrastructure.Config.ModelConfig.get_all_models(provider)
      
      models
      |> Enum.map(fn {model_id, config} ->
        context_window = config[:context_window]
        
        if is_integer(context_window) and context_window >= min_context do
          %{
            id: model_id,
            provider: provider,
            pricing: config[:pricing] || %{},
            context_window: context_window,
            capabilities: config[:capabilities] || []
          }
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    end)
    |> Enum.sort_by(& &1.context_window, :desc)
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.replace(~r/(\d)(?=(\d{3})+(?!\d))/, "\\1,")
  end

  defp format_number(num), do: to_string(num)
end

# Run the demo
YAMLModelsDemo.run()