if System.get_env("PGFLOW_SKIP_DB") != "1" do
  defmodule QuantumFlow.Orchestrator.ExecutorTest do
    use ExUnit.Case, async: true

  alias QuantumFlow.Orchestrator.Executor

  setup :verify_on_exit!

  describe "execute_workflow/4" do
    test "executes workflow successfully with monitoring" do
      workflow = %{
        id: "workflow_123",
        name: "test_workflow",
        steps: [],
        max_parallel: 10
      }

      context = %{goal: "Build auth system"}

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :create_execution, fn _, _ ->
        {:ok, %{id: "exec_123", execution_id: "exec_123", status: "running"}}
      end)

      Mox.stub(QuantumFlow.Executor.Mock, :execute, fn _, _, _ ->
        {:ok, %{success: true, results: %{"task1" => "result1"}}}
      end)

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :update_execution_status, fn _, _, _, _ ->
        {:ok, %{id: "exec_123", status: "completed"}}
      end)

      {:ok, result} = Executor.execute_workflow(workflow, context, %Ecto.Repo{}, 
        monitor: true, timeout: 60_000)

      assert result.success == true
      assert result.results["task1"] == "result1"
    end

    test "handles execution failure" do
      workflow = %{
        id: "workflow_123",
        name: "test_workflow",
        steps: [],
        max_parallel: 10
      }

      context = %{goal: "Build auth system"}

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :create_execution, fn _, _ ->
        {:ok, %{id: "exec_123", execution_id: "exec_123", status: "running"}}
      end)

      Mox.stub(QuantumFlow.Executor.Mock, :execute, fn _, _, _ ->
        {:error, :execution_failed}
      end)

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :update_execution_status, fn _, _, _, _ ->
        {:ok, %{id: "exec_123", status: "failed"}}
      end)

      {:error, :execution_failed} = Executor.execute_workflow(workflow, context, %Ecto.Repo{})
    end

    test "handles execution record creation failure" do
      workflow = %{
        id: "workflow_123",
        name: "test_workflow",
        steps: [],
        max_parallel: 10
      }

      context = %{goal: "Build auth system"}

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :create_execution, fn _, _ ->
        {:error, :database_error}
      end)

      {:error, :database_error} = Executor.execute_workflow(workflow, context, %Ecto.Repo{})
    end
  end

  describe "execute_task/5" do
    test "executes task successfully" do
      task_config = %{
        name: :task1,
        function: fn _ -> {:ok, "result1"} end,
        description: "Task 1",
        timeout: 30_000,
        max_attempts: 3
      }

      context = %{goal: "Build auth system"}
      execution = %{id: "exec_123", execution_id: "exec_123"}

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :create_task_execution, fn _, _ ->
        {:ok, %{id: "task_exec_123", task_id: "task1", status: "pending"}}
      end)

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :update_task_execution_status, fn _, _, _, _ ->
        {:ok, %{id: "task_exec_123", status: "completed"}}
      end)

      {:ok, result} = Executor.execute_task(task_config, context, execution, %Ecto.Repo{})

      assert result == "result1"
    end

    test "handles task execution failure" do
      task_config = %{
        name: :task1,
        function: fn _ -> {:error, :task_failed} end,
        description: "Task 1",
        timeout: 30_000,
        max_attempts: 1
      }

      context = %{goal: "Build auth system"}
      execution = %{id: "exec_123", execution_id: "exec_123"}

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :create_task_execution, fn _, _ ->
        {:ok, %{id: "task_exec_123", task_id: "task1", status: "pending"}}
      end)

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :update_task_execution_status, fn _, _, _, _ ->
        {:ok, %{id: "task_exec_123", status: "failed"}}
      end)

      {:error, :task_failed} = Executor.execute_task(task_config, context, execution, %Ecto.Repo{})
    end

    test "retries failed tasks" do
      task_config = %{
        name: :task1,
        function: fn _ -> {:error, :task_failed} end,
        description: "Task 1",
        timeout: 30_000,
        max_attempts: 3,
        retry_delay: 100
      }

      context = %{goal: "Build auth system"}
      execution = %{id: "exec_123", execution_id: "exec_123"}

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :create_task_execution, fn _, _ ->
        {:ok, %{id: "task_exec_123", task_id: "task1", status: "pending"}}
      end)

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :update_task_execution_status, fn _, _, _, _ ->
        {:ok, %{id: "task_exec_123", status: "failed"}}
      end)

      {:error, :max_retries_exceeded} = Executor.execute_task(task_config, context, execution, %Ecto.Repo{})
    end
  end

  describe "get_execution_status/2" do
    test "returns execution status and progress" do
      execution = %{
        id: "exec_123",
        execution_id: "exec_123",
        status: "running",
        started_at: DateTime.utc_now(),
        completed_at: nil,
        duration_ms: nil
      }

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :get_execution, fn _, _ ->
        {:ok, execution}
      end)

      Mox.stub(QuantumFlow.Orchestrator.Executor.Mock, :get_task_executions, fn _, _ ->
        {:ok, [
          %{task_id: "task1", status: "completed"},
          %{task_id: "task2", status: "running"},
          %{task_id: "task3", status: "pending"}
        ]}
      end)

      {:ok, status} = Executor.get_execution_status("exec_123", %Ecto.Repo{})

      assert status.execution_id == "exec_123"
      assert status.status == "running"
      assert status.total_tasks == 3
      assert status.completed_tasks == 1
      assert status.running_tasks == 1
      assert status.pending_tasks == 1
      assert status.progress_percentage == 33.333333333333336
    end

    test "handles execution not found" do
      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :get_execution, fn _, _ ->
        {:error, :not_found}
      end)

      {:error, :not_found} = Executor.get_execution_status("nonexistent", %Ecto.Repo{})
    end
  end

  describe "cancel_execution/3" do
    test "cancels running execution successfully" do
      execution = %{
        id: "exec_123",
        execution_id: "exec_123",
        status: "running"
      }

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :get_execution, fn _, _ ->
        {:ok, execution}
      end)

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :update_execution_status, fn _, _, _, _ ->
        {:ok, %{id: "exec_123", status: "cancelled"}}
      end)

      :ok = Executor.cancel_execution("exec_123", %Ecto.Repo{}, reason: "User requested")
    end

    test "handles execution not found" do
      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :get_execution, fn _, _ ->
        {:error, :not_found}
      end)

      {:error, :not_found} = Executor.cancel_execution("nonexistent", %Ecto.Repo{})
    end

    test "handles execution not running" do
      execution = %{
        id: "exec_123",
        execution_id: "exec_123",
        status: "completed"
      }

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :get_execution, fn _, _ ->
        {:ok, execution}
      end)

      {:error, :execution_not_running} = Executor.cancel_execution("exec_123", %Ecto.Repo{})
    end

    test "force cancels non-running execution" do
      execution = %{
        id: "exec_123",
        execution_id: "exec_123",
        status: "completed"
      }

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :get_execution, fn _, _ ->
        {:ok, execution}
      end)

      Mox.stub(QuantumFlow.Orchestrator.Repository.Mock, :update_execution_status, fn _, _, _, _ ->
        {:ok, %{id: "exec_123", status: "cancelled"}}
      end)

      :ok = Executor.cancel_execution("exec_123", %Ecto.Repo{}, force: true)
    end
  end
end
