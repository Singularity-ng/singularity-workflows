# ExLLM Models Directory Scripts

This directory contains scripts that demonstrate how to use `ex_llm` to list and optimize models from various LLM providers using YAML configuration.

## Scripts Overview

### 1. `simple_models_list.exs` - Basic Model Listing
**Purpose:** Quick demonstration of ex_llm model listing capabilities

**Features:**
- Lists all available models from all providers
- Groups models by provider
- Shows basic statistics (cost, context window)
- Provider counts and cost analysis

**Usage:**
```bash
elixir simple_models_list.exs
```

### 2. `list_models.exs` - Comprehensive Model Directory
**Purpose:** Detailed model listing with optimization insights

**Features:**
- Complete model information display
- Provider summaries with cost analysis
- Capability-based recommendations
- Cheapest models identification
- Largest context window models
- Capability-specific recommendations

**Usage:**
```bash
elixir list_models.exs
```

### 3. `optimize_models.exs` - Advanced Optimization Engine
**Purpose:** Demonstrates YAML-based optimization strategies

**Features:**
- Multiple optimization strategies (cost, performance, balanced, capability)
- Provider-specific analysis and recommendations
- Interactive model selection for use cases
- Cost vs performance trade-off analysis
- Capability-based filtering

**Usage:**
```bash
elixir optimize_models.exs
```

## How It Works

### YAML Configuration
The scripts leverage ex_llm's YAML configuration system located in `../packages/ex_llm/config/models/`:

- **Provider-specific files:** `anthropic.yml`, `openai.yml`, `gemini.yml`, etc.
- **Model definitions:** Context windows, pricing, capabilities, deprecation dates
- **Optimization data:** Cost per 1M tokens, capability flags, performance metrics

### ExLLM Integration
The scripts use ex_llm's core modules:

```elixir
# List all models
ExLLM.Core.Models.list_all()

# Get model details
ExLLM.Core.Models.get_info(:anthropic, "claude-3-5-sonnet-20241022")

# Find by capabilities
ExLLM.Core.Models.find_by_capabilities([:vision, :streaming])

# Find by cost range
ExLLM.Core.Models.find_by_cost_range(input: {0, 5.0}, output: {0, 20.0})
```

### Optimization Strategies

#### 1. Cost Optimization
- Filters models by maximum cost per 1M tokens
- Sorts by input cost (cheapest first)
- Identifies best value models

#### 2. Performance Optimization
- Filters by minimum context window size
- Sorts by context window (largest first)
- Considers capability richness

#### 3. Balanced Optimization
- Combines cost and performance scores
- Weighted scoring system
- Configurable cost/performance ratio

#### 4. Capability Optimization
- Filters by required capabilities
- Sorts by capability count
- Use-case specific recommendations

## Example Output

### Simple List
```
🤖 ExLLM Simple Models List
==============================

Found 150+ models

ANTHROPIC:
  • claude-3-5-sonnet-20241022
    Cost: $3.0/1M | Context: 200,000
  • claude-3-5-haiku-20241022
    Cost: $0.8/1M | Context: 200,000
  ...

OPENAI:
  • gpt-4o
    Cost: $2.5/1M | Context: 128,000
  • gpt-4o-mini
    Cost: $0.15/1M | Context: 128,000
  ...
```

### Optimization Results
```
💰 Cost Optimized (max $5/1M input tokens):
  • gpt-4o-mini (openai)
    Cost: $0.15/1M tokens | Context: 128,000 | Capabilities: streaming, function_calling
  • claude-3-5-haiku-20241022 (anthropic)
    Cost: $0.8/1M tokens | Context: 200,000 | Capabilities: streaming, function_calling, vision

⚡ Performance Optimized (min 100K context):
  • claude-3-5-sonnet-20241022 (anthropic)
    Cost: $3.0/1M tokens | Context: 200,000 | Capabilities: streaming, function_calling, vision, reasoning
  • gpt-4o (openai)
    Cost: $2.5/1M tokens | Context: 128,000 | Capabilities: streaming, function_calling, vision
```

## Use Cases

### 1. Model Selection for Applications
```elixir
# Find cheapest model with vision capability
{:ok, models} = ExLLM.Core.Models.find_by_capabilities([:vision])
cheapest_vision = models |> Enum.min_by(fn m -> m.pricing[:input] || Float.infinity() end)
```

### 2. Cost Analysis
```elixir
# Analyze cost distribution
{:ok, models} = ExLLM.Core.Models.list_all()
costs = models |> Enum.map(fn m -> m.pricing[:input] end) |> Enum.reject(&is_nil/1)
avg_cost = Enum.sum(costs) / length(costs)
```

### 3. Capability Mapping
```elixir
# Find all models that support both vision and function calling
{:ok, models} = ExLLM.Core.Models.find_by_capabilities([:vision, :function_calling])
```

## Dependencies

- **ex_llm:** The main LLM client library (local path: `../packages/ex_llm`)
- **YAML files:** Model configuration in `../packages/ex_llm/config/models/`

## Running the Scripts

1. **Navigate to the quantum_flow directory:**
   ```bash
   cd /path/to/singularity-incubation/packages/quantum_flow
   ```

2. **Run any script:**
   ```bash
   elixir simple_models_list.exs
   elixir list_models.exs
   elixir optimize_models.exs
   ```

3. **For development with Mix:**
   ```bash
   # If you want to run in a Mix project context
   mix run simple_models_list.exs
   ```

## Customization

### Adding New Optimization Strategies
```elixir
defp optimize_for_latency(models) do
  # Custom optimization based on response time
  models
  |> Enum.sort_by(fn model ->
    # Sort by some latency metric
    get_latency_score(model)
  end)
end
```

### Custom Use Case Filters
```elixir
defp find_models_for_code_generation(models) do
  models
  |> Enum.filter(fn model ->
    capabilities = model.capabilities || []
    :function_calling in capabilities and 
    (model.context_window || 0) >= 50_000
  end)
  |> Enum.sort_by(fn model -> model.pricing[:input] || Float.infinity() end)
end
```

## Integration with Nexus

These scripts can be integrated with the Nexus LLM router to provide intelligent model selection:

```elixir
# In Nexus.LLMRouter
def select_model(complexity, task_type) do
  case complexity do
    :simple -> find_cheapest_model_with_capabilities([:streaming])
    :medium -> find_balanced_model_for_task(task_type)
    :complex -> find_high_performance_model_with_capabilities([:reasoning, :function_calling])
  end
end
```

This demonstrates how ex_llm's YAML configuration can be used to create sophisticated model selection and optimization strategies for production LLM applications.