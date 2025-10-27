defmodule Pgflow.Orchestrator.Schemas do
  @moduledoc """
  Ecto schemas for HTDAG data models.

  Defines the database schemas for HTDAG task graphs, workflows, executions,
  and related data structures. Each schema is defined as a nested module.
  """

  defmodule TaskGraph do
    @moduledoc """
    Task Graph schema for storing HTDAG decomposition results.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "htdag_task_graphs" do
      field :name, :string
      field :goal, :string
      field :decomposer_module, :string
      field :task_graph, :map
      field :max_depth, :integer, default: 5

      has_many :workflows, Pgflow.Orchestrator.Schemas.Workflow, foreign_key: :task_graph_id

      timestamps()
    end

    def changeset(task_graph, attrs) do
      task_graph
      |> cast(attrs, [:name, :goal, :decomposer_module, :task_graph, :max_depth])
      |> validate_required([:name, :goal, :decomposer_module, :task_graph])
      |> validate_length(:name, min: 1, max: 255)
      |> validate_number(:max_depth, greater_than: 0, less_than: 20)
    end
  end

  defmodule Workflow do
    @moduledoc """
    Workflow schema for storing HTDAG-generated workflows.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "htdag_workflows" do
      field :name, :string
      field :workflow_definition, :map
      field :step_functions, :map
      field :max_parallel, :integer, default: 10
      field :retry_attempts, :integer, default: 3
      field :status, :string, default: "created"

      belongs_to :task_graph, Pgflow.Orchestrator.Schemas.TaskGraph, foreign_key: :task_graph_id
      has_many :executions, Pgflow.Orchestrator.Schemas.Execution, foreign_key: :workflow_id
      has_many :performance_metrics, Pgflow.Orchestrator.Schemas.PerformanceMetric, foreign_key: :workflow_id

      timestamps()
    end

    def workflow_changeset(workflow, attrs) do
      workflow
      |> cast(attrs, [:name, :workflow_definition, :step_functions, :max_parallel, :retry_attempts, :status])
      |> validate_required([:name, :workflow_definition, :step_functions])
      |> validate_length(:name, min: 1, max: 255)
      |> validate_number(:max_parallel, greater_than: 0, less_than: 100)
      |> validate_number(:retry_attempts, greater_than_or_equal_to: 0, less_than: 10)
      |> validate_inclusion(:status, ["created", "running", "completed", "failed", "cancelled"])
    end
  end

  defmodule Execution do
    @moduledoc """
    Execution schema for storing workflow execution instances.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "htdag_executions" do
      field :execution_id, :string
      field :goal_context, :map
      field :status, :string, default: "running"
      field :started_at, :utc_datetime
      field :completed_at, :utc_datetime
      field :duration_ms, :integer
      field :result, :map
      field :error_message, :string

      belongs_to :workflow, Pgflow.Orchestrator.Schemas.Workflow, foreign_key: :workflow_id
      has_many :task_executions, Pgflow.Orchestrator.Schemas.TaskExecution, foreign_key: :execution_id
      has_many :events, Pgflow.Orchestrator.Schemas.Event, foreign_key: :execution_id

      timestamps()
    end

    def execution_changeset(execution, attrs) do
      execution
      |> cast(attrs, [:execution_id, :goal_context, :status, :started_at, :completed_at, :duration_ms, :result, :error_message])
      |> validate_required([:execution_id, :goal_context])
      |> validate_inclusion(:status, ["running", "completed", "failed", "cancelled"])
      |> validate_length(:execution_id, min: 1, max: 255)
    end
  end

  defmodule TaskExecution do
    @moduledoc """
    Task Execution schema for storing individual task execution instances.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "htdag_task_executions" do
      field :task_id, :string
      field :task_name, :string
      field :status, :string, default: "pending"
      field :started_at, :utc_datetime
      field :completed_at, :utc_datetime
      field :duration_ms, :integer
      field :result, :map
      field :error_message, :string
      field :retry_count, :integer, default: 0

      belongs_to :execution, Pgflow.Orchestrator.Schemas.Execution, foreign_key: :execution_id
      has_many :events, Pgflow.Orchestrator.Schemas.Event, foreign_key: :task_execution_id

      timestamps()
    end

    def task_execution_changeset(task_execution, attrs) do
      task_execution
      |> cast(attrs, [:task_id, :task_name, :status, :started_at, :completed_at, :duration_ms, :result, :error_message, :retry_count])
      |> validate_required([:task_id, :task_name])
      |> validate_inclusion(:status, ["pending", "running", "completed", "failed", "cancelled"])
      |> validate_length(:task_id, min: 1, max: 255)
      |> validate_number(:retry_count, greater_than_or_equal_to: 0, less_than: 10)
    end
  end

  defmodule Event do
    @moduledoc """
    Event schema for storing HTDAG events and notifications.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "htdag_events" do
      field :event_type, :string
      field :event_data, :map
      field :timestamp, :utc_datetime

      belongs_to :execution, Pgflow.Orchestrator.Schemas.Execution, foreign_key: :execution_id
      belongs_to :task_execution, Pgflow.Orchestrator.Schemas.TaskExecution, foreign_key: :task_execution_id

      timestamps()
    end

    def event_changeset(event, attrs) do
      event
      |> cast(attrs, [:event_type, :event_data, :timestamp])
      |> validate_required([:event_type, :event_data])
      |> validate_inclusion(:event_type, [
        "decomposition:started", "decomposition:completed", "decomposition:failed",
        "task:started", "task:completed", "task:failed",
        "workflow:started", "workflow:completed", "workflow:failed",
        "performance:metrics"
      ])
    end
  end

  defmodule PerformanceMetric do
    @moduledoc """
    Performance Metric schema for storing execution metrics.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "htdag_performance_metrics" do
      field :task_id, :string
      field :metric_type, :string
      field :metric_value, :float
      field :metric_unit, :string
      field :context, :map
      field :timestamp, :utc_datetime

      belongs_to :workflow, Pgflow.Orchestrator.Schemas.Workflow, foreign_key: :workflow_id

      timestamps()
    end

    def performance_metric_changeset(metric, attrs) do
      metric
      |> cast(attrs, [:task_id, :metric_type, :metric_value, :metric_unit, :context, :timestamp])
      |> validate_required([:metric_type, :metric_value])
      |> validate_inclusion(:metric_type, [
        "execution_time", "success_rate", "error_rate", "resource_usage",
        "throughput", "latency", "memory_usage", "cpu_usage"
      ])
      |> validate_number(:metric_value, greater_than_or_equal_to: 0)
    end
  end

  defmodule LearningPattern do
    @moduledoc """
    Learning Pattern schema for storing optimization patterns.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "htdag_learning_patterns" do
      field :workflow_name, :string
      field :pattern_type, :string
      field :pattern_data, :map
      field :confidence_score, :float, default: 0.0
      field :usage_count, :integer, default: 0
      field :last_used_at, :utc_datetime

      timestamps()
    end

    def learning_pattern_changeset(pattern, attrs) do
      pattern
      |> cast(attrs, [:workflow_name, :pattern_type, :pattern_data, :confidence_score, :usage_count, :last_used_at])
      |> validate_required([:workflow_name, :pattern_type, :pattern_data])
      |> validate_length(:workflow_name, min: 1, max: 255)
      |> validate_inclusion(:pattern_type, [
        "parallelization", "timeout_optimization", "retry_strategy",
        "resource_allocation", "dependency_optimization"
      ])
      |> validate_number(:confidence_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
      |> validate_number(:usage_count, greater_than_or_equal_to: 0)
    end
  end
end
