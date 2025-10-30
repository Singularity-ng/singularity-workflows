defmodule ObserverWeb.ValidationMetricsStoreLive do
  @moduledoc """
  Validation Metrics Store Dashboard - Real-time validation effectiveness metrics

  Provides comprehensive validation analytics including:
  - Validation accuracy (KPI #1)
  - Execution success rate (KPI #2) 
  - Time to validation (KPI #3)
  - Effectiveness scores by check type
  - Aggregated metrics by model/task_type/provider
  """

  use ObserverWeb.DashboardLive, fetch: &Observer.Dashboard.validation_metrics_store/0

  @impl true
  def render(assigns) do
    data = assigns.data || %{}
    
    # Extract metrics
    validation_accuracy = data[:validation_accuracy] || 0
    execution_success_rate = data[:execution_success_rate] || 0
    avg_validation_time = data[:avg_validation_time] || 0
    effectiveness_scores = data[:effectiveness_scores] || %{}
    aggregated_metrics = data[:aggregated_metrics] || []

    ~H"""
    <div class="max-w-7xl mx-auto space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-zinc-900">Validation Metrics Store</h1>
          <p class="text-sm text-zinc-500">Real-time validation effectiveness and execution metrics</p>
        </div>
        <div class="flex items-center gap-2 text-sm text-zinc-500">
          <div class="h-2 w-2 rounded-full bg-green-500"></div>
          <span>Live</span>
        </div>
      </div>

      <!-- Core KPIs -->
      <div class="grid gap-4 md:grid-cols-3">
        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Validation Accuracy</p>
              <p class="text-2xl font-bold text-zinc-900"><%= percent(validation_accuracy) %></p>
              <p class="text-xs text-zinc-500">KPI #1 - Checks that predict success</p>
            </div>
            <div class="rounded-full bg-blue-100 p-3">
              <svg class="h-6 w-6 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Execution Success Rate</p>
              <p class="text-2xl font-bold text-zinc-900"><%= percent(execution_success_rate) %></p>
              <p class="text-xs text-zinc-500">KPI #2 - Plans that executed successfully</p>
            </div>
            <div class="rounded-full bg-green-100 p-3">
              <svg class="h-6 w-6 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Avg Validation Time</p>
              <p class="text-2xl font-bold text-zinc-900"><%= avg_validation_time %>ms</p>
              <p class="text-xs text-zinc-500">KPI #3 - Time spent in validation</p>
            </div>
            <div class="rounded-full bg-purple-100 p-3">
              <svg class="h-6 w-6 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
        </div>
      </div>

      <!-- Effectiveness Scores -->
      <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-zinc-900 mb-4">Check Effectiveness Scores</h2>
        <div class="space-y-3">
          <%= for {check_id, score} <- effectiveness_scores do %>
            <div class="flex items-center justify-between py-2">
              <div class="flex items-center gap-3">
                <div class="h-2 w-2 rounded-full bg-blue-500"></div>
                <span class="font-medium text-zinc-900"><%= check_id %></span>
              </div>
              <div class="flex items-center gap-4">
                <div class="w-32 bg-zinc-200 rounded-full h-2">
                  <div class="bg-blue-500 h-2 rounded-full" style={"width: #{score * 100}%"}></div>
                </div>
                <span class="text-sm font-medium text-zinc-600 w-12 text-right"><%= percent(score) %></span>
              </div>
            </div>
          <% end %>
          <%= if map_size(effectiveness_scores) == 0 do %>
            <div class="text-center text-zinc-500 py-8">
              <p>No effectiveness data available</p>
              <p class="text-sm">Check scores will appear as validation checks are recorded</p>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Aggregated Metrics by Model -->
      <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-zinc-900 mb-4">Model Performance</h2>
        <div class="space-y-3">
          <%= for metric <- aggregated_metrics do %>
            <div class="flex items-center justify-between py-2 border-b border-zinc-100 last:border-b-0">
              <div class="flex items-center gap-3">
                <div class="h-2 w-2 rounded-full bg-green-500"></div>
                <span class="font-medium text-zinc-900"><%= metric[:model] || "Unknown" %></span>
              </div>
              <div class="flex items-center gap-4 text-sm text-zinc-600">
                <span><%= metric[:count] || 0 %> executions</span>
                <span><%= format_currency((metric[:cost_cents] || 0) / 100) %></span>
                <span><%= metric[:avg_latency_ms] || 0 %>ms avg</span>
                <span class="px-2 py-1 text-xs font-medium rounded-full bg-green-100 text-green-800">
                  <%= percent((metric[:success_rate] || 0)) %>
                </span>
              </div>
            </div>
          <% end %>
          <%= if length(aggregated_metrics) == 0 do %>
            <div class="text-center text-zinc-500 py-8">
              <p>No model performance data available</p>
              <p class="text-sm">Metrics will appear as executions are recorded</p>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Raw Data (Debug) -->
      <details class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <summary class="cursor-pointer text-sm font-medium text-zinc-600 hover:text-zinc-900">
          Raw Data (Debug)
        </summary>
        <pre class="mt-4 overflow-auto text-xs text-zinc-500"><%= Jason.encode!(data, pretty: true) %></pre>
      </details>
    </div>
    """
  end

  # Helper functions
  defp percent(value) when is_number(value) do
    "#{Float.round(value * 100, 1)}%"
  end
  defp percent(_), do: "0%"

  defp format_currency(value) when is_number(value) do
    "$#{Float.round(value, 4)}"
  end
  defp format_currency(_), do: "$0.0000"
end