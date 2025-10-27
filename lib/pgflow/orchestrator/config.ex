defmodule Pgflow.Orchestrator.Config do
  @moduledoc """
  Configuration management for HTDAG functionality.

  Provides centralized configuration for HTDAG features including:
  - Default decomposer settings
  - Execution timeouts and limits
  - Optimization parameters
  - Notification settings
  - Performance thresholds

  ## AI Navigation Metadata

  ### Module Identity
  - **Type**: Configuration Manager (infrastructure)
  - **Purpose**: Single source of truth for orchestrator settings
  - **Provides**: Composable config for all orchestrator modules

  ### Call Graph
  - `get/2` → Application.get_env(config values)
  - `get_decomposer_config/2` → Returns typed decomposer config
  - `get_execution_config/1` → Returns execution settings
  - `feature_enabled?/2` → Feature flag checking
  - **Used by**: Orchestrator, OrchestratorNotifications, OrchestratorOptimizer, WorkflowComposer

  ### Anti-Patterns
  - ❌ DO NOT hard-code settings - use Config.get/2
  - ❌ DO NOT override config per-call - set in config files
  - ✅ DO use Config.get with defaults for backward compatibility
  - ✅ DO validate config on startup via validate_config/1

  ### Search Keywords
  configuration, config_management, settings, feature_flags, orchestrator_config,
  execution_settings, timeout_management, decomposer_config, performance_thresholds,
  runtime_configuration
  """

  @doc """
  Get HTDAG configuration with defaults.
  
  ## Parameters
  
  - `key` - Configuration key (atom or list of atoms for nested access)
  - `opts` - Options to override defaults
  
  ## Returns
  
  - Configuration value
  
  ## Example
  
      # Get default max depth
      max_depth = Pgflow.Orchestrator.Config.get(:max_depth)
      
      # Get nested configuration
      timeout = Pgflow.Orchestrator.Config.get([:execution, :timeout])
      
      # Override defaults
      timeout = Pgflow.Orchestrator.Config.get(:timeout, timeout: 600_000)
  """
  @spec get(atom() | list(atom()), keyword()) :: any()
  def get(key, opts \\ []) do
    config = get_htdag_config()
    value = get_in(config, List.wrap(key))
    
    # Override with options if provided
    case key do
      :max_depth -> Keyword.get(opts, :max_depth, value)
      :timeout -> Keyword.get(opts, :timeout, value)
      :max_parallel -> Keyword.get(opts, :max_parallel, value)
      :retry_attempts -> Keyword.get(opts, :retry_attempts, value)
      _ -> value
    end
  end

  @doc """
  Get decomposer configuration.
  
  ## Parameters
  
  - `decomposer_type` - Type of decomposer (:simple, :microservices, :data_pipeline, :ml_pipeline)
  - `opts` - Options to override defaults
  
  ## Returns
  
  - Decomposer configuration
  
  ## Example
  
      config = Pgflow.Orchestrator.Config.get_decomposer_config(:microservices, max_depth: 4)
  """
  @spec get_decomposer_config(atom(), keyword()) :: map()
  def get_decomposer_config(decomposer_type, opts \\ []) do
    base_config = get([:decomposers, decomposer_type])
    
    # Override with options
    Enum.reduce(opts, base_config, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  @doc """
  Get execution configuration.
  
  ## Parameters
  
  - `opts` - Options to override defaults
  
  ## Returns
  
  - Execution configuration
  
  ## Example
  
      config = Pgflow.Orchestrator.Config.get_execution_config(timeout: 600_000)
  """
  @spec get_execution_config(keyword()) :: map()
  def get_execution_config(opts \\ []) do
    base_config = get(:execution)
    
    # Override with options
    Enum.reduce(opts, base_config, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  @doc """
  Get optimization configuration.
  
  ## Parameters
  
  - `opts` - Options to override defaults
  
  ## Returns
  
  - Optimization configuration
  
  ## Example
  
      config = Pgflow.Orchestrator.Config.get_optimization_config(level: :aggressive)
  """
  @spec get_optimization_config(keyword()) :: map()
  def get_optimization_config(opts \\ []) do
    base_config = get(:optimization)
    
    # Override with options
    Enum.reduce(opts, base_config, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  @doc """
  Get notification configuration.
  
  ## Parameters
  
  - `opts` - Options to override defaults
  
  ## Returns
  
  - Notification configuration
  
  ## Example
  
      config = Pgflow.Orchestrator.Config.get_notification_config(enabled: true)
  """
  @spec get_notification_config(keyword()) :: map()
  def get_notification_config(opts \\ []) do
    base_config = get(:notifications)
    
    # Override with options
    Enum.reduce(opts, base_config, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  @doc """
  Check if a feature is enabled.
  
  ## Parameters
  
  - `feature` - Feature name
  - `opts` - Options to override defaults
  
  ## Returns
  
  - `true` if feature is enabled, `false` otherwise
  
  ## Example
  
      enabled = Pgflow.Orchestrator.Config.feature_enabled?(:monitoring)
      enabled = Pgflow.Orchestrator.Config.feature_enabled?(:optimization, level: :basic)
  """
  @spec feature_enabled?(atom(), keyword()) :: boolean()
  def feature_enabled?(feature, opts \\ []) do
    case feature do
      :monitoring -> get([:features, :monitoring], opts)
      :optimization -> get([:features, :optimization], opts)
      :notifications -> get([:features, :notifications], opts)
      :learning -> get([:features, :learning], opts)
      :real_time -> get([:features, :real_time], opts)
      _ -> false
    end
  end

  @doc """
  Get performance thresholds.
  
  ## Parameters
  
  - `metric_type` - Type of metric (:execution_time, :success_rate, :error_rate, etc.)
  - `opts` - Options to override defaults
  
  ## Returns
  
  - Performance threshold configuration
  
  ## Example
  
      threshold = Pgflow.Orchestrator.Config.get_performance_threshold(:execution_time)
  """
  @spec get_performance_threshold(atom(), keyword()) :: map()
  def get_performance_threshold(metric_type, opts \\ []) do
    base_config = get([:performance_thresholds, metric_type])
    
    # Override with options
    Enum.reduce(opts, base_config, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  @doc """
  Validate configuration.
  
  ## Parameters
  
  - `config` - Configuration to validate
  
  ## Returns
  
  - `:ok` if configuration is valid
  - `{:error, reason}` if configuration is invalid
  
  ## Example
  
      :ok = Pgflow.Orchestrator.Config.validate_config(config)
  """
  @spec validate_config(map()) :: :ok | {:error, any()}
  def validate_config(config) do
    with :ok <- validate_required_fields(config),
         :ok <- validate_value_ranges(config),
         :ok <- validate_dependencies(config) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp get_htdag_config do
    Application.get_env(:ex_pgflow, :htdag, default_config())
  end

  defp default_config do
    %{
      # Global settings
      max_depth: 5,
      timeout: 300_000,
      max_parallel: 10,
      retry_attempts: 3,
      
      # Decomposer configurations
      decomposers: %{
        simple: %{
          max_depth: 3,
          timeout: 30_000,
          parallel_threshold: 2
        },
        microservices: %{
          max_depth: 4,
          timeout: 60_000,
          parallel_threshold: 3
        },
        data_pipeline: %{
          max_depth: 4,
          timeout: 45_000,
          parallel_threshold: 2
        },
        ml_pipeline: %{
          max_depth: 5,
          timeout: 120_000,
          parallel_threshold: 2
        }
      },
      
      # Execution settings
      execution: %{
        timeout: 300_000,
        max_parallel: 10,
        retry_attempts: 3,
        retry_delay: 1_000,
        task_timeout: 30_000,
        monitor: true
      },
      
      # Optimization settings
      optimization: %{
        enabled: true,
        level: :basic,
        preserve_structure: true,
        max_parallel: 10,
        timeout_threshold: 60_000,
        learning_enabled: true,
        pattern_confidence_threshold: 0.7
      },
      
      # Notification settings
      notifications: %{
        enabled: true,
        real_time: true,
        event_types: [:decomposition, :task, :workflow, :performance],
        queue_prefix: "htdag",
        timeout: 5_000
      },
      
      # Feature flags
      features: %{
        monitoring: true,
        optimization: true,
        notifications: true,
        learning: true,
        real_time: true
      },
      
      # Performance thresholds
      performance_thresholds: %{
        execution_time: %{
          warning: 60_000,
          critical: 300_000
        },
        success_rate: %{
          warning: 0.8,
          critical: 0.5
        },
        error_rate: %{
          warning: 0.2,
          critical: 0.5
        },
        memory_usage: %{
          warning: 100_000_000,  # 100MB
          critical: 500_000_000  # 500MB
        }
      }
    }
  end

  defp validate_required_fields(config) do
    required_fields = [:max_depth, :timeout, :max_parallel, :retry_attempts]
    
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(config, field)
    end)
    
    if length(missing_fields) > 0 do
      {:error, "Missing required fields: #{inspect(missing_fields)}"}
    else
      :ok
    end
  end

  defp validate_value_ranges(config) do
    validations = [
      {config.max_depth, &is_integer/1, "max_depth must be an integer"},
      {config.max_depth, &(&1 > 0 and &1 < 20), "max_depth must be between 1 and 19"},
      {config.timeout, &is_integer/1, "timeout must be an integer"},
      {config.timeout, &(&1 > 0), "timeout must be positive"},
      {config.max_parallel, &is_integer/1, "max_parallel must be an integer"},
      {config.max_parallel, &(&1 > 0 and &1 < 100), "max_parallel must be between 1 and 99"},
      {config.retry_attempts, &is_integer/1, "retry_attempts must be an integer"},
      {config.retry_attempts, &(&1 >= 0 and &1 < 10), "retry_attempts must be between 0 and 9"}
    ]
    
    Enum.find_value(validations, :ok, fn {value, validator, message} ->
      if validator.(value) do
        nil
      else
        {:error, message}
      end
    end)
  end

  defp validate_dependencies(config) do
    # Validate that optimization settings are consistent
    if config.optimization.enabled and not config.features.optimization do
      {:error, "Optimization is enabled but feature flag is disabled"}
    else
      :ok
    end
  end
end