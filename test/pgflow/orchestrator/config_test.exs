defmodule Pgflow.Orchestrator.ConfigTest do
  use ExUnit.Case, async: true

  alias Pgflow.Orchestrator.Config

  describe "get/2" do
    test "returns configuration value" do
      assert Config.get(:max_depth) == 5
      assert Config.get(:timeout) == 300_000
      assert Config.get(:max_parallel) == 10
      assert Config.get(:retry_attempts) == 3
    end

    test "returns nested configuration value" do
      assert Config.get([:execution, :timeout]) == 300_000
      assert Config.get([:optimization, :enabled]) == true
      assert Config.get([:features, :monitoring]) == true
    end

    test "overrides with options" do
      assert Config.get(:max_depth, max_depth: 10) == 10
      assert Config.get(:timeout, timeout: 600_000) == 600_000
      assert Config.get(:max_parallel, max_parallel: 20) == 20
    end

    test "returns default for unknown key" do
      assert Config.get(:unknown_key) == nil
      assert Config.get([:unknown, :nested, :key]) == nil
    end
  end

  describe "get_decomposer_config/2" do
    test "returns decomposer configuration" do
      config = Config.get_decomposer_config(:simple)
      
      assert config.max_depth == 3
      assert config.timeout == 30_000
      assert config.parallel_threshold == 2
    end

    test "overrides with options" do
      config = Config.get_decomposer_config(:simple, max_depth: 5, timeout: 60_000)
      
      assert config.max_depth == 5
      assert config.timeout == 60_000
      assert config.parallel_threshold == 2
    end

    test "returns configuration for different decomposer types" do
      simple_config = Config.get_decomposer_config(:simple)
      microservices_config = Config.get_decomposer_config(:microservices)
      data_pipeline_config = Config.get_decomposer_config(:data_pipeline)
      ml_pipeline_config = Config.get_decomposer_config(:ml_pipeline)

      assert simple_config.max_depth == 3
      assert microservices_config.max_depth == 4
      assert data_pipeline_config.max_depth == 4
      assert ml_pipeline_config.max_depth == 5
    end
  end

  describe "get_execution_config/1" do
    test "returns execution configuration" do
      config = Config.get_execution_config()
      
      assert config.timeout == 300_000
      assert config.max_parallel == 10
      assert config.retry_attempts == 3
      assert config.retry_delay == 1_000
      assert config.task_timeout == 30_000
      assert config.monitor == true
    end

    test "overrides with options" do
      config = Config.get_execution_config(timeout: 600_000, max_parallel: 20)
      
      assert config.timeout == 600_000
      assert config.max_parallel == 20
      assert config.retry_attempts == 3
    end
  end

  describe "get_optimization_config/1" do
    test "returns optimization configuration" do
      config = Config.get_optimization_config()
      
      assert config.enabled == true
      assert config.level == :basic
      assert config.preserve_structure == true
      assert config.max_parallel == 10
      assert config.timeout_threshold == 60_000
      assert config.learning_enabled == true
      assert config.pattern_confidence_threshold == 0.7
    end

    test "overrides with options" do
      config = Config.get_optimization_config(level: :aggressive, max_parallel: 20)
      
      assert config.enabled == true
      assert config.level == :aggressive
      assert config.max_parallel == 20
    end
  end

  describe "get_notification_config/1" do
    test "returns notification configuration" do
      config = Config.get_notification_config()

      assert config.enabled == true
      assert config.real_time == true
      assert config.event_types == [:decomposition, :task, :workflow, :performance]
      assert config.queue_prefix == "orchestrator"
      assert config.timeout == 5_000
    end

    test "overrides with options" do
      config = Config.get_notification_config(enabled: false, timeout: 10_000)
      
      assert config.enabled == false
      assert config.timeout == 10_000
      assert config.real_time == true
    end
  end

  describe "feature_enabled?/2" do
    test "returns feature enabled status" do
      assert Config.feature_enabled?(:monitoring) == true
      assert Config.feature_enabled?(:optimization) == true
      assert Config.feature_enabled?(:notifications) == true
      assert Config.feature_enabled?(:learning) == true
      assert Config.feature_enabled?(:real_time) == true
    end

    test "returns false for unknown feature" do
      assert Config.feature_enabled?(:unknown_feature) == false
    end

    test "overrides with options" do
      assert Config.feature_enabled?(:monitoring, monitoring: false) == false
      assert Config.feature_enabled?(:optimization, level: :basic) == true
    end
  end

  describe "get_performance_threshold/2" do
    test "returns performance threshold configuration" do
      execution_time_threshold = Config.get_performance_threshold(:execution_time)
      success_rate_threshold = Config.get_performance_threshold(:success_rate)
      error_rate_threshold = Config.get_performance_threshold(:error_rate)
      memory_usage_threshold = Config.get_performance_threshold(:memory_usage)

      assert execution_time_threshold.warning == 60_000
      assert execution_time_threshold.critical == 300_000
      assert success_rate_threshold.warning == 0.8
      assert success_rate_threshold.critical == 0.5
      assert error_rate_threshold.warning == 0.2
      assert error_rate_threshold.critical == 0.5
      assert memory_usage_threshold.warning == 100_000_000
      assert memory_usage_threshold.critical == 500_000_000
    end

    test "overrides with options" do
      threshold = Config.get_performance_threshold(:execution_time, warning: 120_000)
      
      assert threshold.warning == 120_000
      assert threshold.critical == 300_000
    end
  end

  describe "validate_config/1" do
    test "validates correct configuration" do
      config = %{
        max_depth: 5,
        timeout: 300_000,
        max_parallel: 10,
        retry_attempts: 3
      }

      assert Config.validate_config(config) == :ok
    end

    test "validates configuration with all fields" do
      config = %{
        max_depth: 5,
        timeout: 300_000,
        max_parallel: 10,
        retry_attempts: 3,
        optimization: %{enabled: true},
        features: %{optimization: true}
      }

      assert Config.validate_config(config) == :ok
    end

    test "fails validation for missing required fields" do
      config = %{
        max_depth: 5,
        timeout: 300_000
        # Missing max_parallel and retry_attempts
      }

      {:error, "Missing required fields: [:max_parallel, :retry_attempts]"} = 
        Config.validate_config(config)
    end

    test "fails validation for invalid value ranges" do
      config = %{
        max_depth: 0,  # Invalid: must be > 0
        timeout: 300_000,
        max_parallel: 10,
        retry_attempts: 3
      }

      {:error, "max_depth must be between 1 and 19"} = Config.validate_config(config)
    end

    test "fails validation for invalid max_parallel" do
      config = %{
        max_depth: 5,
        timeout: 300_000,
        max_parallel: 0,  # Invalid: must be > 0
        retry_attempts: 3
      }

      {:error, "max_parallel must be between 1 and 99"} = Config.validate_config(config)
    end

    test "fails validation for invalid retry_attempts" do
      config = %{
        max_depth: 5,
        timeout: 300_000,
        max_parallel: 10,
        retry_attempts: 10  # Invalid: must be < 10
      }

      {:error, "retry_attempts must be between 0 and 9"} = Config.validate_config(config)
    end

    test "fails validation for dependency conflicts" do
      config = %{
        max_depth: 5,
        timeout: 300_000,
        max_parallel: 10,
        retry_attempts: 3,
        optimization: %{enabled: true},
        features: %{optimization: false}  # Conflict: optimization enabled but feature disabled
      }

      {:error, "Optimization is enabled but feature flag is disabled"} = 
        Config.validate_config(config)
    end
  end
end