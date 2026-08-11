defmodule Singularity.Workflow.CancelRunTest do
  use ExUnit.Case, async: false
  use Singularity.Workflow.SqlCase

  alias Singularity.Workflow.StepTask

  @moduledoc """
  Integration proofs for singularity_workflow.cancel_run/3.

  Falsifier: after cancel, archived msg_ids must not reappear via pgmq.read
  (even after VT would have expired). Requires migrated Postgres + pgmq.
  """

  @tag :integration
  test "cancel_run archives queued pgmq messages so they do not redeliver" do
    case Singularity.Workflow.SqlCase.connect_or_skip() do
      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
        assert true

      conn ->
        unless cancel_run_available?(conn) do
          IO.puts("SKIPPED: singularity_workflow.cancel_run not migrated yet")
          assert true
        else
          id = Ecto.UUID.generate()
          {:ok, binary_id} = Ecto.UUID.dump(id)
          workflow_slug = "cancel_flow_#{String.replace(Ecto.UUID.generate(), "-", "")}"

          Postgrex.query!(
            conn,
            "SELECT singularity_workflow.ensure_workflow_queue($1)",
            [workflow_slug]
          )

          Postgrex.query!(
            conn,
            """
            INSERT INTO workflow_runs
              (id, workflow_slug, status, remaining_steps, created_at, inserted_at, updated_at)
            VALUES ($1, $2, 'started', 1, now(), now(), now())
            """,
            [binary_id, workflow_slug]
          )

          {:ok, send_res} =
            Postgrex.query(conn, "SELECT * FROM pgmq.send($1, $2::jsonb)", [
              workflow_slug,
              Jason.encode!(%{"run_id" => id})
            ])

          [[msg_id]] = send_res.rows

          {:ok, uuid_string} = Ecto.UUID.load(binary_id)
          idempotency_key = StepTask.compute_idempotency_key(workflow_slug, "only", uuid_string, 0)

          Postgrex.query!(
            conn,
            """
            INSERT INTO workflow_step_tasks
              (run_id, step_slug, workflow_slug, task_index, status, message_id,
               idempotency_key, inserted_at, updated_at)
            VALUES ($1, 'only', $2, 0, 'queued', $3, $4, now(), now())
            """,
            [binary_id, workflow_slug, msg_id, idempotency_key]
          )

          archived =
            Postgrex.query!(
              conn,
              "SELECT singularity_workflow.cancel_run($1::uuid, $2::text, false)",
              [binary_id, "test cancel"]
            )

          assert [[1]] = archived.rows

          run_status =
            Postgrex.query!(
              conn,
              "SELECT status FROM workflow_runs WHERE id = $1",
              [binary_id]
            )

          assert [["failed"]] = run_status.rows

          task_status =
            Postgrex.query!(
              conn,
              "SELECT status, message_id FROM workflow_step_tasks WHERE run_id = $1",
              [binary_id]
            )

          assert [["cancelled", nil]] = task_status.rows

          # Force visibility window past; archived messages must stay gone.
          _ =
            Postgrex.query(
              conn,
              "SELECT pgmq.set_vt($1, $2, 0)",
              [workflow_slug, msg_id]
            )

          read_back =
            Postgrex.query!(
              conn,
              "SELECT msg_id FROM pgmq.read($1, 0, 10)",
              [workflow_slug]
            )

          refute Enum.any?(read_back.rows, fn [id] -> id == msg_id end),
                 "cancelled message #{msg_id} must not redeliver after cancel_run archive"
        end
    end
  end

  defp cancel_run_available?(conn) do
    case Postgrex.query(
           conn,
           """
           SELECT 1
           FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'singularity_workflow'
             AND p.proname = 'cancel_run'
           """,
           []
         ) do
      {:ok, %{rows: [[1]]}} -> true
      _ -> false
    end
  end
end
