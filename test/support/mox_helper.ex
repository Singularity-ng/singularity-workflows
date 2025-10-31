defmodule Singularity.Workflow.Test.MoxHelper do
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
      Mox.defmock(Singularity.Workflow.Notifications.Mock, for: Singularity.Workflow.Notifications.Behaviour)
    rescue
      _ -> :ok
    end

    try do
      Mox.defmock(Singularity.Workflow.Orchestrator.Repository.Mock,
        for: Singularity.Workflow.Orchestrator.Repository.Behaviour
      )
    rescue
      _ -> :ok
    end

    try do
      Mox.defmock(Singularity.Workflow.Executor.Mock, for: Singularity.Workflow.Executor.Behaviour)
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
      import Singularity.Workflow.Test.MoxHelper

      setup :setup_mox_test
    end
  """
  def setup_mox_test(_context) do
    setup_mox()
    :ok
  end
end
