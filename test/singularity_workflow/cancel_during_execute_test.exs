defmodule Singularity.Workflow.CancelDuringExecuteTest do
  @moduledoc """
  Falsifier: cancel_workflow_run during a live execute_dynamic map fan-out must
  archive every process message_id so cancelled runs cannot poll-spin after VT.
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.{Executor, FlowBuilder, Repo, StepTask, WorkflowRun}
  import Ecto.Query

  @n 64

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Singularity.Workflow.TestClock.reset()
    {:ok, _} = Singularity.Workflow.TestWorkflowPrefix.cleanup_by_prefix("test_cancel_dyn_", Repo)
    :ok
  end

  test "cancel mid execute_dynamic archives map fan-out pgmq messages" do
    slug = "test_cancel_dyn_n#{@n}"
    items = Enum.to_list(1..@n)

    assert {:ok, _} = FlowBuilder.create_flow(slug, Repo)

    assert {:ok, _} =
             FlowBuilder.add_step(slug, "fetch", [], Repo, step_type: "single", initial_tasks: 1)

    assert {:ok, _} =
             FlowBuilder.add_step(slug, "process", ["fetch"], Repo,
               step_type: "map",
               initial_tasks: @n
             )

    gate = start_supervised!({Agent, fn -> :hold end}, id: :cancel_dyn_gate)
    entered = start_supervised!({Agent, fn -> 0 end}, id: :cancel_dyn_entered)

    step_functions = %{
      fetch: fn _input -> {:ok, items} end,
      process: fn input ->
        Agent.update(entered, &(&1 + 1))

        # Block until released so cancel can land mid-fan-out.
        wait_until(fn -> Agent.get(gate, & &1) == :release end, 30_000)
        {:ok, %{"item" => input}}
      end
    }

    exec =
      Task.async(fn ->
        Executor.execute_dynamic(slug, %{}, step_functions, Repo,
          timeout: 60_000,
          poll_interval: 25
        )
      end)

    wait_until(fn -> Agent.get(entered, & &1) >= 1 end, 15_000)

    run =
      from(r in WorkflowRun, where: r.workflow_slug == ^slug, order_by: [desc: r.inserted_at], limit: 1)
      |> Repo.one()

    assert run != nil
    assert :ok = Executor.cancel_workflow_run(run.id, Repo, reason: "cancel mid execute_dynamic")

    Agent.update(gate, fn _ -> :release end)

    # Executor may return ok (drained) or error (run cancelled) — either is fine
    # as long as pgmq cannot redeliver archived map messages.
    _ = Task.await(exec, 60_000)

    statuses =
      from(t in StepTask,
        where: t.workflow_slug == ^slug and t.step_slug == "process",
        select: t.status
      )
      |> Repo.all()

    assert length(statuses) == @n
    assert Enum.all?(statuses, &(&1 in ["cancelled", "completed", "failed"]))
    assert Enum.any?(statuses, &(&1 == "cancelled")),
           "at least one map task must be cancelled; got #{inspect(statuses)}"

    cancelled_count = Enum.count(statuses, &(&1 == "cancelled"))
    assert cancelled_count >= 1

    # Force VT open — archived msgs must not redeliver.
    {:ok, %{rows: read_rows}} =
      Repo.query("SELECT msg_id FROM pgmq.read($1, 1, $2)", [slug, @n + 5])

    read_ids = Enum.map(read_rows, fn [mid] -> mid end)
    refute Enum.any?(read_ids),
           "cancelled fan-out must not leave readable pgmq msgs; got #{inspect(read_ids)}"
  end

  defp wait_until(pred, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Stream.repeatedly(fn ->
      if pred.() do
        :ok
      else
        if System.monotonic_time(:millisecond) > deadline do
          flunk("wait_until timed out after #{timeout_ms}ms")
        end

        Process.sleep(20)
        :cont
      end
    end)
    |> Enum.find(&(&1 == :ok))
  end
end
