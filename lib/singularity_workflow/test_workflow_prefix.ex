defmodule Singularity.Workflow.TestWorkflowPrefix do
  @moduledoc """
  Test workflow naming utility for safe, collision-free test isolation.

  Provides unique prefixes per test run using UUID-based identifiers instead of
  hardcoded "test_" prefixes. This prevents test workflow name collisions when
  running multiple test instances in parallel or sequential batches.

  ## Usage

      # In test setup
      {:ok, prefix} = Singularity.Workflow.TestWorkflowPrefix.start()

      # Create test workflows with prefix
      workflow_slug = prefix <> "my_workflow"
      {:ok, _} = FlowBuilder.create_flow(workflow_slug, Repo)

      # Clean up after test
      Singularity.Workflow.TestWorkflowPrefix.cleanup_by_prefix(prefix, Repo)

  ## Design

  - Each test run gets a unique UUID-based prefix
  - Prefix format: "singularity_workflow_test_<short_uuid>_"
  - Separates test data by prefix instead of hardcoded pattern matching
  - Enables parallel test execution without naming conflicts
  - Supports cleanup of test data by prefix
  """

  require Logger

  @doc """
  Start a new test run with a unique prefix.

  Returns a UUID-based prefix that can be used for all test workflows in this run.
  """
  @spec start() :: String.t()
  def start() do
    short_uuid = Ecto.UUID.generate() |> String.slice(0..7)
    "singularity_workflow_test_#{short_uuid}_"
  end

  @doc """
  Clean up all workflows with a specific prefix.

  Deletes workflows, steps, and dependencies matching the given prefix.
  Uses exact SQL deletion instead of LIKE pattern for better safety.
  """
  @spec cleanup_by_prefix(String.t(), module()) :: {:ok, integer()} | {:error, term()}
  def cleanup_by_prefix(prefix, repo) do
    # Get all workflow slugs starting with the prefix
    with {:ok, %{rows: workflow_rows}} <-
           repo.query(
             "SELECT workflow_slug FROM workflows WHERE workflow_slug LIKE $1::text",
             ["#{prefix}%"]
           ) do
      # Extract workflow slugs
      workflow_slugs = Enum.map(workflow_rows, fn [slug] -> slug end)

      # Delete dependencies for all matching workflows
      with {:ok, _} <-
             repo.query(
               "DELETE FROM workflow_step_dependencies_def WHERE workflow_slug = ANY($1::text[])",
               [workflow_slugs]
             ),
           {:ok, _} <-
             repo.query(
               "DELETE FROM workflow_steps WHERE workflow_slug = ANY($1::text[])",
               [workflow_slugs]
             ),
           {:ok, result} <-
             repo.query(
               "DELETE FROM workflows WHERE workflow_slug = ANY($1::text[])",
               [workflow_slugs]
             ) do
        deleted_count = result.num_rows
        Logger.info("Cleaned up #{deleted_count} test workflows with prefix: #{prefix}")
        {:ok, deleted_count}
      else
        {:error, reason} ->
          Logger.error("Failed to cleanup test workflows with prefix #{prefix}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to query test workflows with prefix #{prefix}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
