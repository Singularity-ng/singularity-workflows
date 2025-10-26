defmodule Pgflow.ClockTest do
  use ExUnit.Case, async: false

  alias Pgflow.{Clock, TestClock}

  @moduledoc """
  Tests for deterministic clock behavior.

  These tests verify that:
  1. TestClock provides deterministic timestamps
  2. Time advances predictably
  3. Multiple runs produce identical timestamps
  """

  describe "Clock behaviour - default implementation" do
    test "now/0 returns current UTC time" do
      time1 = Clock.now()
      Process.sleep(10)
      time2 = Clock.now()

      # Real clock should advance
      assert DateTime.compare(time2, time1) in [:gt, :eq]
    end

    test "advance/1 is a no-op for real clock" do
      assert Clock.advance(5000) == :ok
    end
  end

  describe "TestClock - deterministic behavior" do
    setup do
      # Reset clock before each test for isolation
      TestClock.reset()
      :ok
    end

    test "reset/0 sets clock to default start time" do
      TestClock.reset()
      time = TestClock.now()

      assert time == ~U[2025-01-01 00:00:00.000000Z]
    end

    test "reset/1 sets clock to custom start time" do
      custom_time = ~U[2024-06-15 10:30:00.000000Z]
      TestClock.reset(custom_time)

      assert TestClock.now() == custom_time
    end

    test "now/0 returns same time on multiple calls" do
      time1 = TestClock.now()
      Process.sleep(10)
      time2 = TestClock.now()

      # TestClock should NOT advance without explicit advance/1 call
      assert time1 == time2
    end

    test "advance/1 increments time by milliseconds" do
      TestClock.reset()
      time1 = TestClock.now()

      TestClock.advance(5000)
      time2 = TestClock.now()

      assert DateTime.diff(time2, time1, :millisecond) == 5000
    end

    test "advance/1 can be called multiple times" do
      TestClock.reset()
      start_time = TestClock.now()

      TestClock.advance(1000)
      TestClock.advance(2000)
      TestClock.advance(3000)

      final_time = TestClock.now()

      assert DateTime.diff(final_time, start_time, :millisecond) == 6000
    end

    test "advance/1 by 1 minute" do
      TestClock.reset()

      TestClock.advance(60_000)

      assert TestClock.now() == ~U[2025-01-01 00:01:00.000000Z]
    end

    test "advance/1 by 1 hour" do
      TestClock.reset()

      TestClock.advance(3_600_000)

      assert TestClock.now() == ~U[2025-01-01 01:00:00.000000Z]
    end
  end

  describe "TestClock - determinism verification" do
    test "same sequence produces identical timestamps across multiple runs" do
      # Run 1
      TestClock.reset()
      run1_t1 = TestClock.now()
      TestClock.advance(5000)
      run1_t2 = TestClock.now()
      TestClock.advance(10_000)
      run1_t3 = TestClock.now()

      # Run 2 (reset and repeat)
      TestClock.reset()
      run2_t1 = TestClock.now()
      TestClock.advance(5000)
      run2_t2 = TestClock.now()
      TestClock.advance(10_000)
      run2_t3 = TestClock.now()

      # All timestamps should be identical
      assert run1_t1 == run2_t1
      assert run1_t2 == run2_t2
      assert run1_t3 == run2_t3
    end

    test "10 consecutive runs produce identical timestamps" do
      results =
        for _i <- 1..10 do
          TestClock.reset()
          t1 = TestClock.now()
          TestClock.advance(1000)
          t2 = TestClock.now()
          TestClock.advance(2000)
          t3 = TestClock.now()

          [t1, t2, t3]
        end

      # All runs should produce the same sequence
      [first_run | other_runs] = results

      Enum.each(other_runs, fn run ->
        assert run == first_run
      end)
    end
  end

  describe "TestClock - integration with Application config" do
    test "Application.get_env returns TestClock in test environment" do
      clock = Application.get_env(:ex_pgflow, :clock)

      assert clock == Pgflow.TestClock
    end

    test "using configured clock for timestamps" do
      TestClock.reset()
      clock = Application.get_env(:ex_pgflow, :clock, Pgflow.Clock)

      time1 = clock.now()
      clock.advance(5000)
      time2 = clock.now()

      assert DateTime.diff(time2, time1, :millisecond) == 5000
    end
  end

  describe "TestClock - edge cases" do
    test "advance/1 with zero milliseconds" do
      TestClock.reset()
      time1 = TestClock.now()

      TestClock.advance(0)
      time2 = TestClock.now()

      assert time1 == time2
    end

    test "advance/1 with large millisecond value (1 day)" do
      TestClock.reset()

      TestClock.advance(86_400_000)

      assert TestClock.now() == ~U[2025-01-02 00:00:00.000000Z]
    end

    test "multiple resets in sequence" do
      TestClock.reset()
      TestClock.advance(5000)

      TestClock.reset()
      time_after_reset = TestClock.now()

      assert time_after_reset == ~U[2025-01-01 00:00:00.000000Z]
    end
  end
end
