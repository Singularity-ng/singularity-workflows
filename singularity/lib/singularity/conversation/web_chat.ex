defmodule Singularity.Conversation.WebChat do
  @moduledoc """
  WebChat - Web-based chat interface for Observer Phoenix app

  Provides web-based chat functionality that can be integrated into the
  Observer Phoenix web interface. This replaces the external GoogleChat
  dependency with a local web chat implementation.

  ## Usage

  The Observer Phoenix app can use this module to provide chat functionality:

      # In Observer LiveView
      WebChat.notify("System status update")
      WebChat.ask_approval("Deploy to production?")
      WebChat.ask_question("What should we prioritize next?")

  ## Integration with Observer

  This module is designed to work with the Observer Phoenix web interface
  to provide real-time chat functionality for monitoring and interaction.
  """

  require Logger

  @doc """
  Send a notification message to the web chat interface.

  ## Examples

      WebChat.notify("System is running normally")
      WebChat.notify("⚠️ High CPU usage detected")
  """
  @spec notify(String.t()) :: :ok
  def notify(message) do
    Logger.info("[WebChat] #{message}")
    
    # Send to Observer Phoenix LiveView via PubSub
    Phoenix.PubSub.broadcast(Observer.PubSub, "web_chat", {:notify, message})
    
    :ok
  end

  @doc """
  Ask for approval from the user via web chat.

  ## Examples

      WebChat.ask_approval("Deploy to production?")
      WebChat.ask_approval("Delete old logs?")
  """
  @spec ask_approval(String.t()) :: :ok
  def ask_approval(question) do
    Logger.info("[WebChat] Approval needed: #{question}")
    
    # Send to Observer Phoenix LiveView via PubSub
    Phoenix.PubSub.broadcast(Observer.PubSub, "web_chat", {:ask_approval, question})
    
    :ok
  end

  @doc """
  Ask a question to the user via web chat.

  ## Examples

      WebChat.ask_question("What should we prioritize next?")
      WebChat.ask_question("Which model should we use?")
  """
  @spec ask_question(String.t()) :: :ok
  def ask_question(question) do
    Logger.info("[WebChat] Question: #{question}")
    
    # Send to Observer Phoenix LiveView via PubSub
    Phoenix.PubSub.broadcast(Observer.PubSub, "web_chat", {:ask_question, question})
    
    :ok
  end

  @doc """
  Send a daily summary to the web chat interface.

  ## Examples

      WebChat.daily_summary(%{tasks_completed: 15, errors: 2})
  """
  @spec daily_summary(map()) :: :ok
  def daily_summary(summary) do
    message = "📊 Daily Summary: #{inspect(summary)}"
    Logger.info("[WebChat] #{message}")
    
    # Send to Observer Phoenix LiveView via PubSub
    Phoenix.PubSub.broadcast(Observer.PubSub, "web_chat", {:daily_summary, summary})
    
    :ok
  end

  @doc """
  Send a deployment notification to the web chat interface.

  ## Examples

      WebChat.deployment_notification(%{version: "1.2.3", status: "success"})
  """
  @spec deployment_notification(map()) :: :ok
  def deployment_notification(deployment) do
    message = "🚀 Deployment: #{inspect(deployment)}"
    Logger.info("[WebChat] #{message}")
    
    # Send to Observer Phoenix LiveView via PubSub
    Phoenix.PubSub.broadcast(Observer.PubSub, "web_chat", {:deployment, deployment})
    
    :ok
  end

  @doc """
  Send a policy change notification to the web chat interface.

  ## Examples

      WebChat.policy_change(%{policy: "security", action: "updated"})
  """
  @spec policy_change(map()) :: :ok
  def policy_change(policy) do
    message = "📋 Policy Change: #{inspect(policy)}"
    Logger.info("[WebChat] #{message}")
    
    # Send to Observer Phoenix LiveView via PubSub
    Phoenix.PubSub.broadcast(Observer.PubSub, "web_chat", {:policy_change, policy})
    
    :ok
  end
end