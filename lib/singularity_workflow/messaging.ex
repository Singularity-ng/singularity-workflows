defmodule Singularity.Workflow.Messaging do
  @moduledoc """
  Messaging helpers for publishing QuantumFlow events via PostgreSQL + pgmq.

  Provides convenience wrappers that resolve the appropriate Ecto repo and
  delegate to `Singularity.Workflow.Notifications` for durable delivery with NOTIFY.
  """

  alias Singularity.Workflow.Notifications

  @type queue :: String.t()
  @type payload :: map()
  @type repo :: module()

  @doc """
  Publish a message to the given queue.

  Accepts either an application atom (from which the repo will be resolved via
  `:ecto_repos`) or an Ecto repo module. Additional options are forwarded to
  `Singularity.Workflow.Notifications.send_with_notify/4`.
  """
  @spec publish(atom() | repo(), queue(), payload(), keyword()) :: {:ok, any()} | {:error, term()}
  def publish(app_or_repo, queue_name, payload, opts \\ []) do
    {repo, notify_opts} = extract_repo(app_or_repo, opts)
    do_publish(repo, queue_name, payload, notify_opts)
  end

  defp do_publish(repo, queue_name, payload, opts) do
    case Notifications.send_with_notify(queue_name, payload, repo, opts) do
      :ok -> {:ok, :sent}
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_repo(app_or_repo, opts) do
    {explicit_repo, remaining} = Keyword.pop(opts, :repo)

    repo =
      (explicit_repo && resolve_repo(explicit_repo)) ||
        resolve_repo(app_or_repo)

    {repo, remaining}
  end

  defp resolve_repo(repo) when is_atom(repo) do
    cond do
      function_exported?(repo, :__adapter__, 0) ->
        repo

      repos = Application.get_env(repo, :ecto_repos) ->
        repos
        |> List.wrap()
        |> List.first()
        |> case do
          nil -> raise "could not resolve Ecto repo for application #{inspect(repo)}"
          module -> module
        end

      true ->
        raise "could not resolve repo from #{inspect(repo)}. Provide an Ecto repo via :repo option"
    end
  end
end
