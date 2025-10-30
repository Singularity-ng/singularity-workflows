defmodule QuantumFlow.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Composite index for workflow step lookups
    # Used by: TaskExecutor.poll_and_execute_batch, FlowBuilder.get_flow, FlowOperations
    create index("workflow_steps", ["workflow_slug", "step_slug"],
      name: "idx_workflow_steps_composite"
    )

    # Index for workflow filtering by slug
    # Used by: FlowBuilder.list_flows, FlowOperations validation queries
    create index("workflows", ["workflow_slug"],
      name: "idx_workflows_slug"
    )

    # Composite index for step dependencies
    # Used by: FlowOperations.insert_dependencies, FlowBuilder.get_flow
    create index("workflow_step_dependencies_def", ["workflow_slug", "step_slug"],
      name: "idx_dependencies_step"
    )

    # Index for querying dependencies by dependent slug
    # Used by: TaskExecutor completion cascades, dependency validation
    create index("workflow_step_dependencies_def", ["workflow_slug", "dep_slug"],
      name: "idx_dependencies_dep"
    )

    # Index for workflow run status queries
    # Used by: TaskExecutor.check_run_status, Executor completion checks
    create index("workflow_runs", ["workflow_slug", "status"],
      name: "idx_workflow_runs_status"
    )

    # Index for step task lookups during execution
    # Used by: start_tasks, complete_task, fail_task functions
    create index("workflow_step_tasks", ["run_id", "step_slug"],
      name: "idx_step_tasks_run_step"
    )

    # Index for task status filtering (important for polling and completion)
    # Used by: TaskExecutor batch processing, task completion checks
    create index("workflow_step_tasks", ["step_slug", "status"],
      name: "idx_step_tasks_status"
    )
  end
end
