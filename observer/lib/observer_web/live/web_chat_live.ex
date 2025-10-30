defmodule ObserverWeb.WebChatLive do
  @moduledoc """
  WebChat LiveView - Real-time chat interface for Observer

  Provides a real-time chat interface that receives messages from the
  Singularity application via Phoenix PubSub and displays them to users.

  ## Features

  - Real-time message display
  - Message input and sending
  - Approval requests with yes/no buttons
  - Question handling
  - System notifications
  - Message history

  ## Integration

  This LiveView subscribes to the "web_chat" PubSub topic and receives
  messages from `Singularity.Conversation.WebChat`.
  """

  use ObserverWeb, :live_view

  alias ObserverWeb.CoreComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Observer.PubSub, "web_chat")
    end

    socket =
      socket
      |> assign(:messages, [])
      |> assign(:input_message, "")
      |> assign(:pending_approval, nil)
      |> assign(:pending_question, nil)

    {:ok, socket}
  end

  @impl true
  def handle_info({:notify, message}, socket) do
    message = %{
      id: System.unique_integer([:positive]),
      type: :notification,
      content: message,
      timestamp: DateTime.utc_now()
    }

    socket = update(socket, :messages, fn messages -> [message | messages] end)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ask_approval, question}, socket) do
    message = %{
      id: System.unique_integer([:positive]),
      type: :approval_request,
      content: question,
      timestamp: DateTime.utc_now()
    }

    socket =
      socket
      |> update(:messages, fn messages -> [message | messages] end)
      |> assign(:pending_approval, message.id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:ask_question, question}, socket) do
    message = %{
      id: System.unique_integer([:positive]),
      type: :question,
      content: question,
      timestamp: DateTime.utc_now()
    }

    socket =
      socket
      |> update(:messages, fn messages -> [message | messages] end)
      |> assign(:pending_question, message.id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:daily_summary, summary}, socket) do
    message = %{
      id: System.unique_integer([:positive]),
      type: :daily_summary,
      content: "📊 Daily Summary: #{inspect(summary)}",
      timestamp: DateTime.utc_now()
    }

    socket = update(socket, :messages, fn messages -> [message | messages] end)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:deployment, deployment}, socket) do
    message = %{
      id: System.unique_integer([:positive]),
      type: :deployment,
      content: "🚀 Deployment: #{inspect(deployment)}",
      timestamp: DateTime.utc_now()
    }

    socket = update(socket, :messages, fn messages -> [message | messages] end)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:policy_change, policy}, socket) do
    message = %{
      id: System.unique_integer([:positive]),
      type: :policy_change,
      content: "📋 Policy Change: #{inspect(policy)}",
      timestamp: DateTime.utc_now()
    }

    socket = update(socket, :messages, fn messages -> [message | messages] end)
    {:noreply, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if String.trim(message) != "" do
      user_message = %{
        id: System.unique_integer([:positive]),
        type: :user_message,
        content: message,
        timestamp: DateTime.utc_now()
      }

      socket =
        socket
        |> update(:messages, fn messages -> [user_message | messages] end)
        |> assign(:input_message, "")

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("approve", %{"message_id" => message_id}, socket) do
    message_id = String.to_integer(message_id)
    
    response_message = %{
      id: System.unique_integer([:positive]),
      type: :approval_response,
      content: "✅ Approved",
      timestamp: DateTime.utc_now(),
      related_message_id: message_id
    }

    socket =
      socket
      |> update(:messages, fn messages -> [response_message | messages] end)
      |> assign(:pending_approval, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("reject", %{"message_id" => message_id}, socket) do
    message_id = String.to_integer(message_id)
    
    response_message = %{
      id: System.unique_integer([:positive]),
      type: :approval_response,
      content: "❌ Rejected",
      timestamp: DateTime.utc_now(),
      related_message_id: message_id
    }

    socket =
      socket
      |> update(:messages, fn messages -> [response_message | messages] end)
      |> assign(:pending_approval, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("answer_question", %{"message_id" => message_id, "answer" => answer}, socket) do
    message_id = String.to_integer(message_id)
    
    response_message = %{
      id: System.unique_integer([:positive]),
      type: :question_response,
      content: "💬 Answer: #{answer}",
      timestamp: DateTime.utc_now(),
      related_message_id: message_id
    }

    socket =
      socket
      |> update(:messages, fn messages -> [response_message | messages] end)
      |> assign(:pending_question, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :input_message, value)}
  end

  @impl true
  def handle_event("clear_messages", _params, socket) do
    {:noreply, assign(socket, :messages, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-gray-50">
      <!-- Header -->
      <div class="bg-blue-600 text-white p-4 shadow-md">
        <div class="flex justify-between items-center">
          <h1 class="text-xl font-bold">WebChat</h1>
          <button
            phx-click="clear_messages"
            class="bg-blue-700 hover:bg-blue-800 px-3 py-1 rounded text-sm"
          >
            Clear
          </button>
        </div>
      </div>

      <!-- Messages -->
      <div class="flex-1 overflow-y-auto p-4 space-y-3" id="messages">
        <div :for={message <- Enum.reverse(@messages)} class="message-item">
          <.message_component message={message} pending_approval={@pending_approval} pending_question={@pending_question} />
        </div>
      </div>

      <!-- Input -->
      <div class="bg-white border-t p-4">
        <form phx-submit="send_message" class="flex space-x-2">
          <input
            type="text"
            name="message"
            value={@input_message}
            phx-change="update_input"
            phx-value-key="value"
            placeholder="Type a message..."
            class="flex-1 border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <button
            type="submit"
            class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg"
          >
            Send
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp message_component(assigns) do
    ~H"""
    <div class={[
      "p-3 rounded-lg max-w-md",
      case @message.type do
        :user_message -> "bg-blue-100 ml-auto"
        :notification -> "bg-yellow-100"
        :approval_request -> "bg-orange-100"
        :question -> "bg-purple-100"
        :daily_summary -> "bg-green-100"
        :deployment -> "bg-indigo-100"
        :policy_change -> "bg-pink-100"
        :approval_response -> "bg-gray-100"
        :question_response -> "bg-gray-100"
        _ -> "bg-gray-100"
      end
    ]}>
      <div class="flex justify-between items-start">
        <div class="flex-1">
          <p class="text-sm text-gray-700"><%= @message.content %></p>
          <p class="text-xs text-gray-500 mt-1">
            <%= Calendar.strftime(@message.timestamp, "%H:%M:%S") %>
          </p>
        </div>
      </div>

      <!-- Approval buttons -->
      <div :if={@message.type == :approval_request and @pending_approval == @message.id} class="mt-2 flex space-x-2">
        <button
          phx-click="approve"
          phx-value-message_id={@message.id}
          class="bg-green-600 hover:bg-green-700 text-white px-3 py-1 rounded text-sm"
        >
          ✅ Approve
        </button>
        <button
          phx-click="reject"
          phx-value-message_id={@message.id}
          class="bg-red-600 hover:bg-red-700 text-white px-3 py-1 rounded text-sm"
        >
          ❌ Reject
        </button>
      </div>

      <!-- Question input -->
      <div :if={@message.type == :question and @pending_question == @message.id} class="mt-2">
        <form phx-submit="answer_question" phx-value-message_id={@message.id} class="flex space-x-2">
          <input
            type="text"
            name="answer"
            placeholder="Your answer..."
            class="flex-1 border border-gray-300 rounded px-2 py-1 text-sm"
          />
          <button
            type="submit"
            class="bg-purple-600 hover:bg-purple-700 text-white px-3 py-1 rounded text-sm"
          >
            Send
          </button>
        </form>
      </div>
    </div>
    """
  end
end