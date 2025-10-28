defmodule ExPgflow.Workflow do
  @moduledoc """
  Compatibility wrapper exposing `ExPgflow.Workflow`.

  This small wrapper allows code that was refactored to `use ExPgflow.Workflow`
  to compile while reusing the existing `Pgflow.Workflow` implementation.
  """

  defmacro __using__(opts \\ []) do
    quote do
      use Pgflow.Workflow, unquote(opts)
    end
  end
end
