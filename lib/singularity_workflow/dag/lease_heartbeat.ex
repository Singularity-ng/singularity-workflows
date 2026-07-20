defmodule Singularity.Workflow.DAG.LeaseHeartbeat do
  @moduledoc """
  Mid-attempt pgmq visibility renewals while a claimed HTDAG task executes.

  Algorithm from ACE `TaskQueue.refresh_task_lease` / C21
  `execute_with_lease_heartbeat`: renew `pgmq.set_vt` on an interval so long
  attempts outlive the claim lease (default LEASE_VT=1200s, heartbeat at VT/4).
  A renew failure aborts the attempt fail-closed (C21 parity).
  """

  require Logger

  @lease_vt_seconds 1200
  @default_interval_ms div(@lease_vt_seconds, 4) * 1000

  @doc """
  Run `fun` while renewing claim VT for `message_id` every interval.

  Options:
  - `:interval_ms` — heartbeat period (default Application env or VT/4)
  - `:vt_seconds` — renew target (default 1200)

  Returns `fun.()` on success, or `{:error, :lease_heartbeat_failed}` when a
  mid-attempt renew fails (attempt is shut down).
  """
  @spec during(module(), String.t(), integer() | nil, (-> result), keyword()) ::
          result | {:error, :lease_heartbeat_failed}
        when result: term()
  def during(_repo, _workflow_slug, nil, fun, _opts) when is_function(fun, 0), do: fun.()

  def during(repo, workflow_slug, message_id, fun, opts)
      when is_integer(message_id) and is_function(fun, 0) do
    interval_ms =
      Keyword.get_lazy(opts, :interval_ms, fn ->
        Application.get_env(
          :singularity_workflow,
          :lease_heartbeat_interval_ms,
          @default_interval_ms
        )
      end)

    vt_seconds = Keyword.get(opts, :vt_seconds, @lease_vt_seconds)
    task = Task.async(fun)
    await_with_heartbeat(task, repo, workflow_slug, message_id, interval_ms, vt_seconds)
  end

  defp await_with_heartbeat(task, repo, workflow_slug, message_id, interval_ms, vt_seconds) do
    ref = task.ref

    receive do
      {^ref, result} ->
        result
    after
      interval_ms ->
        case renew(repo, workflow_slug, message_id, vt_seconds) do
          :ok ->
            await_with_heartbeat(
              task,
              repo,
              workflow_slug,
              message_id,
              interval_ms,
              vt_seconds
            )

          :error ->
            _ = Task.shutdown(task, :brutal_kill)

            Logger.warning("LeaseHeartbeat: aborting attempt after set_vt failure",
              workflow_slug: workflow_slug,
              message_id: message_id
            )

            {:error, :lease_heartbeat_failed}
        end
    end
  end

  defp renew(repo, workflow_slug, message_id, vt_seconds) do
    case repo.query(
           "SELECT pgmq.set_vt($1::text, $2::bigint, $3::integer)",
           [workflow_slug, message_id, vt_seconds],
           timeout: 5_000
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("LeaseHeartbeat: set_vt failed",
          workflow_slug: workflow_slug,
          message_id: message_id,
          reason: inspect(reason)
        )

        :error
    end
  rescue
    e ->
      Logger.warning("LeaseHeartbeat: set_vt raised",
        workflow_slug: workflow_slug,
        message_id: message_id,
        error: Exception.message(e)
      )

      :error
  end
end
