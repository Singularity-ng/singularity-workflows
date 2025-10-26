defmodule ObserverWeb.NexusModelDiscoveryLive do
  @moduledoc """
  Nexus Model Discovery Dashboard - Dynamic model discovery and availability monitoring

  Provides real-time discovery status including:
  - Provider discovery status and health
  - Model counts by provider
  - Discovery errors and issues
  - Fallback chain status
  - Model availability trends
  """

  use ObserverWeb.DashboardLive, fetch: &Observer.Dashboard.nexus_model_discovery/0

  @impl true
  def render(assigns) do
    discovery_status = assigns.data || %{}
    
    # Extract discovery data
    providers = discovery_status[:providers] || %{}
    total_providers = discovery_status[:total_providers] || 0
    successful_discoveries = discovery_status[:successful_discoveries] || 0
    failed_discoveries = discovery_status[:failed_discoveries] || 0
    total_models = discovery_status[:total_models] || 0
    discovery_errors = discovery_status[:discovery_errors] || []
    last_discovery = discovery_status[:last_discovery] || nil
    raw_data = discovery_status[:raw_data] || %{}

    ~H"""
    <div class="max-w-7xl mx-auto space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-zinc-900">Model Discovery</h1>
          <p class="text-sm text-zinc-500">Dynamic model discovery and availability monitoring</p>
        </div>
        <div class="flex items-center gap-2 text-sm text-zinc-500">
          <div class="h-2 w-2 rounded-full bg-green-500"></div>
          <span>Live</span>
        </div>
      </div>

      <!-- Discovery Overview -->
      <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Total Providers</p>
              <p class="text-2xl font-bold text-zinc-900"><%= total_providers %></p>
            </div>
            <div class="rounded-full bg-blue-100 p-3">
              <svg class="h-6 w-6 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
              </svg>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Total Models</p>
              <p class="text-2xl font-bold text-zinc-900"><%= total_models %></p>
            </div>
            <div class="rounded-full bg-green-100 p-3">
              <svg class="h-6 w-6 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
              </svg>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Successful</p>
              <p class="text-2xl font-bold text-zinc-900"><%= successful_discoveries %></p>
            </div>
            <div class="rounded-full bg-emerald-100 p-3">
              <svg class="h-6 w-6 text-emerald-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Failed</p>
              <p class="text-2xl font-bold text-zinc-900"><%= failed_discoveries %></p>
            </div>
            <div class="rounded-full bg-red-100 p-3">
              <svg class="h-6 w-6 text-red-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
        </div>
      </div>

      <!-- Provider Status -->
      <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-zinc-900 mb-4">Provider Status</h2>
        <div class="space-y-3">
          <%= for {provider, %{status: status, model_count: model_count, last_checked: last_checked, error: error}} <- providers do %>
            <div class="flex items-center justify-between py-3 border-b border-zinc-100 last:border-b-0">
              <div class="flex items-center gap-3">
                <div class={"h-2 w-2 rounded-full #{status_badge_class(status)}"}></div>
                <div>
                  <span class="font-medium text-zinc-900"><%= String.capitalize(to_string(provider)) %></span>
                  <div class="text-sm text-zinc-500">
                    <%= model_count %> models
                    <%= if last_checked do %>
                      • Last checked: <%= format_relative_time(last_checked) %>
                    <% end %>
                  </div>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <span class={"px-2 py-1 text-xs font-medium rounded-full #{status_badge_class(status)}"}>
                  <%= status_icon(status) %> <%= String.capitalize(to_string(status)) %>
                </span>
                <%= if error do %>
                  <span class="text-xs text-red-600" title={error}>⚠️</span>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Discovery Summary -->
      <div class="grid gap-4 md:grid-cols-2">
        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <h3 class="text-lg font-semibold text-zinc-900 mb-4">Discovery Summary</h3>
          <div class="space-y-3">
            <div class="flex justify-between">
              <span class="text-zinc-600">Success Rate:</span>
              <span class="font-medium"><%= percent(successful_discoveries / max(total_providers, 1)) %></span>
            </div>
            <div class="flex justify-between">
              <span class="text-zinc-600">Total Models Found:</span>
              <span class="font-medium"><%= total_models %></span>
            </div>
            <%= if last_discovery do %>
              <div class="flex justify-between">
                <span class="text-zinc-600">Last Discovery:</span>
                <span class="font-medium"><%= format_relative_time(last_discovery) %></span>
              </div>
            <% end %>
          </div>
        </div>

        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <h3 class="text-lg font-semibold text-zinc-900 mb-4">Status Distribution</h3>
          <div class="space-y-2">
            <%= for {status, count} <- status_distribution(providers) do %>
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <div class={"h-2 w-2 rounded-full #{status_badge_class(status)}"}></div>
                  <span class="text-sm text-zinc-600"><%= String.capitalize(to_string(status)) %></span>
                </div>
                <span class="text-sm font-medium"><%= count %></span>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Discovery Errors -->
      <%= if length(discovery_errors) > 0 do %>
        <div class="rounded-xl border border-red-200 bg-red-50 p-6 shadow-sm">
          <h3 class="text-lg font-semibold text-red-900 mb-4">Discovery Errors</h3>
          <div class="space-y-2">
            <%= for error <- Enum.take(discovery_errors, 5) do %>
              <div class="text-sm text-red-700 bg-red-100 rounded p-2">
                <%= error %>
              </div>
            <% end %>
            <%= if length(discovery_errors) > 5 do %>
              <div class="text-sm text-red-600">
                ... and <%= length(discovery_errors) - 5 %> more errors
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

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

  defp status_icon(:healthy), do: "✅"
  defp status_icon(:unhealthy), do: "❌"
  defp status_icon(:discovering), do: "🔄"
  defp status_icon(:unknown), do: "❓"
  defp status_icon(_), do: "❓"

  defp status_badge_class(:healthy), do: "bg-green-500"
  defp status_badge_class(:unhealthy), do: "bg-red-500"
  defp status_badge_class(:discovering), do: "bg-yellow-500"
  defp status_badge_class(:unknown), do: "bg-gray-500"
  defp status_badge_class(_), do: "bg-gray-500"

  defp format_relative_time(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _} -> format_relative_time(dt)
      _ -> datetime
    end
  end
  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime)
    
    cond do
      diff_seconds < 60 -> "#{diff_seconds}s ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      true -> "#{div(diff_seconds, 86400)}d ago"
    end
  end
  defp format_relative_time(_), do: "Unknown"

  defp status_distribution(providers) do
    providers
    |> Enum.map(fn {_provider, %{status: status}} -> status end)
    |> Enum.frequencies()
  end
end