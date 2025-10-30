defmodule Observer.DashboardBehaviour do
  @moduledoc """
  Behaviour for Observer dashboard data providers.

  This behaviour defines the interface that dashboard modules must implement
  to provide data to Observer LiveView components.
  """

  @callback agent_performance() :: {:ok, map()} | {:error, term()}
  @callback code_quality() :: {:ok, map()} | {:error, term()}
  @callback cost_analysis() :: {:ok, map()} | {:error, term()}
  @callback rule_evolution() :: {:ok, map()} | {:error, term()}
  @callback task_execution() :: {:ok, map()} | {:error, term()}
  @callback knowledge_base() :: {:ok, map()} | {:error, term()}
  @callback llm_health() :: {:ok, map()} | {:error, term()}
  @callback validation_metrics() :: {:ok, map()} | {:error, term()}
  @callback validation_metrics_store() :: {:ok, map()} | {:error, term()}
  @callback failure_patterns() :: {:ok, map()} | {:error, term()}
  @callback adaptive_threshold() :: {:ok, map()} | {:error, term()}
  @callback system_health() :: {:ok, map()} | {:error, term()}
end