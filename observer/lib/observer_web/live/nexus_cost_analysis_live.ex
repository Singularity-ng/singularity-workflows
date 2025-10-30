defmodule ObserverWeb.NexusCostAnalysisLive do
  @moduledoc """
  Nexus Cost Analysis Dashboard - Detailed cost analysis and optimization insights

  Provides comprehensive cost analytics including:
  - Total cost breakdown by time period
  - Cost per request analysis
  - Provider cost comparison
  - Most expensive models
  - Cost trends and projections
  - Budget alerts and recommendations
  """

  use ObserverWeb.DashboardLive, fetch: &Observer.Dashboard.nexus_cost_analysis/0

  @impl true
  def render(assigns) do
    cost_data = assigns.data || %{}
    
    # Extract cost analysis data
    total_cost = cost_data[:total_cost] || 0
    total_requests = cost_data[:total_requests] || 0
    avg_cost_per_request = cost_data[:avg_cost_per_request] || 0
    provider_breakdown = cost_data[:provider_breakdown] || %{}
    top_expensive_models = cost_data[:top_expensive_models] || []
    trends = cost_data[:trends] || %{}
    projections = cost_data[:projections] || %{}
    raw_data = cost_data[:raw_data] || %{}

    ~H"""
    <div class="max-w-7xl mx-auto space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-zinc-900">Cost Analysis</h1>
          <p class="text-sm text-zinc-500">Detailed cost analysis and optimization insights</p>
        </div>
        <div class="flex items-center gap-2 text-sm text-zinc-500">
          <div class="h-2 w-2 rounded-full bg-green-500"></div>
          <span>Live</span>
        </div>
      </div>

      <!-- Cost Overview -->
      <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Total Cost</p>
              <p class="text-2xl font-bold text-zinc-900"><%= format_currency(total_cost) %></p>
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
              <p class="text-sm font-medium text-zinc-600">Total Requests</p>
              <p class="text-2xl font-bold text-zinc-900"><%= total_requests %></p>
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
              <p class="text-sm font-medium text-zinc-600">Avg Cost/Request</p>
              <p class="text-2xl font-bold text-zinc-900"><%= format_currency(avg_cost_per_request) %></p>
            </div>
            <div class="rounded-full bg-purple-100 p-3">
              <svg class="h-6 w-6 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
              </svg>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Cost Trend</p>
              <p class="text-2xl font-bold text-zinc-900"><%= trend_icon(trends[:cost_trend]) %></p>
            </div>
            <div class="rounded-full bg-yellow-100 p-3">
              <svg class="h-6 w-6 text-yellow-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 12l3-3 3 3 4-4M8 21l4-4 4 4M3 4h18M4 4h16v12a1 1 0 01-1 1H5a1 1 0 01-1-1V4z" />
              </svg>
            </div>
          </div>
        </div>
      </div>

      <!-- Provider Cost Breakdown -->
      <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-zinc-900 mb-4">Provider Cost Breakdown</h2>
        <div class="space-y-4">
          <%= for {provider, %{cost: cost, requests: requests, avg_cost_per_request: avg_cost, percentage: percentage}} <- provider_breakdown do %>
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3">
                <div class="h-3 w-3 rounded-full bg-blue-500"></div>
                <span class="font-medium text-zinc-900"><%= String.capitalize(to_string(provider)) %></span>
                <span class="text-sm text-zinc-500">(<%= Float.round(percentage, 1) %>% of total)</span>
              </div>
              <div class="flex items-center gap-4 text-sm text-zinc-600">
                <span><%= format_currency(cost) %></span>
                <span><%= requests %> requests</span>
                <span><%= format_currency(avg_cost) %>/req</span>
              </div>
            </div>
            <div class="w-full bg-zinc-200 rounded-full h-2">
              <div class="bg-blue-500 h-2 rounded-full" style={"width: #{percentage}%"}></div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Most Expensive Models -->
      <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-zinc-900 mb-4">Most Expensive Models</h2>
        <div class="space-y-3">
          <%= for {model, %{total_cost: total_cost, requests: requests, cost_per_request: cost_per_req, provider: provider}} <- Enum.take(top_expensive_models, 10) do %>
            <div class="flex items-center justify-between py-2 border-b border-zinc-100 last:border-b-0">
              <div class="flex items-center gap-3">
                <div class="h-2 w-2 rounded-full bg-red-500"></div>
                <div>
                  <span class="font-medium text-zinc-900"><%= model %></span>
                  <div class="text-xs text-zinc-500">via <%= String.capitalize(to_string(provider)) %></div>
                </div>
              </div>
              <div class="flex items-center gap-4 text-sm text-zinc-600">
                <span><%= format_currency(total_cost) %></span>
                <span><%= format_currency(cost_per_req) %>/req</span>
                <span><%= requests %> requests</span>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Cost Trends and Projections -->
      <div class="grid gap-4 md:grid-cols-2">
        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <h3 class="text-lg font-semibold text-zinc-900 mb-4">Cost Trends</h3>
          <div class="space-y-3">
            <div class="flex justify-between">
              <span class="text-zinc-600">Today vs Yesterday:</span>
              <span class="font-medium"><%= trend_icon(trends[:daily_trend]) %> <%= format_percentage_change(trends[:daily_change]) %></span>
            </div>
            <div class="flex justify-between">
              <span class="text-zinc-600">This Week vs Last Week:</span>
              <span class="font-medium"><%= trend_icon(trends[:weekly_trend]) %> <%= format_percentage_change(trends[:weekly_change]) %></span>
            </div>
            <div class="flex justify-between">
              <span class="text-zinc-600">This Month vs Last Month:</span>
              <span class="font-medium"><%= trend_icon(trends[:monthly_trend]) %> <%= format_percentage_change(trends[:monthly_change]) %></span>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <h3 class="text-lg font-semibold text-zinc-900 mb-4">Projections</h3>
          <div class="space-y-3">
            <div class="flex justify-between">
              <span class="text-zinc-600">Projected This Week:</span>
              <span class="font-medium"><%= format_currency(projections[:week_projection]) %></span>
            </div>
            <div class="flex justify-between">
              <span class="text-zinc-600">Projected This Month:</span>
              <span class="font-medium"><%= format_currency(projections[:month_projection]) %></span>
            </div>
            <div class="flex justify-between">
              <span class="text-zinc-600">Projected This Year:</span>
              <span class="font-medium"><%= format_currency(projections[:year_projection]) %></span>
            </div>
          </div>
        </div>
      </div>

      <!-- Cost Optimization Recommendations -->
      <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-zinc-900 mb-4">Cost Optimization Recommendations</h2>
        <div class="space-y-3">
          <div class="flex items-start gap-3 p-3 bg-blue-50 rounded-lg">
            <div class="text-blue-600">💡</div>
            <div>
              <p class="text-sm font-medium text-blue-900">Consider using cheaper models for simple tasks</p>
              <p class="text-xs text-blue-700">Switch to faster, lower-cost models for basic text processing</p>
            </div>
          </div>
          <div class="flex items-start gap-3 p-3 bg-green-50 rounded-lg">
            <div class="text-green-600">💰</div>
            <div>
              <p class="text-sm font-medium text-green-900">Implement request batching</p>
              <p class="text-xs text-green-700">Batch multiple requests together to reduce per-request overhead</p>
            </div>
          </div>
          <div class="flex items-start gap-3 p-3 bg-yellow-50 rounded-lg">
            <div class="text-yellow-600">⚡</div>
            <div>
              <p class="text-sm font-medium text-yellow-900">Monitor high-cost models</p>
              <p class="text-xs text-yellow-700">Review usage of expensive models and consider alternatives</p>
            </div>
          </div>
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
  defp format_currency(value) when is_number(value) do
    "$#{Float.round(value, 4)}"
  end
  defp format_currency(_), do: "$0.0000"

  defp trend_icon(:up), do: "📈"
  defp trend_icon(:down), do: "📉"
  defp trend_icon(:stable), do: "➡️"
  defp trend_icon(_), do: "❓"

  defp format_percentage_change(value) when is_number(value) do
    "#{Float.round(value * 100, 1)}%"
  end
  defp format_percentage_change(_), do: "0%"
end