defmodule Pgflow.Agent.Instance do
  @moduledoc """
  Ecto schema for AI agent instances.

  Tracks which agents are running, their current state, and capacity metrics.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:agent_id, :string, autogenerate: false}
  schema "agent_instances" do
    field :agent_type, :string
    field :hostname, :string
    field :pid, :string
    field :status, :string

    # Load metrics
    field :current_load, :integer, default: 0
    field :max_capacity, :integer, default: 10
    field :active_workflows, :integer, default: 0
    field :active_tasks, :integer, default: 0

    # Health & monitoring
    field :last_heartbeat, :utc_datetime
    field :cpu_usage_percent, :float
    field :memory_mb, :integer

    # AI-specific metadata
    field :llm_provider, :string
    field :model_name, :string
    field :temperature, :float
    field :max_tokens, :integer

    timestamps(type: :utc_datetime)

    has_many :executions, Pgflow.Agent.Execution, foreign_key: :agent_id
    has_one :performance, Pgflow.Agent.PerformanceSummary, foreign_key: :agent_id
  end

  @required_fields ~w(agent_id agent_type status)a
  @optional_fields ~w(hostname pid current_load max_capacity active_workflows active_tasks
                      last_heartbeat cpu_usage_percent memory_mb llm_provider model_name
                      temperature max_tokens)a

  def changeset(instance, attrs) do
    instance
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ~w(online offline paused busy))
    |> validate_inclusion(:agent_type, ~w(planner executor researcher coder analyzer reviewer))
    |> validate_number(:current_load, greater_than_or_equal_to: 0)
    |> validate_number(:max_capacity, greater_than: 0)
    |> unique_constraint(:agent_id, name: :agent_instances_pkey)
  end

  def online_changeset(instance, attrs \\ %{}) do
    changeset(instance, Map.put(attrs, :status, "online"))
  end

  def heartbeat_changeset(instance) do
    change(instance, last_heartbeat: DateTime.utc_now())
  end

  def load_changeset(instance, load) do
    change(instance, current_load: load)
  end
end

defmodule Pgflow.Agent.Execution do
  @moduledoc """
  Ecto schema for AI agent execution history.

  Tracks individual task executions with cost, token usage, and success metrics.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "agent_executions" do
    field :agent_id, :string
    field :workflow_slug, :string
    field :run_id, Ecto.UUID

    # Execution details
    field :task_type, :string
    field :status, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :duration_ms, :integer

    # AI-specific metrics
    field :prompt_tokens, :integer
    field :completion_tokens, :integer
    field :total_tokens, :integer
    field :estimated_cost_usd, :float

    # Quality metrics
    field :retry_count, :integer, default: 0
    field :error_message, :string
    field :success_score, :float

    timestamps(type: :utc_datetime, updated_at: false)

    belongs_to :instance, Pgflow.Agent.Instance,
      foreign_key: :agent_id,
      references: :agent_id,
      define_field: false

    has_many :tool_usage, Pgflow.Agent.ToolUsage, foreign_key: :execution_id
  end

  @required_fields ~w(agent_id status started_at)a
  @optional_fields ~w(workflow_slug run_id task_type completed_at duration_ms
                      prompt_tokens completion_tokens total_tokens estimated_cost_usd
                      retry_count error_message success_score)a

  def changeset(execution, attrs) do
    execution
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ~w(success failed timeout))
    |> validate_number(:success_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:agent_id)
  end

  def start_changeset(attrs) do
    changeset(%__MODULE__{}, Map.put(attrs, :started_at, DateTime.utc_now()))
  end

  def complete_changeset(execution, status, attrs \\ %{}) do
    now = DateTime.utc_now()
    duration_ms = DateTime.diff(now, execution.started_at, :millisecond)

    execution
    |> changeset(
      attrs
      |> Map.put(:status, status)
      |> Map.put(:completed_at, now)
      |> Map.put(:duration_ms, duration_ms)
    )
  end
end

defmodule Pgflow.Agent.ToolUsage do
  @moduledoc """
  Ecto schema for tracking agent tool usage patterns.

  Helps identify which tools agents use most and their success rates.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_tool_usage" do
    field :agent_id, :string
    field :tool_name, :string
    field :execution_id, Ecto.UUID

    field :invocation_count, :integer, default: 1
    field :success_count, :integer, default: 0
    field :failure_count, :integer, default: 0
    field :avg_duration_ms, :float

    field :total_cost_usd, :float, default: 0.0

    timestamps(type: :utc_datetime)

    belongs_to :instance, Pgflow.Agent.Instance,
      foreign_key: :agent_id,
      references: :agent_id,
      define_field: false

    belongs_to :execution, Pgflow.Agent.Execution,
      foreign_key: :execution_id,
      references: :id,
      define_field: false
  end

  @required_fields ~w(agent_id tool_name)a
  @optional_fields ~w(execution_id invocation_count success_count failure_count
                      avg_duration_ms total_cost_usd)a

  def changeset(usage, attrs) do
    usage
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:execution_id)
    |> unique_constraint([:agent_id, :tool_name, :execution_id])
  end
end

defmodule Pgflow.Agent.PerformanceSummary do
  @moduledoc """
  Ecto schema for agent performance summary (aggregated metrics).

  Computed periodically via background job or database trigger.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:agent_id, :string, autogenerate: false}
  schema "agent_performance_summary" do
    field :total_executions, :integer, default: 0
    field :successful_executions, :integer, default: 0
    field :failed_executions, :integer, default: 0
    field :avg_duration_ms, :float
    field :total_tokens_used, :integer, default: 0
    field :total_cost_usd, :float, default: 0.0
    field :success_rate, :float
    field :last_execution_at, :utc_datetime

    timestamps(type: :utc_datetime)

    belongs_to :instance, Pgflow.Agent.Instance,
      foreign_key: :agent_id,
      references: :agent_id,
      define_field: false
  end

  def changeset(summary, attrs) do
    summary
    |> cast(attrs, ~w(agent_id total_executions successful_executions failed_executions
                      avg_duration_ms total_tokens_used total_cost_usd success_rate
                      last_execution_at)a)
    |> validate_required([:agent_id])
    |> foreign_key_constraint(:agent_id)
    |> unique_constraint(:agent_id, name: :agent_performance_summary_pkey)
  end
end
