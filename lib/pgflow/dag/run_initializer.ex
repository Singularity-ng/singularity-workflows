defmodule Pgflow.DAG.RunInitializer do
  @moduledoc """
  Initializes a workflow run in the database - creates all necessary records
  for database-driven DAG execution.

  ## Initialization Steps

  1. Create workflow_runs record with status='started'
  2. Create workflow_step_states records for each step
     - Set remaining_deps based on dependency count
     - Set initial_tasks (supports map steps with N tasks)
  3. Create workflow_step_dependencies records
  4. Ensure pgmq queue exists for this workflow
  5. Call start_ready_steps() to:
     - Mark root steps as 'started'
     - Create workflow_step_tasks records
     - Send messages to pgmq queue (matches pgflow architecture)

  ## Example

      {:ok, definition} = WorkflowDefinition.parse(MyWorkflow)
      {:ok, run_id} = RunInitializer.initialize(definition, %{"user_id" => 123}, MyApp.Repo)

      # Database now contains:
      # - 1 workflow_runs record
      # - N workflow_step_states records (one per step)
      # - M workflow_step_dependencies records
      # - K workflow_step_tasks records (for root steps)
  """

  require Logger

  alias Pgflow.DAG.WorkflowDefinition
  alias Pgflow.{WorkflowRun, StepState, StepDependency}

  @doc """
  Initialize a workflow run with all database records.

  Returns `{:ok, run_id}` on success.
  """
  @spec initialize(WorkflowDefinition.t(), map(), module()) ::
          {:ok, Ecto.UUID.t()} | {:error, term()}
  def initialize(%WorkflowDefinition{} = definition, input, repo) do
    repo.transaction(fn ->
      with {:ok, run} <- create_run(definition, input, repo),
           :ok <- create_step_states(definition, run.id, repo),
           :ok <- create_dependencies(definition, run.id, repo),
           :ok <- ensure_workflow_queue(definition.slug, repo),
           :ok <- start_ready_steps(run.id, repo) do
        run.id
      else
        {:error, reason} ->
          repo.rollback(reason)
      end
    end)
  end

  # Step 1: Create workflow_runs record
  defp create_run(definition, input, repo) do
    run_id = Ecto.UUID.generate()
    step_count = map_size(definition.steps)

    %WorkflowRun{}
    |> WorkflowRun.changeset(%{
      id: run_id,
      workflow_slug: definition.slug,
      status: "started",
      input: input,
      remaining_steps: step_count,
      started_at: DateTime.utc_now()
    })
    |> repo.insert()
  end

  # Step 2: Create workflow_step_states records
  defp create_step_states(definition, run_id, repo) do
    step_states =
      Enum.map(definition.steps, fn {step_name, _step_fn} ->
        remaining_deps = WorkflowDefinition.dependency_count(definition, step_name)
        metadata = WorkflowDefinition.get_step_metadata(definition, step_name)

        %{
          run_id: run_id,
          step_slug: to_string(step_name),
          workflow_slug: definition.slug,
          status: "created",
          remaining_deps: remaining_deps,
          initial_tasks: metadata.initial_tasks,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      end)

    {count, _} = repo.insert_all(StepState, step_states)

    if count == map_size(definition.steps) do
      :ok
    else
      {:error, :step_states_insert_failed}
    end
  end

  # Step 3: Create workflow_step_dependencies records
  defp create_dependencies(definition, run_id, repo) do
    dependency_records =
      Enum.flat_map(definition.dependencies, fn {step_name, deps} ->
        Enum.map(deps, fn dep_name ->
          %{
            run_id: run_id,
            step_slug: to_string(step_name),
            depends_on_step: to_string(dep_name),
            inserted_at: DateTime.utc_now()
          }
        end)
      end)

    if dependency_records == [] do
      :ok
    else
      {_count, _} = repo.insert_all(StepDependency, dependency_records)
      :ok
    end
  end

  # Step 4: Ensure pgmq queue exists for this workflow
  defp ensure_workflow_queue(workflow_slug, repo) do
    result =
      repo.query(
        "SELECT pgflow.ensure_workflow_queue($1)",
        [workflow_slug]
      )

    case result do
      {:ok, _} ->
        Logger.debug("RunInitializer: Ensured queue exists", workflow_slug: workflow_slug)
        :ok

      {:error, reason} ->
        Logger.error("RunInitializer: Failed to ensure queue",
          workflow_slug: workflow_slug,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Step 5: Call start_ready_steps() to mark root steps as 'started' and send to pgmq
  # NOTE: start_ready_steps now creates task records AND sends messages to pgmq
  defp start_ready_steps(run_id, repo) do
    # Call PostgreSQL function via raw SQL
    result =
      repo.query(
        "SELECT * FROM start_ready_steps($1)",
        [run_id]
      )

    case result do
      {:ok, %{rows: rows}} ->
        Logger.debug("RunInitializer: Started #{length(rows)} ready steps", run_id: run_id)
        :ok

      {:error, reason} ->
        Logger.error("RunInitializer: Failed to start ready steps",
          run_id: run_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end
end
