defmodule QuantumFlow.WorkflowAPI.Context do
  @moduledoc """
  Lightweight workflow context struct used when invoking QuantumFlow workflow
  steps outside of the orchestration runtime.

  The production QuantumFlow executor builds workflow contexts dynamically as maps
  that include the original `:input` plus per-step results. Certain parts of
  the umbrella (for example, synchronous code paths that call workflow steps
  directly) still construct a struct to satisfy compile-time references.

  This struct keeps the shape minimal: only the `:input` key is enforced.
  When additional step data is required it is usually better to convert the
  struct to a plain map with `Map.from_struct/1` before attaching dynamic keys.
  """

  @enforce_keys [:input]
  defstruct input: %{}
end

defmodule QuantumFlow.WorkflowContext do
  @moduledoc """
  CamelCase alias of `QuantumFlow.WorkflowAPI.Context` provided for backwards
  compatibility with modules that still reference the legacy `QuantumFlow`
  namespace.
  """

  @doc false
  defdelegate __struct__(), to: QuantumFlow.WorkflowAPI.Context
  @doc false
  defdelegate __struct__(kv), to: QuantumFlow.WorkflowAPI.Context, as: :__struct__
end
