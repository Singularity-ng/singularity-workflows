#!/usr/bin/env elixir

# Direct YAML Demo Script
# Directly reads and parses YAML files to demonstrate model optimization

Mix.install([
  {:yaml_elixir, "~> 2.12"}
])

defmodule DirectYAMLDemo do
  def run do
    IO.puts("📋 Direct YAML Models Configuration Demo")
    IO.puts("=" |> String.duplicate(40))
    IO.puts("")

    # Find YAML files
    yaml_dir = "../../packages/ex_llm/config/models"
    
    if File.exists?(yaml_dir) do
      show_yaml_files(yaml_dir)
      demonstrate_yaml_parsing(yaml_dir)
      show_optimization_examples(yaml_dir)
    else
      IO.puts("❌ YAML directory not found: #{yaml_dir}")
    end
  end

  defp show_yaml_files(yaml_dir) do
    IO.puts("📁 Available YAML Configuration Files:")
    IO.puts("-" |> String.duplicate(35))

    yaml_files = File.ls!(yaml_dir)
    |> Enum.filter(&String.ends_with?(&1, ".yml"))
    |> Enum.sort()

    yaml_files
    |> Enum.each(fn file ->
      file_path = Path.join(yaml_dir, file)
      case File.stat(file_path) do
        {:ok, %{size: size}} ->
          IO.puts("  📄 #{file} (#{format_file_size(size)})")
        {:error, _} ->
          IO.puts("  ❌ #{file} (error reading)")
      end
    end)
    IO.puts("")
  end

  defp demonstrate_yaml_parsing(yaml_dir) do
    IO.puts("🔍 YAML Parsing Examples:")
    IO.puts("-" |> String.duplicate(30))

    # Parse Anthropic config
    parse_provider_config(yaml_dir, "anthropic.yml", "Anthropic Claude")
    
    # Parse OpenAI config
    parse_provider_config(yaml_dir, "openai.yml", "OpenAI GPT")
    
    # Parse Gemini config
    parse_provider_config(yaml_dir, "gemini.yml", "Google Gemini")
  end

  defp parse_provider_config(yaml_dir, filename, display_name) do
    file_path = Path.join(yaml_dir, filename)
    
    case File.read(file_path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, config} ->
            IO.puts("\n#{display_name} Configuration:")
            
            # Show provider info
            provider = config["provider"] || "unknown"
            default_model = config["default_model"] || "none"
            IO.puts("  Provider: #{provider}")
            IO.puts("  Default Model: #{default_model}")
            
            # Show models
            models = config["models"] || %{}
            model_count = map_size(models)
            IO.puts("  Models: #{model_count}")
            
            if model_count > 0 do
              IO.puts("  Sample models:")
              models
              |> Enum.take(3)
              |> Enum.each(fn {model_id, model_config} ->
                context_window = model_config["context_window"] || "Unknown"
                pricing = model_config["pricing"] || %{}
                input_cost = pricing["input"] || 0
                output_cost = pricing["output"] || 0
                capabilities = model_config["capabilities"] || []
                
                IO.puts("    • #{model_id}")
                IO.puts("      Context: #{format_number(context_window)} tokens")
                IO.puts("      Cost: $#{input_cost}/$#{output_cost} (input/output per 1M)")
                IO.puts("      Capabilities: #{capabilities |> Enum.take(3) |> Enum.join(", ")}")
              end)
              
              if model_count > 3 do
                IO.puts("      ... and #{model_count - 3} more models")
              end
            end

          {:error, reason} ->
            IO.puts("\n#{display_name}: Error parsing YAML - #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("\n#{display_name}: Error reading file - #{inspect(reason)}")
    end
  end

  defp show_optimization_examples(yaml_dir) do
    IO.puts("\n💡 YAML-Based Optimization Examples:")
    IO.puts("-" |> String.duplicate(35))

    # Load all models from YAML files
    all_models = load_all_models_from_yaml(yaml_dir)
    
    if length(all_models) > 0 do
      IO.puts("📊 Loaded #{length(all_models)} models from YAML files")
      
      # Cost optimization
      show_cost_analysis(all_models)
      
      # Capability analysis
      show_capability_analysis(all_models)
      
      # Context window analysis
      show_context_analysis(all_models)
      
      # Provider comparison
      show_provider_comparison(all_models)
    else
      IO.puts("❌ No models loaded from YAML files")
    end
  end

  defp load_all_models_from_yaml(yaml_dir) do
    yaml_files = File.ls!(yaml_dir)
    |> Enum.filter(&String.ends_with?(&1, ".yml"))
    
    yaml_files
    |> Enum.flat_map(fn filename ->
      file_path = Path.join(yaml_dir, filename)
      
      case File.read(file_path) do
        {:ok, content} ->
          case YamlElixir.read_from_string(content) do
            {:ok, config} ->
              provider = config["provider"] || filename |> String.replace(".yml", "")
              models = config["models"] || %{}
              
              models
              |> Enum.map(fn {model_id, model_config} ->
                %{
                  id: model_id,
                  provider: provider,
                  context_window: model_config["context_window"],
                  max_output_tokens: model_config["max_output_tokens"],
                  pricing: model_config["pricing"] || %{},
                  capabilities: model_config["capabilities"] || [],
                  deprecation_date: model_config["deprecation_date"]
                }
              end)
              
            {:error, _} ->
              []
          end
          
        {:error, _} ->
          []
      end
    end)
  end

  defp show_cost_analysis(models) do
    IO.puts("\n💰 Cost Analysis:")
    
    models_with_pricing = models
    |> Enum.filter(fn model -> 
      pricing = model.pricing
      pricing["input"] && is_number(pricing["input"])
    end)
    
    if length(models_with_pricing) > 0 do
      costs = models_with_pricing |> Enum.map(fn m -> m.pricing["input"] end)
      min_cost = Enum.min(costs)
      max_cost = Enum.max(costs)
      avg_cost = Enum.sum(costs) / length(costs)
      
      cheapest = models_with_pricing |> Enum.min_by(fn m -> m.pricing["input"] end)
      
      IO.puts("  Cheapest: #{cheapest.id} (#{cheapest.provider}) - $#{cheapest.pricing["input"]}/1M tokens")
      IO.puts("  Most expensive: $#{max_cost}/1M tokens")
      IO.puts("  Average: $#{Float.round(avg_cost, 2)}/1M tokens")
      IO.puts("  Total models with pricing: #{length(models_with_pricing)}")
    else
      IO.puts("  No models with pricing information found")
    end
  end

  defp show_capability_analysis(models) do
    IO.puts("\n🎯 Capability Analysis:")
    
    all_capabilities = models
    |> Enum.flat_map(& &1.capabilities)
    |> Enum.uniq()
    |> Enum.sort()
    
    IO.puts("  Available capabilities: #{all_capabilities |> Enum.join(", ")}")
    
    # Count models by capability
    capability_counts = all_capabilities
    |> Enum.map(fn capability ->
      count = models |> Enum.count(fn m -> capability in m.capabilities end)
      {capability, count}
    end)
    |> Enum.sort_by(fn {_cap, count} -> count end, :desc)
    
    IO.puts("  Capability distribution:")
    capability_counts
    |> Enum.take(5)
    |> Enum.each(fn {capability, count} ->
      IO.puts("    #{capability}: #{count} models")
    end)
  end

  defp show_context_analysis(models) do
    IO.puts("\n🧠 Context Window Analysis:")
    
    models_with_context = models
    |> Enum.filter(fn model -> is_integer(model.context_window) end)
    
    if length(models_with_context) > 0 do
      contexts = models_with_context |> Enum.map(& &1.context_window)
      min_context = Enum.min(contexts)
      max_context = Enum.max(contexts)
      avg_context = Enum.sum(contexts) / length(contexts)
      
      largest = models_with_context |> Enum.max_by(& &1.context_window)
      
      IO.puts("  Largest: #{largest.id} (#{largest.provider}) - #{format_number(largest.context_window)} tokens")
      IO.puts("  Smallest: #{format_number(min_context)} tokens")
      IO.puts("  Average: #{format_number(round(avg_context))} tokens")
      IO.puts("  Total models with context info: #{length(models_with_context)}")
    else
      IO.puts("  No models with context window information found")
    end
  end

  defp show_provider_comparison(models) do
    IO.puts("\n🏢 Provider Comparison:")
    
    grouped = models |> Enum.group_by(& &1.provider)
    
    grouped
    |> Enum.sort_by(fn {_provider, models} -> length(models) end, :desc)
    |> Enum.each(fn {provider, provider_models} ->
      model_count = length(provider_models)
      models_with_pricing = provider_models |> Enum.filter(fn m -> m.pricing["input"] end)
      avg_cost = if length(models_with_pricing) > 0 do
        costs = models_with_pricing |> Enum.map(fn m -> m.pricing["input"] end)
        Float.round(Enum.sum(costs) / length(costs), 2)
      else
        "N/A"
      end
      
      IO.puts("  #{provider}: #{model_count} models, avg cost: $#{avg_cost}/1M tokens")
    end)
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.replace(~r/(\d)(?=(\d{3})+(?!\d))/, "\\1,")
  end

  defp format_number(num), do: to_string(num)

  defp format_file_size(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{Float.round(bytes / (1024 * 1024), 1)} MB"
    end
  end
end

# Run the demo
DirectYAMLDemo.run()