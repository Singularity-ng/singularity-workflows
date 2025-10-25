{
  description = "ex_pgflow - Elixir implementation of pgflow";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            elixir
            postgresql_17
          ];

          shellHook = ''
            export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/ex_pgflow"

            echo "ex_pgflow development environment ready!"
            echo "Make sure PostgreSQL is running with pgmq extension installed"
            echo "Database: ex_pgflow on localhost:5432"
            echo "Run 'mix test' to run tests"
          '';
        };
      });
}