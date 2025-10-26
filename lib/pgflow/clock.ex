defmodule Pgflow.Clock do
  @moduledoc """
  Clock behaviour for abstracting time-related operations.

  This enables deterministic testing by allowing time to be controlled in tests
  while using real time in production.

  ## Behaviour Callbacks

  - `now/0` - Returns the current DateTime (UTC)
  - `advance/1` - Advances time by the given milliseconds (test-only)

  ## Default Implementation

  The default implementation uses `DateTime.utc_now()` for real-time behavior.

  ## Test Implementation

  `Pgflow.TestClock` provides a controllable clock for deterministic testing:

      # In test setup
      Pgflow.TestClock.reset()

      # In tests
      time1 = TestClock.now()
      TestClock.advance(5000)  # Advance 5 seconds
      time2 = TestClock.now()
      assert DateTime.diff(time2, time1, :millisecond) == 5000

  ## Configuration

  Configure which clock implementation to use:

      # config/test.exs
      config :ex_pgflow, :clock, Pgflow.TestClock

      # config/prod.exs (default)
      config :ex_pgflow, :clock, Pgflow.Clock

  ## Usage in Modules

      defmodule MyModule do
        def create_record do
          clock = Application.get_env(:ex_pgflow, :clock, Pgflow.Clock)
          timestamp = clock.now()
          # ...
        end
      end
  """

  @doc """
  Returns the current DateTime in UTC.
  """
  @callback now() :: DateTime.t()

  @doc """
  Advances the clock by the given number of milliseconds.

  This is primarily for testing. Production implementations should ignore this.
  """
  @callback advance(milliseconds :: non_neg_integer()) :: :ok

  @doc """
  Default implementation: Returns current UTC time.
  """
  def now do
    DateTime.utc_now()
  end

  @doc """
  Default implementation: No-op (cannot advance real time).
  """
  def advance(_milliseconds), do: :ok
end
