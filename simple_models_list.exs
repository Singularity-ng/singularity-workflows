#!/usr/bin/env elixir

# Simple Models Listing Script
# Quick demonstration of ex_llm model listing capabilities

Mix.install([
  {:ex_llm, path: "../../packages/ex_llm"}
])

defmodule SimpleModelsList do
  def run do
    IO.puts("🤖 ExLLM Simple Models List")
    IO.puts("=" |> String.duplicate(30))
    IO.puts("")

    # List all models
    case ExLLM.Core.Models.list_all() do
      {:ok, models} ->
        IO.puts("Found #{length(models)} models")
        IO.puts("")

        # Group by provider
        grouped = Enum.group_by(models, & &1.provider)
        
        # Show each provider
        grouped
        |> Enum.sort_by(fn {provider, _models} -> provider end)
        |> Enum.each(fn {provider, provider_models} ->
          IO.puts("#{provider |> Atom.to_string() |> String.upcase()}:")
          
          provider_models
          |> Enum.take(5)  # Show first 5 models
          |> Enum.each(fn model ->
            pricing = model.pricing || %{}
            input_cost = pricing[:input] || 0
            context_window = model.context_window || "Unknown"
            
            IO.puts("  • #{model.id}")
            IO.puts("    Cost: $#{input_cost}/1M | Context: #{context_window}")
          end)
          
          if length(provider_models) > 5 do
            IO.puts("  ... and #{length(provider_models) - 5} more")
          end
          IO.puts("")
        end)

        # Show some statistics
        show_statistics(models)

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end

  defp show_statistics(models) do
    IO.puts("📊 Statistics:")
    IO.puts("-" |> String.duplicate(20))

    # Count by provider
    provider_counts = models |> Enum.group_by(& &1.provider) |> Enum.map(fn {k, v} -> {k, length(v)} end)
    
    IO.puts("Models per provider:")
    provider_counts
    |> Enum.sort_by(fn {_provider, count} -> count end, :desc)
    |> Enum.each(fn {provider, count} ->
      IO.puts("  #{provider}: #{count}")
    end)

    # Cost analysis
    models_with_pricing = Enum.filter(models, fn model -> model.pricing && model.pricing[:input] end)
    
    if length(models_with_pricing) > 0 do
      costs = Enum.map(models_with_pricing, fn model -> model.pricing[:input] end)
      min_cost = Enum.min(costs)
      max_cost = Enum.max(costs)
      avg_cost = Enum.sum(costs) / length(costs)
      
      IO.puts("\nCost analysis:")
      IO.puts("  Cheapest: $#{min_cost}/1M tokens")
      IO.puts("  Most expensive: $#{max_cost}/1M tokens") 
      IO.puts("  Average: $#{Float.round(avg_cost, 2)}/1M tokens")
    end

    # Context window analysis
    models_with_context = Enum.filter(models, fn model -> is_integer(model.context_window) end)
    
    if length(models_with_context) > 0 do
      contexts = Enum.map(models_with_context, & &1.context_window)
      min_context = Enum.min(contexts)
      max_context = Enum.max(contexts)
      
      IO.puts("\nContext window analysis:")
      IO.puts("  Smallest: #{format_number(min_context)} tokens")
      IO.puts("  Largest: #{format_number(max_context)} tokens")
    end
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.replace(~r/(\d)(?=(\d{3})+(?!\d))/, "\\1,")
  end
end

# Run the script
SimpleModelsList.run()