defmodule Singularity.Workflow.Test.Snapshot do
  @moduledoc """
  Snapshot testing helper for comparing complex outputs.

  Snapshots are stored in test/snapshots/ and versioned with git.

  Usage:
    {:ok, result} = MyFunction.execute()
    assert_snapshot(result, "my_function_result")
  """

  def snapshot_dir, do: Path.join([__DIR__, "..", "snapshots"])

  @doc """
  Assert that the given data matches the stored snapshot.

  On first run, creates the snapshot file.
  On subsequent runs, compares against stored snapshot.
  """
  def assert_snapshot(data, snapshot_name, opts \\ []) do
    snapshot_file = Path.join(snapshot_dir(), "#{snapshot_name}.json")
    data_json = Jason.encode!(data, pretty: true)

    case File.read(snapshot_file) do
      {:ok, stored_json} ->
        # Compare snapshots
        assert_snapshots_match(data_json, stored_json, snapshot_name, snapshot_file, opts)

      {:error, :enoent} ->
        # Create snapshot on first run
        File.mkdir_p!(snapshot_dir())
        File.write!(snapshot_file, data_json)
        :ok
    end
  end

  defp assert_snapshots_match(actual, expected, name, file, opts) do
    if String.trim(actual) == String.trim(expected) do
      :ok
    else
      if Keyword.get(opts, :update, false) or System.get_env("SNAPSHOT_UPDATE") == "1" do
        # Update snapshot when flag is set
        File.write!(file, actual)
        :ok
      else
        # Fail with diff
        raise """
        Snapshot mismatch for: #{name}
        File: #{file}

        Expected:
        #{expected}

        Actual:
        #{actual}

        To update snapshots, run:
          SNAPSHOT_UPDATE=1 mix test
        """
      end
    end
  end

  @doc """
  Compare two complex data structures by converting to JSON.
  """
  def assert_json_equal(actual, expected, message \\ "") do
    actual_json = Jason.encode!(actual, pretty: true)
    expected_json = Jason.encode!(expected, pretty: true)

    if actual_json == expected_json do
      :ok
    else
      raise "JSON mismatch #{message}:\n\nExpected:\n#{expected_json}\n\nActual:\n#{actual_json}"
    end
  end
end
