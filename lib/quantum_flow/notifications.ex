defmodule QuantumFlow.Notifications.Behaviour do
  @moduledoc """
  Behaviour definition for QuantumFlow notifications, used for testing and mocking.
  """

  @callback send_with_notify(String.t(), map(), Ecto.Repo.t()) ::
              {:ok, String.t()} | {:error, any()}

  @callback listen(String.t(), Ecto.Repo.t()) :: {:ok, pid()} | {:error, any()}

  @callback unlisten(pid(), Ecto.Repo.t()) :: :ok | {:error, any()}

  @callback notify_only(String.t(), String.t(), Ecto.Repo.t()) :: :ok | {:error, any()}
end

defmodule QuantumFlow.Notifications do
  @moduledoc """
  PostgreSQL NOTIFY integration for PGMQ flows.

  Provides real-time notification capabilities for PGMQ-based workflows.
  This enables instant delivery of workflow events without constant polling.

  ## How it works

  1. **Send with NOTIFY**: `send_with_notify/3` sends to PGMQ + triggers NOTIFY
  2. **Listen for events**: `listen/2` subscribes to PostgreSQL NOTIFY events
  3. **Process notifications**: Handle NOTIFY events to trigger workflow processing

  ## Benefits

  - ✅ **Real-time**: Instant notification when messages arrive
  - ✅ **Efficient**: No constant polling, only when events occur
  - ✅ **Reliable**: Built on PostgreSQL's proven NOTIFY system
  - ✅ **Logged**: All NOTIFY events are properly logged for debugging

  ## Example

      # Send message with NOTIFY
      {:ok, message_id} = QuantumFlow.Notifications.send_with_notify(
        "workflow_events",
        %{type: "task_completed", task_id: "123"},
        MyApp.Repo
      )

      # Listen for NOTIFY events
      {:ok, pid} = QuantumFlow.Notifications.listen("workflow_events", MyApp.Repo)

      # Handle notifications
      receive do
        {:notification, ^pid, channel, message_id} ->
          Logger.info("NOTIFY received on \#{channel} -> \#{message_id}")
          # Process the notification...
      end
  """

  @behaviour QuantumFlow.Notifications.Behaviour
  require Logger
  alias Pgmq
  alias Pgmq.Message

  @doc """
  Send a message via PGMQ with PostgreSQL NOTIFY for real-time delivery.

  ## Parameters

  - `queue_name` - PGMQ queue name
  - `message` - Message payload (will be JSON encoded)
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, message_id}` - Message sent and NOTIFY triggered
  - `{:error, reason}` - Send failed

  ## Logging

  All NOTIFY events are logged with structured logging:
  - `:info` level for successful sends
  - `:error` level for failures
  - Includes queue name, message ID, and timing
  """
  @spec send_with_notify(String.t(), map(), Ecto.Repo.t(), keyword()) ::
          :ok | {:ok, map()} | {:error, any()}
  def send_with_notify(queue_name, message, repo, opts \\ []) do
    start_time = System.monotonic_time()

    expect_reply? = Keyword.get(opts, :expect_reply, true)
    timeout_ms = Keyword.get(opts, :timeout, 30_000)
    poll_interval = Keyword.get(opts, :poll_interval, 100)

    reply_queue =
      if expect_reply? do
        Keyword.get(opts, :reply_queue, "QuantumFlow.reply.#{Ecto.UUID.generate()}")
      end

    enriched_message =
      if expect_reply? and reply_queue do
        message
        |> Map.put_new(:reply_to, reply_queue)
        |> Map.put_new("reply_to", reply_queue)
      else
        message
      end

    ensure_reply_queue(expect_reply?, reply_queue, repo)

    with {:ok, message_id} <- send_pgmq_message(queue_name, enriched_message, repo),
         :ok <- trigger_notify(queue_name, message_id, repo),
         result <- maybe_wait_for_reply(expect_reply?, reply_queue, repo, timeout_ms, poll_interval) do
      duration = System.monotonic_time() - start_time

      Logger.info("PGMQ + NOTIFY sent successfully",
        queue: queue_name,
        message_id: message_id,
        duration_ms: System.convert_time_unit(duration, :native, :millisecond),
        message_type:
          Map.get(enriched_message, :type, Map.get(enriched_message, "type", "unknown")),
        expect_reply: expect_reply?
      )

      cleanup_reply_queue(expect_reply?, reply_queue, repo)
      result
    else
      {:error, reason} ->
        Logger.error("PGMQ + NOTIFY send failed",
          queue: queue_name,
          error: inspect(reason),
          message_type:
            Map.get(enriched_message, :type, Map.get(enriched_message, "type", "unknown"))
        )

        cleanup_reply_queue(expect_reply?, reply_queue, repo)
        {:error, reason}
    end
  end

  @doc """
  Listen for NOTIFY events on a PGMQ queue.

  ## Parameters

  - `queue_name` - PGMQ queue name to listen for
  - `repo` - Ecto repository

  ## Returns

  - `{:ok, pid}` - Notification listener process
  - `{:error, reason}` - Failed to start listener

  ## Logging

  Listener start/stop events are logged:
  - `:info` level for successful listener creation
  - `:error` level for listener failures
  - Includes channel name and process ID
  """
  @spec listen(String.t(), Ecto.Repo.t()) :: {:ok, pid()} | {:error, any()}
  def listen(queue_name, repo) do
    channel = "pgmq_#{queue_name}"

    case Postgrex.Notifications.listen(repo, channel) do
      {:ok, pid} ->
        Logger.info("PGMQ NOTIFY listener started",
          queue: queue_name,
          channel: channel,
          listener_pid: inspect(pid)
        )

        {:ok, pid}

      {:error, reason} ->
        Logger.error("PGMQ NOTIFY listener failed to start",
          queue: queue_name,
          channel: channel,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Stop listening for NOTIFY events.

  ## Parameters

  - `pid` - Notification listener process
  - `repo` - Ecto repository

  ## Returns

  - `:ok` - Stopped successfully
  - `{:error, reason}` - Stop failed

  ## Logging

  Listener stop events are logged at `:info` level.
  """
  @spec unlisten(pid(), Ecto.Repo.t()) :: :ok | {:error, any()}
  def unlisten(pid, repo) do
    case Postgrex.Notifications.unlisten(repo, pid) do
      :ok ->
        Logger.info("PGMQ NOTIFY listener stopped",
          listener_pid: inspect(pid)
        )

        :ok

      {:error, reason} ->
        Logger.error("PGMQ NOTIFY listener stop failed",
          listener_pid: inspect(pid),
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Send a notification without PGMQ (NOTIFY only).

  Useful for simple notifications that don't need persistence.

  ## Parameters

  - `channel` - NOTIFY channel name
  - `payload` - Notification payload
  - `repo` - Ecto repository

  ## Returns

  - `:ok` - Notification sent
  - `{:error, reason}` - Send failed

  ## Logging

  NOTIFY-only events are logged at `:debug` level.
  """
  @spec notify_only(String.t(), String.t(), Ecto.Repo.t()) :: :ok | {:error, any()}
  def notify_only(channel, payload, repo) do
    case repo.query("SELECT pg_notify($1, $2)", [channel, payload]) do
      {:ok, _} ->
        Logger.debug("NOTIFY sent",
          channel: channel,
          payload: payload
        )

        :ok

      {:error, reason} ->
        Logger.error("NOTIFY send failed",
          channel: channel,
          payload: payload,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Private: Send message via PGMQ
  defp send_pgmq_message(queue_name, message, repo) when is_binary(queue_name) do
    with {:ok, json} <- encode_message(message),
         {:ok, message_id} <- do_send(queue_name, json, repo) do
      {:ok, Integer.to_string(message_id)}
    end
  end

  defp encode_message(message) do
    case Jason.encode(message) do
      {:ok, json} ->
        {:ok, json}

      {:error, reason} ->
        Logger.error("Failed to encode pgmq message",
          error: inspect(reason),
          payload: inspect(message)
        )

        {:error, reason}
    end
  end

  defp do_send(queue_name, json_message, repo, attempts \\ 0)

  defp do_send(queue_name, json_message, repo, attempts) when attempts < 2 do
    try do
      case Pgmq.send_message(repo, queue_name, json_message) do
        {:ok, msg_id} ->
          {:ok, msg_id}

        {:error, reason} ->
          Logger.error("pgmq.send returned error",
            queue: queue_name,
            error: inspect(reason)
          )

          {:error, reason}
      end
    rescue
      error in [Postgrex.Error] ->
        if queue_missing?(error) do
          case ensure_queue(queue_name, repo) do
            :ok -> do_send(queue_name, json_message, repo, attempts + 1)
            {:error, reason} -> {:error, reason}
          end
        else
          Logger.error("pgmq.send failed",
            queue: queue_name,
            error: format_postgrex_error(error)
          )

          {:error, error}
        end
    end
  end

  defp do_send(queue_name, _json_message, _repo, _attempts) do
    Logger.error("Failed to create pgmq queue after retry", queue: queue_name)
    {:error, :queue_create_failed}
  end

  defp ensure_queue(queue_name, repo) do
    try do
      :ok = Pgmq.create_queue(repo, queue_name)
    rescue
      error in [Postgrex.Error] ->
        case error.postgres[:code] do
          :duplicate_table -> :ok
          :duplicate_object -> :ok
          _ ->
            Logger.error("pgmq.create failed",
              queue: queue_name,
              error: format_postgrex_error(error)
            )

            {:error, error}
        end
    end
  end

  # Private: Trigger PostgreSQL NOTIFY after PGMQ send
  defp trigger_notify(queue_name, message_id, repo) do
    channel = "pgmq_#{queue_name}"

    case repo.query("SELECT pg_notify($1, $2)", [channel, message_id]) do
      {:ok, _} ->
        Logger.debug("NOTIFY triggered",
          queue: queue_name,
          channel: channel,
          message_id: message_id
        )

        :ok

      {:error, reason} ->
        Logger.error("NOTIFY trigger failed",
          queue: queue_name,
          channel: channel,
          message_id: message_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp queue_missing?(%Postgrex.Error{postgres: %{code: :undefined_table}}), do: true

  defp queue_missing?(%Postgrex.Error{postgres: %{code: :undefined_object}}), do: true

  defp queue_missing?(%Postgrex.Error{postgres: %{message: message}}) when is_binary(message) do
    String.contains?(message, "does not exist")
  end

  defp queue_missing?(_), do: false

  defp format_postgrex_error(%Postgrex.Error{postgres: postgres} = _error) do
    %{code: postgres[:code], message: postgres[:message], detail: postgres[:detail]} |> inspect()
  end

  defp format_postgrex_error(error), do: inspect(error)

  defp ensure_reply_queue(false, _queue, _repo), do: :ok

  defp ensure_reply_queue(true, queue, repo) do
    ensure_queue(queue, repo)
  end

  defp maybe_wait_for_reply(false, _queue, _repo, _timeout, _poll_interval), do: :ok

  defp maybe_wait_for_reply(true, queue, repo, timeout_ms, poll_interval) do
    wait_for_reply(queue, repo, timeout_ms, poll_interval)
  end

  defp wait_for_reply(queue, repo, timeout_ms, poll_interval) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_reply(queue, repo, deadline, poll_interval)
  end

  defp do_wait_for_reply(queue, repo, deadline, poll_interval) do
    case pop_reply_message(queue, repo) do
      {:ok, nil} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(poll_interval)
          do_wait_for_reply(queue, repo, deadline, poll_interval)
        end

      {:ok, %Message{body: payload}} ->
        decode_message_payload(payload)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp pop_reply_message(queue, repo) do
    try do
      {:ok, Pgmq.pop_message(repo, queue)}
    rescue
      error ->
        case error do
          %Postgrex.Error{} ->
            Logger.error("pgmq.pop failed", queue: queue, error: format_postgrex_error(error))
            {:error, error}

          _ ->
            Logger.error("Unexpected error while popping reply message",
              queue: queue,
              error: inspect(error)
            )

            {:error, error}
        end
    end
  end

  defp decode_message_payload(msg) when is_binary(msg) do
    case Jason.decode(msg) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        Logger.error("Failed to decode reply message", error: inspect(reason), payload: msg)
        {:error, reason}
    end
  end

  defp decode_message_payload(%{} = msg), do: {:ok, msg}
  defp decode_message_payload(other), do: {:ok, other}

  defp cleanup_reply_queue(false, _queue, _repo), do: :ok

  defp cleanup_reply_queue(true, queue, repo) do
    try do
      :ok = Pgmq.drop_queue(repo, queue)
    rescue
      error in [Postgrex.Error] ->
        case error.postgres[:code] do
          :undefined_table -> :ok
          :undefined_object -> :ok
          _ ->
            Logger.warning("Failed to drop reply queue",
              queue: queue,
              error: format_postgrex_error(error)
            )

            :ok
        end
    end
  end
end
