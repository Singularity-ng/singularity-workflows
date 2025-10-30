defmodule ExQuantumFlow do
  @moduledoc """
  Backwards-compatible facade for the renamed `quantum_flow` application.

  Legacy compatibility layer for projects that still reference `ExQuantumFlow`.

  All functionality now lives under `QuantumFlow`. This module simply delegates
  publishing to the new implementation so existing call sites keep working
  during the transition.
  """

  alias QuantumFlow.Notifications

  @type queue_name :: String.t()
  @type payload :: map()
  @type repo :: module()
  @type publish_result :: {:ok, any()} | {:error, any()}

  @doc """
  Publish a message to `queue_name`, resolving the repository from an
  application atom or accepting a repo module directly.
  """
  @spec publish(atom() | repo(), queue_name(), payload()) :: publish_result()
  def publish(app_or_repo, queue_name, payload) do
    publish(app_or_repo, queue_name, payload, [])
  end

  @spec publish(atom() | repo(), queue_name(), payload(), keyword()) :: publish_result()
  def publish(app_or_repo, queue_name, payload, opts) when is_list(opts) do
    {repo, opts} = extract_repo(app_or_repo, opts)
    do_publish(repo, queue_name, payload, opts)
  end

  defp do_publish(repo, queue_name, payload, opts) do
    case Notifications.send_with_notify(queue_name, payload, repo, opts) do
      {:ok, %{message_id: message_id}} ->
        {:ok, message_id}

      {:ok, %{"message_id" => message_id}} ->
        {:ok, message_id}

      {:ok, other} ->
        {:ok, other}

      :ok ->
        {:ok, :sent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_repo(app_or_repo, opts) do
    {explicit_repo, rest} = Keyword.pop(opts, :repo)

    repo =
      explicit_repo
      |> maybe_resolve_repo(app_or_repo)

    {repo, rest}
  end

  defp maybe_resolve_repo(nil, app_or_repo), do: resolve_repo(app_or_repo)
  defp maybe_resolve_repo(repo, _), do: resolve_repo(repo)

  defp resolve_repo(nil),
    do: raise(ArgumentError, "missing :repo option for ExQuantumFlow.publish/4")

  defp resolve_repo(repo) when is_atom(repo) do
    cond do
      Code.ensure_loaded?(repo) and function_exported?(repo, :__adapter__, 0) ->
        repo

      true ->
        repo
        |> Application.get_env(:ecto_repos, [])
        |> List.wrap()
        |> List.first()
        |> case do
          nil ->
            raise ArgumentError,
                  "could not resolve Ecto repo for application #{inspect(repo)}. " <>
                    "Set :ecto_repos or provide a repo module via the :repo option."

          module ->
            module
        end
    end
  end
end
