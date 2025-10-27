defmodule Singularity.LLM.Service do
  @moduledoc """
  LLM Service - Simple interface to Nexus AI orchestration.

  This is a lightweight wrapper that routes all LLM calls to Nexus.LLMRouter
  for intelligent model selection and cost optimization.

  ## Quick Start

  ```elixir
  # Simple call (auto-selects fast/cheap model)
  Service.call(:simple, [%{role: "user", content: "Classify this"}])

  # Complex call (auto-selects powerful model)
  Service.call(:complex, [%{role: "user", content: "Design a microservice"}])

  # With task hint for better model selection
  Service.call(:complex, messages, task_type: :architect)

  # Convenience wrappers
  Service.call_with_prompt(:medium, "Your question here")
  Service.call_with_system(:complex, "You are an architect", "Design X")
  ```

  ## Architecture

  ```
  Service.call/3 → Nexus.LLMRouter.route/3 → Model Selection → LLM Provider
  ```

  All complex logic (model selection, cost optimization, monitoring) is handled
  by Nexus.LLMRouter. This service just provides a simple interface.
  """

  require Logger

  alias Singularity.Nexus.LLMRouter

  @type complexity :: :simple | :medium | :complex
  @type task_type :: :architect | :coder | :planning | :refactoring | :analysis
  @type llm_result :: {:ok, map()} | {:error, atom() | tuple()}

  ## Public API

  @doc """
  Call LLM with complexity-based model selection.

  Routes to Nexus.LLMRouter for intelligent model selection and execution.
  """
  @spec call(complexity(), list(map()), keyword()) :: llm_result()
  def call(complexity, messages, opts \\ []) when complexity in [:simple, :medium, :complex] do
    Logger.debug("LLM Service routing to Nexus", %{
      complexity: complexity,
      message_count: length(messages),
      task_type: Keyword.get(opts, :task_type)
    })

    LLMRouter.route(complexity, messages, opts)
  end

  @doc """
  Call LLM with a simple prompt string.
  """
  @spec call_with_prompt(complexity(), String.t(), keyword()) :: llm_result()
  def call_with_prompt(complexity, prompt, opts \\ []) do
    LLMRouter.route_with_prompt(complexity, prompt, opts)
  end

  @doc """
  Call LLM with system and user messages.
  """
  @spec call_with_system(complexity(), String.t(), String.t(), keyword()) :: llm_result()
  def call_with_system(complexity, system_prompt, user_message, opts \\ []) do
    LLMRouter.route_with_system(complexity, system_prompt, user_message, opts)
  end

  @doc """
  Determine optimal complexity for a given task type.
  """
  @spec determine_complexity_for_task(task_type()) :: complexity()
  def determine_complexity_for_task(task_type) do
    case task_type do
      :architect -> :complex
      :refactoring -> :complex
      :coder -> :medium
      :planning -> :medium
      :analysis -> :simple
      _ -> :medium
    end
  end

  @doc """
  Get available models for a complexity level.
  """
  @spec get_models_for_complexity(complexity()) :: list(String.t())
  def get_models_for_complexity(complexity) do
    case complexity do
      :simple -> ["gemini-2.0-flash-exp"]
      :medium -> ["claude-3-5-sonnet-20241022"]
      :complex -> ["claude-3-5-sonnet-20241022", "gpt-4o"]
    end
  end
end