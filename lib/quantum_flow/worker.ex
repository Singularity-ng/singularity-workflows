defmodule QuantumFlow.Worker do
  @moduledoc """
  Compatibility layer that plugs QuantumFlow workflows into Oban workers.

  The original implementation lives alongside the QuantumFlow Elixir wrappers.
  For Observer we only need the minimal behaviour that delegates to
  `Oban.Worker` while exposing the convenience `new/2` function expected by
  Singularity job modules.
  """

  defmacro __using__(opts) do
    quote do
      use Oban.Worker, unquote(opts)

      @doc false
      def new(args, job_opts \\ []) do
        Oban.Worker.new(__MODULE__, args, job_opts)
      end
    end
  end
end
