defmodule PgflowTest do
  use ExUnit.Case, async: true

  doctest Pgflow

  describe "version/0" do
    test "returns current version" do
      version = Pgflow.version()

      assert is_binary(version)
      assert version == "0.1.0"
    end

    test "version matches semantic versioning format" do
      version = Pgflow.version()

      # Should match major.minor.patch format
      assert version =~ ~r/^\d+\.\d+\.\d+$/
    end
  end
end
