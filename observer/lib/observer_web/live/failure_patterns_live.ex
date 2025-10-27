defmodule ObserverWeb.FailurePatternsLive do
  @moduledoc """
  Failure Patterns Dashboard - Real-time failure analysis and guardrails

  Provides comprehensive failure pattern analytics including:
  - Top failure patterns by frequency
  - Recent failures with root causes
  - Successful fixes and remediation strategies
  - Failure clustering and trend analysis
  """

  use ObserverWeb.DashboardLive, fetch: &Observer.Dashboard.failure_patterns/0

  @impl true
  def render(assigns) do
    data = assigns.data || %{}
    
    # Extract data
    top_patterns = data[:top_patterns] || []
    recent_failures = data[:recent_failures] || []
    successful_fixes = data[:successful_fixes] || []

    ~H"""
    <div class="max-w-7xl mx-auto space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-zinc-900">Failure Patterns & Guardrails</h1>
          <p class="text-sm text-zinc-500">Real-time failure analysis and remediation strategies</p>
        </div>
        <div class="flex items-center gap-2 text-sm text-zinc-500">
          <div class="h-2 w-2 rounded-full bg-green-500"></div>
          <span>Live</span>
        </div>
      </div>

      <!-- Summary Cards -->
      <div class="grid gap-4 md:grid-cols-3">
        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Top Patterns</p>
              <p class="text-2xl font-bold text-zinc-900"><%= length(top_patterns) %></p>
              <p class="text-xs text-zinc-500">Most frequent failure modes</p>
            </div>
            <div class="rounded-full bg-red-100 p-3">
              <svg class="h-6 w-6 text-red-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
              </svg>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Recent Failures</p>
              <p class="text-2xl font-bold text-zinc-900"><%= length(recent_failures) %></p>
              <p class="text-xs text-zinc-500">Last 7 days</p>
            </div>
            <div class="rounded-full bg-amber-100 p-3">
              <svg class="h-6 w-6 text-amber-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-zinc-600">Successful Fixes</p>
              <p class="text-2xl font-bold text-zinc-900"><%= length(successful_fixes) %></p>
              <p class="text-xs text-zinc-500">Proven remediation strategies</p>
            </div>
            <div class="rounded-full bg-green-100 p-3">
              <svg class="h-6 w-6 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
        </div>
      </div>

      <!-- Top Failure Patterns -->
      <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-zinc-900 mb-4">Top Failure Patterns</h2>
        <div class="space-y-3">
          <%= for pattern <- top_patterns do %>
            <div class="flex items-center justify-between py-3 border-b border-zinc-100 last:border-b-0">
              <div class="flex-1">
                <div class="flex items-center gap-3 mb-2">
                  <span class="font-medium text-zinc-900"><%= pattern[:failure_mode] || "Unknown" %></span>
                  <span class="px-2 py-1 text-xs font-medium rounded-full bg-red-100 text-red-800">
                    <%= pattern[:total_frequency] || 0 %> occurrences
                  </span>
                </div>
                <div class="flex items-center gap-4 text-sm text-zinc-500">
                  <span>Story Types: <%= Enum.join(pattern[:story_types] || [], ", ") %></span>
                  <span>Last seen: <%= format_relative_time(pattern[:last_seen_at]) %></span>
                </div>
              </div>
            </div>
          <% end %>
          <%= if length(top_patterns) == 0 do %>
            <div class="text-center text-zinc-500 py-8">
              <p>No failure patterns recorded</p>
              <p class="text-sm">Patterns will appear as failures are analyzed</p>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Recent Failures -->
      <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-zinc-900 mb-4">Recent Failures (Last 7 Days)</h2>
        <div class="space-y-3">
          <%= for failure <- recent_failures do %>
            <div class="flex items-start justify-between py-3 border-b border-zinc-100 last:border-b-0">
              <div class="flex-1">
                <div class="flex items-center gap-3 mb-2">
                  <span class="font-medium text-zinc-900"><%= failure.failure_mode || "Unknown" %></span>
                  <span class="px-2 py-1 text-xs font-medium rounded-full bg-amber-100 text-amber-800">
                    <%= failure.story_type || "Unknown" %>
                  </span>
                  <span class="px-2 py-1 text-xs font-medium rounded-full bg-zinc-100 text-zinc-800">
                    Frequency: <%= failure.frequency || 0 %>
                  </span>
                </div>
                <div class="text-sm text-zinc-600 mb-2">
                  <p><strong>Root Cause:</strong> <%= failure.root_cause || "Not identified" %></p>
                  <%= if failure.execution_error do %>
                    <p class="mt-1"><strong>Error:</strong> <%= truncate_text(failure.execution_error, 100) %></p>
                  <% end %>
                </div>
                <div class="text-xs text-zinc-500">
                  Last seen: <%= format_relative_time(failure.last_seen_at) %>
                </div>
              </div>
            </div>
          <% end %>
          <%= if length(recent_failures) == 0 do %>
            <div class="text-center text-zinc-500 py-8">
              <p>No recent failures recorded</p>
              <p class="text-sm">Failures will appear as they are analyzed</p>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Successful Fixes -->
      <div class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-zinc-900 mb-4">Successful Fixes & Remediation Strategies</h2>
        <div class="space-y-3">
          <%= for fix <- successful_fixes do %>
            <div class="flex items-start gap-3 py-3 border-b border-zinc-100 last:border-b-0">
              <div class="flex-shrink-0">
                <div class="h-2 w-2 rounded-full bg-green-500 mt-2"></div>
              </div>
              <div class="flex-1">
                <div class="text-sm text-zinc-900">
                  <%= if is_map(fix) do %>
                    <%= fix[:description] || fix["description"] || "Fix applied successfully" %>
                  <% else %>
                    <%= fix %>
                  <% end %>
                </div>
                <%= if is_map(fix) and (fix[:applied_at] || fix["applied_at"]) do %>
                  <div class="text-xs text-zinc-500 mt-1">
                    Applied: <%= format_relative_time(fix[:applied_at] || fix["applied_at"]) %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
          <%= if length(successful_fixes) == 0 do %>
            <div class="text-center text-zinc-500 py-8">
              <p>No successful fixes recorded</p>
              <p class="text-sm">Fixes will appear as they are identified and applied</p>
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
  defp format_relative_time(nil), do: "Unknown"
  defp format_relative_time(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, dt)
    
    cond do
      diff_seconds < 60 -> "#{diff_seconds}s ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      true -> "#{div(diff_seconds, 86400)}d ago"
    end
  end
  defp format_relative_time(_), do: "Unknown"

  defp truncate_text(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end
  defp truncate_text(text, _) when is_binary(text), do: text
  defp truncate_text(_, _), do: "N/A"
end