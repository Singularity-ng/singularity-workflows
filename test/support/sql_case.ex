defmodule Singularity.Workflow.SqlCase do
  @moduledoc """
  Helper for SQL-based tests. Connects to Postgres via DATABASE_URL / POSTGRES_URL
  or PGHOST/PGUSER/PGPASSWORD/PGDATABASE (defaults: 127.0.0.1 / postgres /
  singularity_workflow_test).

  Tests using this helper skip when the DB is unreachable or required tables are
  absent, so CI without a prepared DB stays non-fatal.
  """

  use ExUnit.CaseTemplate

  @doc """
  Attempt to connect and return a Postgrex connection.
  Returns `{:skip, reason}` when the DB or Singularity.Workflow tables are missing.
  """
  def connect_or_skip do
    case Postgrex.start_link(connection_opts()) do
      {:ok, conn} ->
        case Postgrex.query(conn, "SELECT to_regclass('public.workflow_runs')", []) do
          {:ok, %{rows: [[nil]]}} ->
            Process.exit(conn, :normal)

            {:skip,
             "Database does not have Singularity.Workflow tables; run migrations before enabling SQL tests"}

          {:ok, _} ->
            Process.flag(:trap_exit, true)
            on_exit(fn -> Process.exit(conn, :normal) end)
            conn

          {:error, _} ->
            Process.exit(conn, :normal)

            {:skip,
             "Database query failed; ensure DATABASE_URL points to a migrated Singularity.Workflow DB"}
        end

      {:error, reason} ->
        {:skip, "Database connection failed: #{inspect(reason)}"}
    end
  end

  @doc "Postgrex start_link opts (TCP defaults for race / multi-conn SQL tests)."
  def connection_opts do
    case System.get_env("DATABASE_URL") || System.get_env("POSTGRES_URL") do
      url when is_binary(url) and url != "" ->
        uri = URI.parse(url)
        {user, pass} = split_userinfo(uri.userinfo)

        [
          hostname: uri.host || "127.0.0.1",
          port: uri.port || 5432,
          username: user || System.get_env("PGUSER") || "postgres",
          password: pass || System.get_env("PGPASSWORD") || "",
          database: database_from_path(uri.path) || "singularity_workflow_test"
        ]

      _ ->
        [
          # Prefer 127.0.0.1 over localhost so Postgrex uses TCP, not /run/postgresql.
          hostname: System.get_env("PGHOST") || "127.0.0.1",
          port: String.to_integer(System.get_env("PGPORT") || "5432"),
          username: System.get_env("PGUSER") || "postgres",
          password: System.get_env("PGPASSWORD") || "",
          database: System.get_env("PGDATABASE") || "singularity_workflow_test"
        ]
    end
  end

  defp split_userinfo(nil), do: {nil, nil}

  defp split_userinfo(info) do
    case String.split(info, ":", parts: 2) do
      [u] -> {URI.decode(u), ""}
      [u, p] -> {URI.decode(u), URI.decode(p)}
    end
  end

  defp database_from_path(nil), do: nil
  defp database_from_path("/"), do: nil
  defp database_from_path("/" <> name), do: name
  defp database_from_path(other), do: other
end
