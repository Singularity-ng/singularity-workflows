{
  description = "quantum_flow - Elixir implementation of QuantumFlow";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        beamPackages = pkgs.beam.packages.erlang;
        # Use Elixir 1.19.x (latest)
        elixir = beamPackages.elixir_1_19;

        # PostgreSQL with pgmq extension
        # Note: Using PostgreSQL 18 (uuid_generate_v7() is built-in, no extension needed)
        postgresqlWithExtensions = pkgs.postgresql_18.withPackages (ps: [
          ps.pgmq  # In-database message queue
        ]);

      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            beamPackages.erlang
            elixir  # Elixir 1.19.x
            postgresqlWithExtensions
            pkgs.nodejs  # For moon installation
            pkgs.yarn    # Alternative package manager
            pkgs.gh      # GitHub CLI for repository management
          ];

          shellHook = ''
            # Clear PATH and rebuild with nix packages FIRST (before system paths)
            export PATH="${beamPackages.erlang}/bin:${elixir}/bin:${postgresqlWithExtensions}/bin:${pkgs.nodejs}/bin:${pkgs.yarn}/bin:${pkgs.gh}/bin:$PATH"
            export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/quantum_flow"
            echo "ShellHook PATH: $PATH"
            echo "Elixir location: $(which elixir 2>/dev/null || echo 'not found')"
            echo "Mix location: $(which mix 2>/dev/null || echo 'not found')"
            echo "GitHub CLI location: $(which gh 2>/dev/null || echo 'not found')"

            # Install moon if not present
            if ! command -v moon >/dev/null 2>&1; then
              echo "Moon task runner not available - using mix commands directly"
            fi

            # Function to cleanup PostgreSQL on exit
            cleanup_postgres() {
              if [ -f ".postgres_pid" ] && kill -0 $(cat .postgres_pid) 2>/dev/null; then
                echo "Stopping PostgreSQL..."
                pg_ctl -D .postgres_data stop
                rm -f .postgres_pid
              fi
            }

            # Set trap to cleanup on shell exit
            trap cleanup_postgres EXIT

            # Start PostgreSQL if not already running
            if ! pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
              echo "Starting PostgreSQL..."

              # Create data directory if it doesn't exist
              if [ ! -d ".postgres_data" ]; then
                echo "Initializing PostgreSQL data directory..."
                initdb -D .postgres_data --no-locale --encoding=UTF8
              fi

              # Start PostgreSQL
              pg_ctl -D .postgres_data -l .postgres.log -o "-p 5432" start
              echo $! > .postgres_pid

              # Wait for PostgreSQL to be ready
              sleep 3

              # Create postgres role if it doesn't exist
              if ! psql -p 5432 -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='postgres'" | grep -q 1; then
                echo "Creating postgres role..."
                psql -p 5432 -d postgres -c "CREATE ROLE postgres WITH SUPERUSER LOGIN PASSWORD 'postgres';"
              fi

              # Create database and install extensions if they don't exist
              if ! psql -lqt | cut -d \| -f 1 | grep -qw quantum_flow; then
                echo "Creating quantum_flow database..."
                createdb -p 5432 quantum_flow
                psql -p 5432 -d quantum_flow -c "CREATE EXTENSION IF NOT EXISTS pgmq;"
                echo "Database and extensions ready"
              else
                echo "Database already exists"
              fi

              echo "PostgreSQL started with pgmq extension"
            else
              echo "PostgreSQL already running"
            fi

            echo "quantum_flow development environment ready!"
            echo "Database: quantum_flow on localhost:5432 with pgmq extension"
            echo "Run 'mix test' to run tests"
            echo "PostgreSQL will auto-stop when you exit this shell"
          '';
        };
      });
}
