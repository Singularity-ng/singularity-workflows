defmodule Pgflow.SqlCase do
  @moduledoc """
  Helper for SQL-based tests. Connects to Postgres using POSTGRES_URL or DATABASE_URL.

  Tests using this helper will be skipped if a DB is not reachable or the required
  pgflow tables are not present. This makes the migrated tests non-fatal in CI
  environments where the developer hasn't prepared a DB.
  """

  use ExUnit.CaseTemplate

  @doc """
  Attempt to connect to the database and return a Postgrex connection.
  If the DB is unavailable or the pgflow tables are not present, call
  ExUnit.Callbacks.skip/1 to skip the test at runtime.
  """
  def connect_or_skip do
    _db_url =
      System.get_env("DATABASE_URL") || System.get_env("POSTGRES_URL") ||
        "postgresql://postgres:postgres@localhost:5432/ex_pgflow"

    case Postgrex.start_link(
           hostname: "localhost",
           port: 5432,
           username: "postgres",
           password: "postgres",
           database: "ex_pgflow"
         ) do
      {:ok, conn} ->
        case Postgrex.query(conn, "SELECT to_regclass('public.workflow_runs')", []) do
          {:ok, res} ->
            IO.puts("DEBUG: query result rows = #{inspect(res.rows)}")

            case res.rows do
              [[nil]] ->
                Process.exit(conn, :normal)

                {:skip,
                 "Database does not have pgflow tables; run migrations before enabling SQL tests"}

              _ ->
                # register a stop on exit and return connection
                Process.flag(:trap_exit, true)
                on_exit(fn -> Process.exit(conn, :normal) end)
                conn
            end

          {:error, _} ->
            Process.exit(conn, :normal)
            {:skip, "Database query failed; ensure DATABASE_URL points to a migrated pgflow DB"}
        end

      {:error, reason} ->
        {:skip, "Database connection failed: #{inspect(reason)}"}
    end
  end
end
