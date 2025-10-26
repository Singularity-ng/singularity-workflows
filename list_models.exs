#!/usr/bin/env elixir

# Models Directory Listing Script
# Uses ex_llm to list models from providers and optimizes using YAML configuration

Mix.install([
  {:ex_llm, path: "../../packages/ex_llm"}
])

defmodule ModelsDirectory do
  @moduledoc """
  Models directory listing and optimization using ex_llm and YAML configuration.
  
  This script demonstrates how to:
  1. List all available models from ex_llm providers
  2. Use YAML configuration for optimization
  3. Show model capabilities, pricing, and context windows
  4. Provide intelligent model recommendations
  """

  alias ExLLM.Core.Models
  alias ExLLM.Infrastructure.Config.ModelConfig

  def run do
    IO.puts("🤖 ExLLM Models Directory Listing")
    IO.puts("=" |> String.duplicate(50))
    IO.puts()

    # List all models
    case Models.list_all() do
      {:ok, models} ->
        IO.puts("📊 Found #{length(models)} models across all providers")
        IO.puts()

        # Group by provider
        grouped_models = Enum.group_by(models, & &1.provider)

        # Show summary by provider
        show_provider_summary(grouped_models)

        # Show detailed models
        show_detailed_models(grouped_models)

        # Show optimization recommendations
        show_optimization_recommendations(models)

      {:error, reason} ->
        IO.puts("❌ Error listing models: #{inspect(reason)}")
    end
  end

  defp show_provider_summary(grouped_models) do
    IO.puts("📈 Provider Summary:")
    IO.puts("-" |> String.duplicate(30))

    grouped_models
    |> Enum.sort_by(fn {_provider, models} -> length(models) end, :desc)
    |> Enum.each(fn {provider, models} ->
      total_cost = calculate_total_cost(models)
      capabilities = extract_all_capabilities(models)
      
      IO.puts("  #{provider |> Atom.to_string() |> String.upcase()}")
      IO.puts("    Models: #{length(models)}")
      IO.puts("    Avg Cost: $#{total_cost / length(models) |> Float.round(2)}/1M tokens")
      IO.puts("    Capabilities: #{capabilities |> Enum.join(", ")}")
      IO.puts()
    end)
  end

  defp show_detailed_models(grouped_models) do
    IO.puts("🔍 Detailed Model Information:")
    IO.puts("-" |> String.duplicate(40))

    grouped_models
    |> Enum.sort_by(fn {provider, _models} -> provider end)
    |> Enum.each(fn {provider, models} ->
      IO.puts("\n#{provider |> Atom.to_string() |> String.upcase()}:")
      
      models
      |> Enum.sort_by(& &1.id)
      |> Enum.each(fn model ->
        show_model_details(model)
      end)
    end)
  end

  defp show_model_details(model) do
    pricing = model.pricing || %{}
    input_cost = Map.get(pricing, :input, 0)
    output_cost = Map.get(pricing, :output, 0)
    context_window = model.context_window || "Unknown"
    capabilities = model.capabilities || []
    
    IO.puts("  📋 #{model.id}")
    IO.puts("     Context: #{format_number(context_window)} tokens")
    IO.puts("     Pricing: $#{input_cost}/$#{output_cost} (input/output per 1M)")
    IO.puts("     Capabilities: #{capabilities |> Enum.join(", ")}")
    
    if model.description do
      IO.puts("     Description: #{model.description}")
    end
    
    IO.puts()
  end

  defp show_optimization_recommendations(models) do
    IO.puts("💡 Optimization Recommendations:")
    IO.puts("-" |> String.duplicate(35))

    # Find cheapest models
    cheapest_models = find_cheapest_models(models)
    IO.puts("💰 Cheapest Models (per 1M input tokens):")
    cheapest_models
    |> Enum.take(5)
    |> Enum.each(fn {model, cost} ->
      IO.puts("  • #{model.id} (#{model.provider}): $#{cost}")
    end)

    IO.puts()

    # Find models with largest context windows
    largest_context = find_largest_context_models(models)
    IO.puts("🧠 Largest Context Windows:")
    largest_context
    |> Enum.take(5)
    |> Enum.each(fn {model, context} ->
      IO.puts("  • #{model.id} (#{model.provider}): #{format_number(context)} tokens")
    end)

    IO.puts()

    # Find models by capabilities
    show_capability_recommendations(models)
  end

  defp show_capability_recommendations(models) do
    capabilities = [:vision, :function_calling, :streaming, :reasoning, :web_search]
    
    capabilities
    |> Enum.each(fn capability ->
      matching_models = Enum.filter(models, fn model ->
        capability in (model.capabilities || [])
      end)
      
      if length(matching_models) > 0 do
        cheapest = matching_models
        |> Enum.min_by(fn model ->
          model.pricing[:input] || Float.infinity()
        end)
        
        IO.puts("🎯 Best for #{capability}:")
        IO.puts("  • #{cheapest.id} (#{cheapest.provider}) - $#{cheapest.pricing[:input]}/1M tokens")
      end
    end)
  end

  defp find_cheapest_models(models) do
    models
    |> Enum.filter(fn model -> model.pricing && model.pricing[:input] end)
    |> Enum.sort_by(fn model -> model.pricing[:input] end)
    |> Enum.map(fn model -> {model, model.pricing[:input]} end)
  end

  defp find_largest_context_models(models) do
    models
    |> Enum.filter(fn model -> is_integer(model.context_window) end)
    |> Enum.sort_by(& &1.context_window, :desc)
    |> Enum.map(fn model -> {model, model.context_window} end)
  end

  defp calculate_total_cost(models) do
    models
    |> Enum.filter(fn model -> model.pricing && model.pricing[:input] end)
    |> Enum.map(fn model -> model.pricing[:input] end)
    |> Enum.sum()
  end

  defp extract_all_capabilities(models) do
    models
    |> Enum.flat_map(fn model -> model.capabilities || [] end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.replace(~r/(\d)(?=(\d{3})+(?!\d))/, "\\1,")
  end

  defp format_number(num), do: to_string(num)
end

# Run the script
ModelsDirectory.run()