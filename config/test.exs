import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ex_pgflow, PgflowWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_here",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Configure your database
config :ex_pgflow, Pgflow.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ex_pgflow_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We use a file-based database for testing
config :ex_pgflow, Pgflow.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ex_pgflow_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox

# Orchestrator test configuration
config :ex_pgflow, :orchestrator,
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