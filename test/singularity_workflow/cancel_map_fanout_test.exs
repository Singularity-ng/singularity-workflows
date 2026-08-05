defmodule Singularity.Workflow.CancelMapFanoutTest do
  use ExUnit.Case, async: false
  use Singularity.Workflow.SqlCase

  alias Singularity.Workflow.StepTask

  @moduledoc """
  Falsifier: cancel_run during map fan-out archives every process message_id
  (not just one), and no archived id redelivers via pgmq.read.
  """

  @tag :integration
  test "cancel_run archives all map fan-out pgmq messages" do
    cancel_map_fanout_archives!(n: 3)
  end

  @tag :integration
  test "cancel_run archives N=64 map fan-out pgmq messages" do
    cancel_map_fanout_archives!(n: 64)
  end

  @tag :integration
  test "concurrent dual cancel_run is idempotent and archives all messages" do
    concurrent_dual_cancel_idempotent!(n: 32)
  end

  defp cancel_map_fanout_archives!(n: n) do
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
          workflow_slug = "cancel_map_#{String.replace(Ecto.UUID.generate(), "-", "")}"

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

          {:ok, uuid_string} = Ecto.UUID.load(binary_id)

          msg_ids =
            Enum.map(0..(n - 1), fn i ->
              {:ok, send_res} =
                Postgrex.query(conn, "SELECT * FROM pgmq.send($1, $2::jsonb)", [
                  workflow_slug,
                  Jason.encode!(%{"run_id" => id, "i" => i})
                ])

              [[msg_id]] = send_res.rows
              key = StepTask.compute_idempotency_key(workflow_slug, "process", uuid_string, i)

              Postgrex.query!(
                conn,
                """
                INSERT INTO workflow_step_tasks
                  (run_id, step_slug, workflow_slug, task_index, status, message_id,
                   idempotency_key, inserted_at, updated_at)
                VALUES ($1, 'process', $2, $3, 'queued', $4, $5, now(), now())
                """,
                [binary_id, workflow_slug, i, msg_id, key]
              )

              msg_id
            end)

          archived =
            Postgrex.query!(
              conn,
              "SELECT singularity_workflow.cancel_run($1::uuid, $2::text, false)",
              [binary_id, "cancel map fan-out n=#{n}"]
            )

          assert [[^n]] = archived.rows

          task_rows =
            Postgrex.query!(
              conn,
              """
              SELECT task_index, status, message_id
              FROM workflow_step_tasks
              WHERE run_id = $1 AND step_slug = 'process'
              ORDER BY task_index
              """,
              [binary_id]
            )

          assert length(task_rows.rows) == n
          assert Enum.all?(task_rows.rows, fn [i, status, mid] ->
                   is_integer(i) and status == "cancelled" and is_nil(mid)
                 end)

          Enum.each(msg_ids, fn msg_id ->
            _ = Postgrex.query(conn, "SELECT pgmq.set_vt($1, $2, 0)", [workflow_slug, msg_id])
          end)

          {:ok, read_res} =
            Postgrex.query(conn, "SELECT msg_id FROM pgmq.read($1, 1, $2)", [
              workflow_slug,
              n + 10
            ])

          read_ids = Enum.map(read_res.rows, fn [msg_id] -> msg_id end)
          refute Enum.any?(msg_ids, &(&1 in read_ids))
        end
    end
  end

  defp concurrent_dual_cancel_idempotent!(n: n) do
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
          workflow_slug = "cancel_dual_#{String.replace(Ecto.UUID.generate(), "-", "")}"

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

          {:ok, uuid_string} = Ecto.UUID.load(binary_id)

          msg_ids =
            Enum.map(0..(n - 1), fn i ->
              {:ok, send_res} =
                Postgrex.query(conn, "SELECT * FROM pgmq.send($1, $2::jsonb)", [
                  workflow_slug,
                  Jason.encode!(%{"run_id" => id, "i" => i})
                ])

              [[msg_id]] = send_res.rows
              key = StepTask.compute_idempotency_key(workflow_slug, "process", uuid_string, i)

              Postgrex.query!(
                conn,
                """
                INSERT INTO workflow_step_tasks
                  (run_id, step_slug, workflow_slug, task_index, status, message_id,
                   idempotency_key, inserted_at, updated_at)
                VALUES ($1, 'process', $2, $3, 'queued', $4, $5, now(), now())
                """,
                [binary_id, workflow_slug, i, msg_id, key]
              )

              msg_id
            end)

          # Two independent connections race cancel_run (FOR UPDATE serializes).
          {:ok, c1} = Postgrex.start_link(Singularity.Workflow.SqlCase.connection_opts())
          {:ok, c2} = Postgrex.start_link(Singularity.Workflow.SqlCase.connection_opts())

          t1 =
            Task.async(fn ->
              Postgrex.query(
                c1,
                "SELECT singularity_workflow.cancel_run($1::uuid, $2::text, false)",
                [binary_id, "dual-a"]
              )
            end)

          t2 =
            Task.async(fn ->
              Postgrex.query(
                c2,
                "SELECT singularity_workflow.cancel_run($1::uuid, $2::text, false)",
                [binary_id, "dual-b"]
              )
            end)

          r1 = Task.await(t1, 15_000)
          r2 = Task.await(t2, 15_000)
          GenServer.stop(c1)
          GenServer.stop(c2)

          assert {:ok, %{rows: [[a1]]}} = r1
          assert {:ok, %{rows: [[a2]]}} = r2
          assert is_integer(a1) and is_integer(a2)
          assert a1 + a2 == n
          assert MapSet.new([a1, a2]) |> MapSet.member?(n)
          assert MapSet.new([a1, a2]) |> MapSet.member?(0)

          task_rows =
            Postgrex.query!(
              conn,
              """
              SELECT status, message_id FROM workflow_step_tasks
              WHERE run_id = $1 AND step_slug = 'process'
              """,
              [binary_id]
            )

          assert length(task_rows.rows) == n
          assert Enum.all?(task_rows.rows, fn [status, mid] ->
                   status == "cancelled" and is_nil(mid)
                 end)

          Enum.each(msg_ids, fn msg_id ->
            _ = Postgrex.query(conn, "SELECT pgmq.set_vt($1, $2, 0)", [workflow_slug, msg_id])
          end)

          {:ok, read_res} =
            Postgrex.query(conn, "SELECT msg_id FROM pgmq.read($1, 1, $2)", [
              workflow_slug,
              n + 10
            ])

          read_ids = Enum.map(read_res.rows, fn [msg_id] -> msg_id end)
          refute Enum.any?(msg_ids, &(&1 in read_ids))
        end
    end
  end

  defp cancel_run_available?(conn) do
    res =
      Postgrex.query!(
        conn,
        """
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'singularity_workflow' AND p.proname = 'cancel_run'
        LIMIT 1
        """,
        []
      )

    res.rows != []
  end
end
