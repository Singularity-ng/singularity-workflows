defmodule Pgflow do
  @moduledoc """
  Pgflow - Complete workflow orchestration for Elixir.

  A unified package providing complete workflow orchestration capabilities,
  combining PGMQ-based message queuing, HTDAG goal decomposition, workflow execution,
  and real-time notifications. Converts high-level goals into executable task graphs
  with automatic dependency resolution and parallel execution.

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

  ## HTDAG Integration

  Pgflow includes `Pgflow.HTDAG` for goal-driven workflow creation:

      # Define a decomposer function
      defmodule MyApp.GoalDecomposer do
        def decompose(goal) do
          # Your custom decomposition logic
          tasks = [
            %{id: "task1", description: "Analyze requirements", depends_on: []},
            %{id: "task2", description: "Design architecture", depends_on: ["task1"]},
            %{id: "task3", description: "Implement solution", depends_on: ["task2"]}
          ]
          {:ok, tasks}
        end
      end

      # Compose and execute workflow from goal
      {:ok, result} = Pgflow.WorkflowComposer.compose_from_goal(
        "Build user authentication system",
        &MyApp.GoalDecomposer.decompose/1,
        step_functions,
        MyApp.Repo
      )

  ## Real-time Notifications

  Pgflow includes `Pgflow.Notifications` for real-time message delivery:

      # Send message with real-time notification
      {:ok, message_id} = Pgflow.Notifications.send_with_notify(
        "chat_messages",
        %{type: "notification", content: "Hello!"},
        MyApp.Repo
      )

      # Listen for real-time updates
      {:ok, pid} = Pgflow.Notifications.listen("chat_messages", MyApp.Repo)

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

  ## Real-time Notifications

  ex_pgflow includes `Pgflow.Notifications` for real-time workflow events with comprehensive logging:

      # Send workflow event with NOTIFY
      {:ok, message_id} = Pgflow.Notifications.send_with_notify(
        "workflow_events", 
        %{type: "task_completed", task_id: "123"}, 
        MyApp.Repo
      )

      # Listen for real-time workflow events
      {:ok, pid} = Pgflow.Notifications.listen("workflow_events", MyApp.Repo)
      
      # All NOTIFY events are automatically logged with structured data:
      # - Queue names, message IDs, timing, message types
      # - Success/error logging with context
      # - Performance metrics and debugging information

  ### Notification Types

  | Event Type | Description | Payload |
  |------------|-------------|---------|
  | `workflow_started` | Workflow execution begins | `{workflow_id, input}` |
  | `task_started` | Individual task starts | `{task_id, workflow_id, step_name}` |
  | `task_completed` | Task finishes successfully | `{task_id, result, duration_ms}` |
  | `task_failed` | Task fails with error | `{task_id, error, retry_count}` |
  | `workflow_completed` | Entire workflow finishes | `{workflow_id, final_result}` |
  | `workflow_failed` | Workflow fails | `{workflow_id, error, failed_task}` |

  ### Integration Examples

      # Observer Web UI integration
      {:ok, _} = Pgflow.Notifications.send_with_notify("observer_approvals", %{
        type: "approval_created",
        approval_id: "app_123",
        title: "Deploy to Production"
      }, MyApp.Repo)

      # CentralCloud pattern learning
      {:ok, _} = Pgflow.Notifications.send_with_notify("centralcloud_patterns", %{
        type: "pattern_learned",
        pattern_type: "microservice_architecture",
        confidence_score: 0.95
      }, MyApp.Repo)

      # Genesis autonomous learning
      {:ok, _} = Pgflow.Notifications.send_with_notify("genesis_learning", %{
        type: "rule_evolved",
        rule_type: "optimization",
        improvement: 0.12
      }, MyApp.Repo)

  ## Orchestrator Integration

  ex_pgflow includes `Pgflow.Orchestrator` for goal-driven workflow creation:

      # Define a decomposer function
      defmodule MyApp.GoalDecomposer do
        def decompose(goal) do
          # Your custom decomposition logic
          tasks = [
            %{id: "task1", description: "Analyze requirements", depends_on: []},
            %{id: "task2", description: "Design architecture", depends_on: ["task1"]},
            %{id: "task3", description: "Implement solution", depends_on: ["task2"]}
          ]
          {:ok, tasks}
        end
      end

      # Compose and execute workflow from goal
      {:ok, result} = Pgflow.WorkflowComposer.compose_from_goal(
        "Build user authentication system",
        &MyApp.GoalDecomposer.decompose/1,
        step_functions,
        MyApp.Repo
      )
  """

  defdelegate send_with_notify(queue, message, repo), to: Pgflow.Notifications
  defdelegate listen(queue, repo), to: Pgflow.Notifications
  defdelegate unlisten(listener_pid, repo), to: Pgflow.Notifications
  defdelegate notify_only(channel, payload, repo), to: Pgflow.Notifications

  @doc """
  Returns the current version of ex_pgflow.

  ## Examples

      iex> Pgflow.version()
      "0.1.0"
  """
  @spec version() :: String.t()
  def version, do: "0.1.0"
end
