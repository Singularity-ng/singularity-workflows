defmodule Pgflow do
  @moduledoc """
  Elixir implementation of pgflow's database-driven DAG (Directed Acyclic Graph) execution.

  Matches pgflow's proven architecture using PostgreSQL + pgmq extension for
  workflow coordination with 100% feature parity.

  ## Dynamic vs Static Workflows

  ex_pgflow supports TWO ways to define workflows:

  ### 1. Static (Code-Based) - Recommended for most use cases

  Define workflows as Elixir modules with `__workflow_steps__/0`:

      defmodule MyWorkflow do
        def __workflow_steps__ do
          [{:step1, &__MODULE__.step1/1, depends_on: []}]
        end
        def step1(input), do: {:ok, input}
      end

      Pgflow.Executor.execute(MyWorkflow, input, repo)

  ### 2. Dynamic (Database-Stored) - For AI/LLM generation

  Create workflows at runtime via FlowBuilder API:

      {:ok, _} = Pgflow.FlowBuilder.create_flow("ai_workflow", repo)
      {:ok, _} = Pgflow.FlowBuilder.add_step("ai_workflow", "step1", [], repo)

      step_functions = %{step1: fn input -> {:ok, input} end}
      Pgflow.Executor.execute_dynamic("ai_workflow", input, step_functions, repo)

  **Both approaches use the same execution engine!**

  ## Architecture

  ex_pgflow uses the same architecture as pgflow (TypeScript):

  - **pgmq Extension** - PostgreSQL Message Queue for task coordination
  - **Database-Driven** - Task state persisted in PostgreSQL tables
  - **DAG Syntax** - Define dependencies with `depends_on: [:step]`
  - **Parallel Execution** - Independent branches run concurrently
  - **Map Steps** - Variable task counts (`initial_tasks: N`) for bulk processing
  - **Dependency Merging** - Steps receive outputs from all dependencies
  - **Multi-Instance** - Horizontal scaling via pgmq + PostgreSQL

  ## Quick Start

  1. **Install pgmq extension:**

      psql> CREATE EXTENSION pgmq VERSION '1.4.4';

  2. **Define workflow:**

      defmodule MyApp.Workflows.ProcessData do
        def __workflow_steps__ do
          [
            # Root step
            {:fetch, &__MODULE__.fetch/1, depends_on: []},

            # Parallel branches
            {:analyze, &__MODULE__.analyze/1, depends_on: [:fetch]},
            {:summarize, &__MODULE__.summarize/1, depends_on: [:fetch]},

            # Convergence step
            {:save, &__MODULE__.save/1, depends_on: [:analyze, :summarize]}
          ]
        end

        def fetch(input) do
          {:ok, %{data: "fetched"}}
        end

        def analyze(state) do
          # Has access to fetch output
          {:ok, %{analysis: "done"}}
        end

        def summarize(state) do
          # Runs in parallel with analyze!
          {:ok, %{summary: "complete"}}
        end

        def save(state) do
          # Has access to analyze AND summarize outputs
          {:ok, state}
        end
      end

  3. **Execute workflow:**

      {:ok, result} = Pgflow.Executor.execute(
        MyApp.Workflows.ProcessData,
        %{"user_id" => 123},
        MyApp.Repo
      )

  ## Map Steps (Bulk Processing)

  Process multiple items in parallel:

      def __workflow_steps__ do
        [
          {:fetch_users, &__MODULE__.fetch_users/1, depends_on: []},

          # Create 50 parallel tasks!
          {:process_user, &__MODULE__.process_user/1,
           depends_on: [:fetch_users],
           initial_tasks: 50},

          {:aggregate, &__MODULE__.aggregate/1, depends_on: [:process_user]}
        ]
      end

  ## Requirements

  - **PostgreSQL 12+**
  - **pgmq extension 1.4.4+** - `CREATE EXTENSION pgmq`
  - **Ecto & Postgrex** - For database access

  ## Comparison with pgflow

  | Feature | pgflow (TypeScript) | ex_pgflow (Elixir) |
  |---------|---------------------|---------------------|
  | DAG Syntax | ✅ | ✅ |
  | pgmq Integration | ✅ | ✅ |
  | Parallel Execution | ✅ | ✅ |
  | Map Steps | ✅ | ✅ |
  | Dependency Merging | ✅ | ✅ |
  | Multi-Instance | ✅ | ✅ |
  | Database-Driven | ✅ | ✅ |

  **Result: 100% Feature Parity** 🎉

  See `Pgflow.Executor` for execution options and `Pgflow.DAG.WorkflowDefinition`
  for workflow syntax details.
  """

  @doc """
  Returns the current version of ex_pgflow.

  ## Examples

      iex> Pgflow.version()
      "0.1.0"
  """
  @spec version() :: String.t()
  def version, do: "0.1.0"
end
