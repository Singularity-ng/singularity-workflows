defmodule Pgflow.TestClock do
  @moduledoc """
  Test adapter for deterministic clock behavior in tests.

  Uses an Agent to maintain a fixed "current time" that can be manually
  advanced for testing time-dependent behavior without actual delays.

  ## Benefits

  - **Deterministic**: Same test always produces same timestamps
  - **Fast**: No Process.sleep() calls needed
  - **Controllable**: Manually advance time to test timeouts/delays
  - **Reproducible**: Easy to debug timing-related test failures

  ## Usage

      # In test setup (before each test)
      Pgflow.TestClock.reset()

      # In tests
      time1 = Pgflow.TestClock.now()
      # => ~U[2025-01-01 00:00:00.000000Z]

      Pgflow.TestClock.advance(5000)  # Advance 5 seconds

      time2 = Pgflow.TestClock.now()
      # => ~U[2025-01-01 00:00:05.000000Z]

      # Test timeout behavior
      Pgflow.TestClock.advance(60_000)  # Advance 1 minute
      # Now you can test what happens after timeout without waiting

  ## Initial Time

  The clock starts at `2025-01-01 00:00:00.000000 UTC` by default.
  Call `reset/0` or `reset/1` to change the starting time.

  ## Configuration

      # config/test.exs
      config :ex_pgflow, :clock, Pgflow.TestClock

  ## Implementation

  Uses an Agent to store the current time. The Agent is started automatically
  on first use (lazy initialization).
  """

  @behaviour Pgflow.Clock

  use Agent

  @default_start_time ~U[2025-01-01 00:00:00.000000Z]

  @doc """
  Returns the current time from the test clock.

  The time is stored in an Agent and can be advanced with `advance/1`.
  """
  @impl Pgflow.Clock
  def now do
    ensure_started()
    Agent.get(__MODULE__, & &1)
  end

  @doc """
  Advances the clock by the given number of milliseconds.

  ## Examples

      iex> Pgflow.TestClock.reset()
      iex> time1 = Pgflow.TestClock.now()
      iex> Pgflow.TestClock.advance(5000)
      iex> time2 = Pgflow.TestClock.now()
      iex> DateTime.diff(time2, time1, :millisecond)
      5000

      # Advance by 1 minute
      iex> Pgflow.TestClock.reset()
      iex> Pgflow.TestClock.advance(60_000)
      iex> Pgflow.TestClock.now()
      ~U[2025-01-01 00:01:00.000000Z]
  """
  @impl Pgflow.Clock
  def advance(milliseconds) when is_integer(milliseconds) and milliseconds >= 0 do
    ensure_started()

    Agent.update(__MODULE__, fn current_time ->
      DateTime.add(current_time, milliseconds, :millisecond)
    end)

    :ok
  end

  @doc """
  Resets the clock to the default start time (2025-01-01 00:00:00 UTC).

  Call this in your test setup to ensure deterministic test behavior.

  ## Examples

      setup do
        Pgflow.TestClock.reset()
        :ok
      end
  """
  def reset do
    reset(@default_start_time)
  end

  @doc """
  Resets the clock to a specific DateTime.

  ## Examples

      iex> custom_time = ~U[2024-06-15 10:30:00.000000Z]
      iex> Pgflow.TestClock.reset(custom_time)
      iex> Pgflow.TestClock.now()
      ~U[2024-06-15 10:30:00.000000Z]
  """
  def reset(%DateTime{} = start_time) do
    case ensure_started() do
      :ok ->
        # Try to update, but handle if Agent died between ensure_started and update
        try do
          Agent.update(__MODULE__, fn _current -> start_time end)
          :ok
        catch
          :exit, _reason ->
            # Agent died, restart it
            case start_link(start_time: start_time) do
              {:ok, _pid} -> :ok
              {:error, {:already_started, _pid}} -> :ok
              error -> error
            end
        end

      {:error, _reason} ->
        # Agent failed to start, try to start it synchronously
        case start_link(start_time: start_time) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end
    end
  end

  @doc """
  Starts the TestClock Agent if not already started.

  This is called automatically by other functions, so you typically don't
  need to call it manually.
  """
  def start_link(opts \\ []) do
    start_time = Keyword.get(opts, :start_time, @default_start_time)
    Agent.start_link(fn -> start_time end, name: __MODULE__)
  end

  # Private helper to ensure the Agent is started (lazy initialization)
  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        case start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end

      _pid ->
        :ok
    end
  end
end
