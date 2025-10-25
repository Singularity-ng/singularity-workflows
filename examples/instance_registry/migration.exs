defmodule YourApp.Repo.Migrations.CreateAgentRegistry do
  @moduledoc """
  Migration for AI Agent Registry tables.

  Creates tables for tracking AI agent instances, their execution history,
  cost metrics, and tool usage patterns.
  """

  use Ecto.Migration

  def up do
    # Main agent instances table
    create table(:agent_instances, primary_key: false) do
      add :agent_id, :text, primary_key: true
      add :agent_type, :text, null: false  # "planner", "executor", "researcher", "coder", etc.
      add :hostname, :text
      add :pid, :text
      add :status, :text, null: false  # 'online', 'offline', 'paused', 'busy'

      # Load metrics
      add :current_load, :integer, default: 0
      add :max_capacity, :integer, default: 10
      add :active_workflows, :integer, default: 0
      add :active_tasks, :integer, default: 0

      # Health & monitoring
      add :last_heartbeat, :utc_datetime
      add :cpu_usage_percent, :float
      add :memory_mb, :integer

      # AI-specific metadata
      add :llm_provider, :text  # "claude", "openai", "gemini", etc.
      add :model_name, :text    # "claude-3-5-sonnet-20241022", "gpt-4", etc.
      add :temperature, :float
      add :max_tokens, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:agent_instances, [:status])
    create index(:agent_instances, [:agent_type])
    create index(:agent_instances, [:last_heartbeat])
    create index(:agent_instances, [:status, :agent_type])

    # Agent execution history
    create table(:agent_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_id, references(:agent_instances, column: :agent_id, type: :text, on_delete: :delete_all)
      add :workflow_slug, :text
      add :run_id, :uuid

      # Execution details
      add :task_type, :text  # "code_generation", "planning", "research", "analysis", etc.
      add :status, :text, null: false  # "success", "failed", "timeout"
      add :started_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime
      add :duration_ms, :integer

      # AI-specific metrics
      add :prompt_tokens, :integer
      add :completion_tokens, :integer
      add :total_tokens, :integer
      add :estimated_cost_usd, :float

      # Quality metrics
      add :retry_count, :integer, default: 0
      add :error_message, :text
      add :success_score, :float  # 0.0 to 1.0

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:agent_executions, [:agent_id])
    create index(:agent_executions, [:workflow_slug])
    create index(:agent_executions, [:status])
    create index(:agent_executions, [:started_at])
    create index(:agent_executions, [:task_type])

    # Agent tool usage tracking
    create table(:agent_tool_usage) do
      add :agent_id, references(:agent_instances, column: :agent_id, type: :text, on_delete: :delete_all)
      add :tool_name, :text, null: false  # "code_search", "file_edit", "bash", etc.
      add :execution_id, references(:agent_executions, type: :binary_id, on_delete: :delete_all)

      add :invocation_count, :integer, default: 1
      add :success_count, :integer, default: 0
      add :failure_count, :integer, default: 0
      add :avg_duration_ms, :float

      # Cost tracking
      add :total_cost_usd, :float, default: 0.0

      timestamps(type: :utc_datetime)
    end

    create index(:agent_tool_usage, [:agent_id])
    create index(:agent_tool_usage, [:tool_name])
    create unique_index(:agent_tool_usage, [:agent_id, :tool_name, :execution_id])

    # Agent performance summary (materialized view or updated via trigger)
    create table(:agent_performance_summary, primary_key: false) do
      add :agent_id, :text, primary_key: true
      add :total_executions, :integer, default: 0
      add :successful_executions, :integer, default: 0
      add :failed_executions, :integer, default: 0
      add :avg_duration_ms, :float
      add :total_tokens_used, :bigint, default: 0
      add :total_cost_usd, :float, default: 0.0
      add :success_rate, :float  # Computed: successful / total
      add :last_execution_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end
  end

  def down do
    drop table(:agent_performance_summary)
    drop table(:agent_tool_usage)
    drop table(:agent_executions)
    drop table(:agent_instances)
  end
end
