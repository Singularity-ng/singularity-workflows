import Config

# Print only warnings and errors during test
config :logger, level: :warning

# Use TestClock for testing
config :quantum_flow, :clock, QuantumFlow.TestClock

# Configure your database
config :quantum_flow, QuantumFlow.Repo,
  username: System.get_env("PGUSER") || System.get_env("USER"),
  password: System.get_env("PGPASSWORD") || "",
  hostname: System.get_env("PGHOST") || "localhost",
  database: "quantum_flow_test#{System.get_env("MIX_TEST_PARTITION")}",
  adapter: Ecto.Adapters.Postgres,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Orchestrator test configuration
config :quantum_flow, :orchestrator,
  # Disable features that might interfere with tests
  features: %{
    monitoring: false,
    optimization: false,
    notifications: false,
    learning: false,
    real_time: false
  },

  # Fast timeouts for tests
  timeout: 5_000,
  execution: %{
    timeout: 5_000,
    task_timeout: 1_000,
    retry_attempts: 1
  },

  # Disable notifications for tests
  notifications: %{
    enabled: false,
    real_time: false,
    event_types: [],
    queue_prefix: "orchestrator_test",
    timeout: 1_000
  },

  # Minimal decomposer configs for tests
  decomposers: %{
    simple: %{
      max_depth: 2,
      timeout: 1_000,
      parallel_threshold: 1
    },
    microservices: %{
      max_depth: 2,
      timeout: 1_000,
      parallel_threshold: 1
    },
    data_pipeline: %{
      max_depth: 2,
      timeout: 1_000,
      parallel_threshold: 1
    },
    ml_pipeline: %{
      max_depth: 2,
      timeout: 1_000,
      parallel_threshold: 1
    }
  }
