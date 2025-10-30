defmodule QuantumFlow.Test.MoxHelper do
  @moduledoc """
  Helper module for setting up Mox mocks in tests.
  """

  @doc """
  Setup Mox mocks for tests that need them.
  """
  def setup_mox do
    # Define all required mocks using Mox.defmock
    # Mox is loaded as a dependency and doesn't need to be started as an application
    try do
      Mox.defmock(QuantumFlow.Notifications.Mock, for: QuantumFlow.Notifications.Behaviour)
    rescue
      _ -> :ok
    end

    try do
      Mox.defmock(QuantumFlow.Orchestrator.Repository.Mock, for: QuantumFlow.Orchestrator.Repository.Behaviour)
    rescue
      _ -> :ok
    end

    try do
      Mox.defmock(QuantumFlow.Executor.Mock, for: QuantumFlow.Executor.Behaviour)
    rescue
      _ -> :ok
    end

    :ok
  end

  @doc """
  Use this in your test module to setup Mox.

  Example:
    defmodule MyTest do
      use ExUnit.Case
      import QuantumFlow.Test.MoxHelper

      setup :setup_mox_test
    end
  """
  def setup_mox_test(_context) do
    setup_mox()
    :ok
  end
end
