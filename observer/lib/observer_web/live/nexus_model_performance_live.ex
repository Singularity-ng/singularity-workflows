defmodule ObserverWeb.NexusModelPerformanceLive do
  @moduledoc """
  Nexus Model Performance Dashboard - Real-time model usage and performance metrics

  Provides detailed performance analytics including:
  - Model usage statistics and trends
  - Response times and success rates by model
  - Cost analysis per model
  - Provider performance breakdown
  - Most used and most expensive models
  """

  use ObserverWeb.DashboardLive, fetch: &Observer.Dashboard.nexus_model_performance/0

  @impl true
  def render(assigns) do
    dashboard = assigns.data || %{}
    
    # Extract dashboard sections
    overview = dashboard[:overview] || %{}
    most_used_models = dashboard[:most_used_models] || []
    most_expensive_models = dashboard[:most_expensive_models] || []
    provider_breakdown = dashboard[:provider_breakdown] || %{}
    raw_data = dashboard[:raw_data] || %{}

    ~H"""
    <div class="max-w-7xl mx-auto space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-zinc-900">Model Performance</h1>
          <p class="text-sm text-zinc-500">Real-time model usage and performance metrics</p>
        </div>
        <div class="flex items-center gap-2 text-sm text-zinc-500">
          <div class="h-2 w-2 rounded-full bg-green-500"></div>
          <span>Live</span>
        </div>
      </div>

      <!-- Overview Stats -->
      <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Total Requests</p>
              <p class="text-2xl font-bold text-zinc-900"><%= overview[:total_requests] || 0 %></p>
            </div>
            <div class="rounded-full bg-blue-100 p-3">
              <svg class="h-6 w-6 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
              </svg>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Total Cost</p>
              <p class="text-2xl font-bold text-zinc-900"><%= format_currency(overview[:total_cost] || 0) %></p>
            </div>
            <div class="rounded-full bg-green-100 p-3">
              <svg class="h-6 w-6 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1" />
              </svg>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Avg Response Time</p>
              <p class="text-2xl font-bold text-zinc-900"><%= overview[:avg_response_time] || 0 %>ms</p>
            </div>
            <div class="rounded-full bg-purple-100 p-3">
              <svg class="h-6 w-6 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Success Rate</p>
              <p class="text-2xl font-bold text-zinc-900"><%= percent(overview[:success_rate] || 0) %></p>
            </div>
            <div class="rounded-full bg-emerald-100 p-3">
              <svg class="h-6 w-6 text-emerald-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
        </div>
      </div>

      <!-- Most Used Models -->
      <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-zinc-900 mb-4">Most Used Models</h2>
        <div class="space-y-3">
          <%= for {model, %{count: count, cost: cost, avg_response_time: avg_time}} <- Enum.take(most_used_models, 10) do %>
            <div class="flex items-center justify-between py-2 border-b border-zinc-100 last:border-b-0">
              <div class="flex items-center gap-3">
                <div class="h-2 w-2 rounded-full bg-blue-500"></div>
                <span class="font-medium text-zinc-900"><%= model %></span>
              </div>
              <div class="flex items-center gap-4 text-sm text-zinc-600">
                <span><%= count %> requests</span>
                <span><%= format_currency(cost) %></span>
                <span><%= avg_time %>ms avg</span>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Most Expensive Models -->
      <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-zinc-900 mb-4">Most Expensive Models</h2>
        <div class="space-y-3">
          <%= for {model, %{cost: cost, count: count, cost_per_request: cost_per_req}} <- Enum.take(most_expensive_models, 10) do %>
            <div class="flex items-center justify-between py-2 border-b border-zinc-100 last:border-b-0">
              <div class="flex items-center gap-3">
                <div class="h-2 w-2 rounded-full bg-red-500"></div>
                <span class="font-medium text-zinc-900"><%= model %></span>
              </div>
              <div class="flex items-center gap-4 text-sm text-zinc-600">
                <span><%= format_currency(cost) %> total</span>
                <span><%= format_currency(cost_per_req) %>/req</span>
                <span><%= count %> requests</span>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Provider Breakdown -->
      <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-zinc-900 mb-4">Provider Breakdown</h2>
        <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <%= for {provider, %{requests: requests, cost: cost, success_rate: success_rate}} <- provider_breakdown do %>
            <div class="rounded-lg border border-zinc-200 p-4">
              <div class="flex items-center justify-between mb-2">
                <h3 class="font-medium text-zinc-900"><%= String.capitalize(to_string(provider)) %></h3>
                <span class="text-sm text-zinc-500"><%= requests %> requests</span>
              </div>
              <div class="space-y-1">
                <div class="flex justify-between text-sm">
                  <span class="text-zinc-600">Cost:</span>
                  <span class="font-medium"><%= format_currency(cost) %></span>
                </div>
                <div class="flex justify-between text-sm">
                  <span class="text-zinc-600">Success Rate:</span>
                  <span class="font-medium"><%= percent(success_rate) %></span>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Raw Data (Debug) -->
      <details class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <summary class="cursor-pointer text-sm font-medium text-zinc-600 hover:text-zinc-900">
          Raw Data (Debug)
        </summary>
        <pre class="mt-4 overflow-auto text-xs text-zinc-500"><%= Jason.encode!(raw_data, pretty: true) %></pre>
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