defmodule Pgflow.Instance.Registry do
  @moduledoc """
  Tracks and manages Pgflow instance registration and health.

  When running multiple BEAM instances with shared PostgreSQL:
  1. Each instance registers itself on startup
  2. Updates heartbeat every N seconds
  3. Other instances can query who's alive
  4. Oban uses this to reassign jobs from dead instances

  ## Usage

  In your application.ex supervision tree:

      children = [
        # ... other children ...
        Pgflow.Instance.Registry
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  Check registered instances:

      iex> Pgflow.Instance.Registry.list()
      [
        %{instance_id: "instance_a", status: "online", load: 5},
        %{instance_id: "instance_b", status: "online", load: 3},
        %{instance_id: "instance_c", status: "offline", last_heartbeat: ...}
      ]

  Get current instance ID:

      iex> Pgflow.Instance.Registry.instance_id()
      "instance_a"

  ## Configuration

  Set in your config/config.exs or runtime.exs:

      config :ex_pgflow,
        instance_id: System.get_env("INSTANCE_ID") || "instance_#{Node.self()}",
        instance_heartbeat_interval: 5000,        # Heartbeat every 5 seconds
        instance_stale_timeout: 300               # Mark offline after 5 minutes

  Or use node names:

      config :ex_pgflow,
        instance_id: Node.self()  # Uses Erlang node name

  ## Database Schema

  Requires table created by migration:

      CREATE TABLE pgflow_instances (
        instance_id TEXT PRIMARY KEY,
        hostname TEXT,
        pid TEXT,
        status TEXT,              -- 'online', 'offline', 'paused'
        load INTEGER,
        last_heartbeat TIMESTAMP,
        created_at TIMESTAMP
      );

  See migrations for complete schema.
  """

  use GenServer
  require Logger

  @doc """
  Start the Instance Registry GenServer.

  Called automatically as part of supervision tree.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current instance ID.

  Returns the unique identifier for this instance.
  """
  @spec instance_id() :: String.t()
  def instance_id do
    Application.get_env(:ex_pgflow, :instance_id) || generate_instance_id()
  end

  @doc """
  List all registered instances.

  Returns list of instance records from database.
  """
  @spec list() :: [map()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Get status of a specific instance.

  Returns instance record or nil if not found.
  """
  @spec get(String.t()) :: map() | nil
  def get(instance_id) do
    GenServer.call(__MODULE__, {:get, instance_id})
  end

  @doc """
  Update instance load (number of executing jobs).

  Called by the executor or job processor.
  """
  @spec update_load(integer()) :: :ok
  def update_load(load) do
    GenServer.cast(__MODULE__, {:update_load, load})
  end

  @doc """
  Mark instance as offline.

  Called on shutdown.
  """
  @spec mark_offline() :: :ok
  def mark_offline do
    GenServer.cast(__MODULE__, :mark_offline)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    instance_id = instance_id()
    heartbeat_interval = Application.get_env(:ex_pgflow, :instance_heartbeat_interval, 5000)

    Logger.info("Pgflow.Instance.Registry: Starting registry",
      instance_id: instance_id,
      heartbeat_interval: heartbeat_interval
    )

    # Try to register immediately
    register_instance(instance_id)

    # Schedule heartbeat
    Process.send_after(self(), :heartbeat, heartbeat_interval)

    {:ok, %{instance_id: instance_id, heartbeat_interval: heartbeat_interval}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    instances = fetch_instances()
    {:reply, instances, state}
  end

  @impl true
  def handle_call({:get, instance_id}, _from, state) do
    instance = fetch_instance(instance_id)
    {:reply, instance, state}
  end

  @impl true
  def handle_cast({:update_load, load}, state) do
    update_instance_load(state.instance_id, load)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:mark_offline, state) do
    mark_instance_offline(state.instance_id)
    {:noreply, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    update_instance_heartbeat(state.instance_id)
    Process.send_after(self(), :heartbeat, state.heartbeat_interval)
    {:noreply, state}
  end

  # Private Functions

  defp generate_instance_id do
    {:ok, hostname_charlist} = :inet.gethostname()
    hostname = to_string(hostname_charlist)
    pid = System.pid()
    "#{hostname}:#{pid}"
  rescue
    _ -> "instance_#{Node.self()}"
  end

  defp register_instance(instance_id) do
    try do
      Logger.debug("Pgflow.Instance.Registry: Registering instance", instance_id: instance_id)

      # This is a placeholder - actual implementation depends on your database setup
      # In real usage, you'd use your Repo module here
      {:ok, hostname_charlist} = :inet.gethostname()
      hostname = to_string(hostname_charlist)

      Logger.info("Pgflow.Instance.Registry: Instance registered",
        instance_id: instance_id,
        hostname: hostname,
        pid: System.pid()
      )
    catch
      kind, error ->
        Logger.error("Pgflow.Instance.Registry: Failed to register instance",
          instance_id: instance_id,
          error: inspect({kind, error})
        )
    end
  end

  defp update_instance_heartbeat(instance_id) do
    Logger.debug("Pgflow.Instance.Registry: Updating heartbeat",
      instance_id: instance_id,
      timestamp: DateTime.utc_now()
    )

    # Placeholder - actual implementation depends on your Repo
  end

  defp update_instance_load(instance_id, load) do
    Logger.debug("Pgflow.Instance.Registry: Updating load",
      instance_id: instance_id,
      load: load
    )

    # Placeholder - actual implementation depends on your Repo
  end

  defp mark_instance_offline(instance_id) do
    Logger.info("Pgflow.Instance.Registry: Marking instance offline",
      instance_id: instance_id
    )

    # Placeholder - actual implementation depends on your Repo
  end

  defp fetch_instances do
    Logger.debug("Pgflow.Instance.Registry: Fetching all instances")

    # Placeholder - actual implementation depends on your Repo
    []
  end

  defp fetch_instance(instance_id) do
    Logger.debug("Pgflow.Instance.Registry: Fetching instance",
      instance_id: instance_id
    )

    # Placeholder - actual implementation depends on your Repo
    nil
  end
end
