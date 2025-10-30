# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project. If another project (or dependency)
# is using this project, this file won't be loaded or affect it.
# For this reason, if you want to provide default values for your
# application for third-party users, it should be done in your
# "mix.exs" file.

import Config

# General application configuration
config :quantum_flow,
  ecto_repos: [QuantumFlow.Repo]

# Configures Elixir's Logger
config :logger,
  level: :info

# Use Jason for JSON parsing
config :quantum_flow, :json_library, Jason

# PGMQ configuration
config :quantum_flow, :pgmq,
  host: "localhost",
  port: 5432,
  database: "quantum_flow_dev",
  username: "postgres",
  password: "postgres",
  pool_size: 10,
  timeout: 30_000

# Orchestrator configuration
config :quantum_flow, :orchestrator,
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
    queue_prefix: "orchestrator",
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

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
