defmodule Pgflow.Repo.Migrations.CreateWorkflowDefinitionTables do
  @moduledoc """
  Creates tables for storing dynamic workflow definitions.

  Enables runtime workflow creation via API (for AI/LLM workflow generation).
  Matches pgflow's flows, steps, and deps tables.

  Usage:
    - Code-based workflows: Use __workflow_steps__/0 callback (existing)
    - Dynamic workflows: Use FlowBuilder.create_flow() + add_step() (new)

  Both approaches execute identically - just different definition sources.
  """
  use Ecto.Migration

  def change do
    # Flows table - stores workflow definitions
    create table(:workflows, primary_key: false) do
      add :workflow_slug, :text, primary_key: true, null: false
      add :max_attempts, :integer, null: false, default: 3
      add :timeout, :integer, null: false, default: 60  # Matches pgflow opt_timeout default
      add :created_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create constraint(:workflows, :workflow_slug_is_valid, check: "pgflow.is_valid_slug(workflow_slug)")
    create constraint(:workflows, :max_attempts_is_nonnegative, check: "max_attempts >= 0")
    create constraint(:workflows, :timeout_is_positive, check: "timeout > 0")

    # Steps table - stores individual steps within workflows
    create table(:workflow_steps, primary_key: false) do
      add :workflow_slug, references(:workflows, column: :workflow_slug, type: :text, on_delete: :delete_all), null: false
      add :step_slug, :text, null: false
      add :step_type, :text, null: false, default: "single"
      add :step_index, :integer, null: false, default: 0
      add :deps_count, :integer, null: false, default: 0
      add :initial_tasks, :integer, null: true
      add :max_attempts, :integer, null: true
      add :timeout, :integer, null: true
      add :created_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:workflow_steps, [:workflow_slug, :step_slug], name: :workflow_steps_pkey)
    create unique_index(:workflow_steps, [:workflow_slug, :step_index])
    create constraint(:workflow_steps, :step_slug_is_valid, check: "pgflow.is_valid_slug(step_slug)")
    create constraint(:workflow_steps, :step_type_is_valid, check: "step_type IN ('single', 'map')")
    create constraint(:workflow_steps, :deps_count_nonnegative, check: "deps_count >= 0")
    create constraint(:workflow_steps, :initial_tasks_nonnegative, check: "initial_tasks IS NULL OR initial_tasks >= 0")
    create constraint(:workflow_steps, :max_attempts_nonnegative, check: "max_attempts IS NULL OR max_attempts >= 0")
    create constraint(:workflow_steps, :timeout_positive, check: "timeout IS NULL OR timeout > 0")

    # Dependencies table - stores relationships between steps
    create table(:workflow_step_dependencies_def, primary_key: false) do
      add :workflow_slug, :text, null: false
      add :dep_slug, :text, null: false
      add :step_slug, :text, null: false
      add :created_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:workflow_step_dependencies_def, [:workflow_slug, :dep_slug, :step_slug], name: :workflow_step_dependencies_def_pkey)
    create index(:workflow_step_dependencies_def, [:workflow_slug, :step_slug], name: :idx_deps_def_by_workflow_step)
    create index(:workflow_step_dependencies_def, [:workflow_slug, :dep_slug], name: :idx_deps_def_by_workflow_dep)
    create constraint(:workflow_step_dependencies_def, :no_self_dependencies, check: "dep_slug != step_slug")

    # Add foreign keys after indexes
    execute("ALTER TABLE workflow_step_dependencies_def ADD CONSTRAINT workflow_step_dependencies_def_dep_fkey FOREIGN KEY (workflow_slug, dep_slug) REFERENCES workflow_steps (workflow_slug, step_slug)")
    execute("ALTER TABLE workflow_step_dependencies_def ADD CONSTRAINT workflow_step_dependencies_def_step_fkey FOREIGN KEY (workflow_slug, step_slug) REFERENCES workflow_steps (workflow_slug, step_slug)")
  end
end
