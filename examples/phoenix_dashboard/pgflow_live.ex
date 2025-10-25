defmodule YourAppWeb.PgflowLive do
  @moduledoc """
  Phoenix LiveView dashboard for ex_pgflow workflow monitoring.

  ## Features

  - 📊 Real-time workflow execution status
  - 🔄 Task state breakdown (started, completed, failed)
  - 📈 Queue depth metrics (pgmq)
  - 📋 Active workflows list
  - ⚡ Recent activity timeline
  - 🎯 Step dependency visualization

  ## Installation

  1. Add to your router:

      live "/pgflow", YourAppWeb.PgflowLive

  2. Copy this file to lib/your_app_web/live/pgflow_live.ex

  3. Create the HTML template (see pgflow_live.html.heex)

  4. Add auto-refresh (optional):

      def mount(_params, _session, socket) do
        if connected?(socket) do
          :timer.send_interval(2000, self(), :refresh)
        end
        {:ok, load_data(socket)}
      end

  ## Customization

  - Adjust refresh interval (currently 2s)
  - Add filters (by workflow_slug, status, date range)
  - Add pagination for large result sets
  - Add search functionality
  - Export metrics to Prometheus/DataDog
  """

  use Phoenix.LiveView
  import Ecto.Query
  alias Pgflow.Repo

  @refresh_interval 2000  # 2 seconds

  # LiveView Callbacks

  @impl true
  def mount(_params, _session, socket) do
    # Auto-refresh if connected (WebSocket)
    if connected?(socket) do
      :timer.send_interval(@refresh_interval, self(), :refresh)
    end

    {:ok, load_data(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_data(socket)}
  end

  # Data Loading

  defp load_data(socket) do
    socket
    |> assign(:stats, load_stats())
    |> assign(:active_workflows, load_active_workflows())
    |> assign(:queue_depths, load_queue_depths())
    |> assign(:recent_completions, load_recent_completions())
    |> assign(:step_states, load_step_states())
    |> assign(:last_updated, DateTime.utc_now())
  end

  # Stats Queries

  defp load_stats do
    %{
      total_workflows: count_workflows(),
      running_workflows: count_running_workflows(),
      completed_workflows: count_completed_workflows(),
      failed_workflows: count_failed_workflows(),
      total_tasks: count_tasks(),
      running_tasks: count_running_tasks(),
      completed_tasks: count_completed_tasks(),
      failed_tasks: count_failed_tasks()
    }
  end

  defp count_workflows do
    from(w in "workflow_runs", select: count(w.id))
    |> Repo.one()
  end

  defp count_running_workflows do
    from(w in "workflow_runs", where: w.status == "running", select: count(w.id))
    |> Repo.one()
  end

  defp count_completed_workflows do
    from(w in "workflow_runs", where: w.status == "completed", select: count(w.id))
    |> Repo.one()
  end

  defp count_failed_workflows do
    from(w in "workflow_runs", where: w.status == "failed", select: count(w.id))
    |> Repo.one()
  end

  defp count_tasks do
    from(t in "workflow_step_tasks", select: count(t.run_id))
    |> Repo.one()
  end

  defp count_running_tasks do
    from(t in "workflow_step_tasks", where: t.status == "started", select: count(t.run_id))
    |> Repo.one()
  end

  defp count_completed_tasks do
    from(t in "workflow_step_tasks", where: t.status == "completed", select: count(t.run_id))
    |> Repo.one()
  end

  defp count_failed_tasks do
    from(t in "workflow_step_tasks", where: t.status == "failed", select: count(t.run_id))
    |> Repo.one()
  end

  # Active Workflows

  defp load_active_workflows do
    query = """
    SELECT
      w.id,
      w.workflow_slug,
      w.status,
      w.remaining_steps,
      w.created_at,
      w.updated_at,
      COUNT(DISTINCT s.step_slug) as total_steps,
      COUNT(DISTINCT CASE WHEN s.status = 'completed' THEN s.step_slug END) as completed_steps,
      COUNT(DISTINCT t.task_index) as total_tasks,
      COUNT(DISTINCT CASE WHEN t.status = 'completed' THEN t.task_index END) as completed_tasks
    FROM workflow_runs w
    LEFT JOIN workflow_step_states s ON w.id = s.run_id
    LEFT JOIN workflow_step_tasks t ON w.id = t.run_id
    WHERE w.status IN ('running', 'pending')
    GROUP BY w.id, w.workflow_slug, w.status, w.remaining_steps, w.created_at, w.updated_at
    ORDER BY w.created_at DESC
    LIMIT 20
    """

    case Repo.query(query) do
      {:ok, result} ->
        Enum.map(result.rows, fn [id, slug, status, remaining, created, updated, total_steps, completed_steps, total_tasks, completed_tasks] ->
          %{
            id: id,
            workflow_slug: slug,
            status: status,
            remaining_steps: remaining,
            created_at: created,
            updated_at: updated,
            total_steps: total_steps,
            completed_steps: completed_steps,
            total_tasks: total_tasks,
            completed_tasks: completed_tasks,
            progress: calculate_progress(completed_tasks, total_tasks)
          }
        end)

      {:error, _} -> []
    end
  end

  # Queue Depths (pgmq)

  defp load_queue_depths do
    # Query pgmq for queue depths
    # This uses pgmq's internal tables to show message counts
    query = """
    SELECT
      queue_name,
      COUNT(*) as pending_messages
    FROM pgmq.q_pgflow
    WHERE vt > NOW()
    GROUP BY queue_name
    ORDER BY pending_messages DESC
    """

    case Repo.query(query) do
      {:ok, result} ->
        Enum.map(result.rows, fn [queue_name, count] ->
          %{queue_name: queue_name, pending: count}
        end)

      # If pgmq table doesn't exist or query fails, return empty
      {:error, _} -> []
    end
  end

  # Recent Completions

  defp load_recent_completions do
    query = """
    SELECT
      w.id,
      w.workflow_slug,
      w.status,
      w.created_at,
      w.updated_at,
      EXTRACT(EPOCH FROM (w.updated_at - w.created_at)) as duration_seconds
    FROM workflow_runs w
    WHERE w.status IN ('completed', 'failed')
    ORDER BY w.updated_at DESC
    LIMIT 10
    """

    case Repo.query(query) do
      {:ok, result} ->
        Enum.map(result.rows, fn [id, slug, status, created, updated, duration] ->
          %{
            id: id,
            workflow_slug: slug,
            status: status,
            created_at: created,
            updated_at: updated,
            duration_seconds: Float.round(duration || 0.0, 2)
          }
        end)

      {:error, _} -> []
    end
  end

  # Step States Breakdown

  defp load_step_states do
    query = """
    SELECT
      s.workflow_slug,
      s.step_slug,
      s.status,
      s.remaining_tasks,
      s.remaining_deps,
      COUNT(t.task_index) as task_count,
      COUNT(CASE WHEN t.status = 'completed' THEN 1 END) as completed_count,
      COUNT(CASE WHEN t.status = 'failed' THEN 1 END) as failed_count
    FROM workflow_step_states s
    LEFT JOIN workflow_step_tasks t ON s.run_id = t.run_id AND s.step_slug = t.step_slug
    WHERE s.status != 'completed'
    GROUP BY s.workflow_slug, s.step_slug, s.status, s.remaining_tasks, s.remaining_deps
    ORDER BY s.workflow_slug, s.step_slug
    LIMIT 50
    """

    case Repo.query(query) do
      {:ok, result} ->
        Enum.map(result.rows, fn [workflow, step, status, remaining_tasks, remaining_deps, task_count, completed, failed] ->
          %{
            workflow_slug: workflow,
            step_slug: step,
            status: status,
            remaining_tasks: remaining_tasks,
            remaining_deps: remaining_deps,
            task_count: task_count,
            completed_count: completed,
            failed_count: failed
          }
        end)

      {:error, _} -> []
    end
  end

  # Helpers

  defp calculate_progress(_completed, 0), do: 0
  defp calculate_progress(completed, total) when is_integer(completed) and is_integer(total) do
    Float.round(completed / total * 100, 1)
  end
  defp calculate_progress(_, _), do: 0

  defp format_duration(seconds) when is_float(seconds) do
    cond do
      seconds < 60 -> "#{Float.round(seconds, 1)}s"
      seconds < 3600 -> "#{Float.round(seconds / 60, 1)}m"
      true -> "#{Float.round(seconds / 3600, 1)}h"
    end
  end

  defp status_color(status) do
    case status do
      "running" -> "text-blue-600"
      "completed" -> "text-green-600"
      "failed" -> "text-red-600"
      "pending" -> "text-yellow-600"
      _ -> "text-gray-600"
    end
  end

  defp status_badge(status) do
    case status do
      "running" -> "bg-blue-100 text-blue-800"
      "completed" -> "bg-green-100 text-green-800"
      "failed" -> "bg-red-100 text-red-800"
      "pending" -> "bg-yellow-100 text-yellow-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end
end
