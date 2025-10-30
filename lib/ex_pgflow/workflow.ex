defmodule ExQuantumFlow.Workflow do
  @moduledoc """
  Compatibility shim that keeps the `use ExQuantumFlow.Workflow` macro working
  after the library was renamed to `QuantumFlow` internally.

  New code should prefer `use QuantumFlow.Workflow`, but keeping this module
  avoids updating every umbrella app immediately.
  """

  defmacro __using__(opts \\ []) do
    quote do
      use QuantumFlow.Workflow, unquote(opts)
    end
  end
end
