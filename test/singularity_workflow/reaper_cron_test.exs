defmodule Singularity.Workflow.ReaperCronTest do
  use ExUnit.Case, async: false
  use Singularity.Workflow.SqlCase

  @moduledoc """
  Integration proof for HTDAG reaper pg_cron schedules.

  Falsifier: after migration, when pg_cron is installed, both job names exist
  in cron.job. Skips cleanly when the extension is absent.
  """

  @tag :integration
  test "htdag reaper cron jobs are scheduled when pg_cron is present" do
    case Singularity.Workflow.SqlCase.connect_or_skip() do
      {:skip, reason} ->
        IO.puts("SKIPPED: #{reason}")
        assert true

      conn ->
        case Postgrex.query(conn, "SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'", []) do
          {:ok, %{rows: []}} ->
            IO.puts("SKIPPED: pg_cron not installed (migration is fail-soft)")
            assert true

          {:ok, _} ->
            %{rows: rows} =
              Postgrex.query!(
                conn,
                """
                SELECT jobname, schedule
                FROM cron.job
                WHERE jobname IN (
                  'htdag-rearm-stuck-started',
                  'htdag-enqueue-orphaned-steps'
                )
                ORDER BY jobname
                """,
                []
              )

            names = Enum.map(rows, fn [name, _sched] -> name end)

            assert "htdag-enqueue-orphaned-steps" in names
            assert "htdag-rearm-stuck-started" in names

          {:error, reason} ->
            flunk("cron.job query failed: #{inspect(reason)}")
        end
    end
  end
end
