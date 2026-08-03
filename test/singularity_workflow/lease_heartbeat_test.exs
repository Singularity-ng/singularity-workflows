defmodule Singularity.Workflow.LeaseHeartbeatTest do
  @moduledoc """
  Falsifier: mid-attempt lease heartbeat must renew short pgmq VT so a long
  step does not redeliver while still executing (ACE refresh_task_lease /
  C21 execute_with_lease_heartbeat parity).
  """
  use ExUnit.Case, async: false

  alias Singularity.Workflow.DAG.LeaseHeartbeat
  alias Singularity.Workflow.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "during/5 renews short VT so message stays invisible across a long fun" do
    slug = "test_lease_hb_#{System.unique_integer([:positive])}"
    {:ok, _} = Repo.query("SELECT pgmq.create($1)", [slug])

    {:ok, %{rows: [[msg_id]]}} =
      Repo.query("SELECT * FROM pgmq.send($1, $2::jsonb)", [slug, Jason.encode!(%{"k" => 1})])

    # Claim with short visibility (1s) — without heartbeat the msg reappears.
    {:ok, _} =
      Repo.query("SELECT * FROM pgmq.read($1, 1, 1)", [slug])

    {:ok, _} =
      Repo.query("SELECT pgmq.set_vt($1::text, $2::bigint, $3::integer)", [slug, msg_id, 1])

    LeaseHeartbeat.during(
      Repo,
      slug,
      msg_id,
      fn -> Process.sleep(2_500) end,
      interval_ms: 200,
      vt_seconds: 30
    )

    # After 2.5s with only a 1s VT, a redelivery would succeed without renews.
    {:ok, %{rows: rows}} = Repo.query("SELECT * FROM pgmq.read($1, 1, 1)", [slug])
    assert rows == [], "message must stay invisible while heartbeat renews VT; got #{inspect(rows)}"
  end

  test "during/5 aborts fail-closed when mid-attempt set_vt fails" do
    slug = "test_lease_hb_fail_#{System.unique_integer([:positive])}"
    # Nonexistent queue → set_vt errors → attempt must abort.
    assert {:error, :lease_heartbeat_failed} =
             LeaseHeartbeat.during(
               Repo,
               slug,
               9_999_999,
               fn ->
                 Process.sleep(5_000)
                 :should_not_finish
               end,
               interval_ms: 50,
               vt_seconds: 30
             )
  end
end
