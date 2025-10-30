import Config

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done in config/runtime.exs.

# Orchestrator production configuration
config :quantum_flow, :orchestrator,
  # Production-optimized settings
  max_depth: 5,
  timeout: 300_000,
  max_parallel: 20,
  retry_attempts: 3,
  
  # Production execution settings
  execution: %{
    timeout: 300_000,
    max_parallel: 20,
    retry_attempts: 3,
    retry_delay: 2_000,
    task_timeout: 60_000,
    monitor: true
  },
  
  # Enable optimization for production
  optimization: %{
    enabled: true,
    level: :advanced,
    preserve_structure: true,
    max_parallel: 20,
    timeout_threshold: 120_000,
    learning_enabled: true,
    pattern_confidence_threshold: 0.8
  },
  
  # Production notification settings
  notifications: %{
    enabled: true,
    real_time: true,
    event_types: [:decomposition, :task, :workflow, :performance],
    queue_prefix: "orchestrator_prod",
    timeout: 5_000
  },
  
  # Enable all features for production
  features: %{
    monitoring: true,
    optimization: true,
    notifications: true,
    learning: true,
    real_time: true
  },
  
  # Production performance thresholds
  performance_thresholds: %{
    execution_time: %{
      warning: 120_000,
      critical: 600_000
    },
    success_rate: %{
      warning: 0.9,
      critical: 0.7
    },
    error_rate: %{
      warning: 0.1,
      critical: 0.3
    },
    memory_usage: %{
      warning: 500_000_000,  # 500MB
      critical: 2_000_000_000  # 2GB
    }
  },
  
  # Production decomposer configs
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
  }