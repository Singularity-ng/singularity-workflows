# Contributing to ExPgflow

Thank you for your interest in ExPgflow! This document provides guidelines for contributing to the project.

## Getting Started

### Prerequisites
- Elixir 1.14+
- PostgreSQL 14+
- Mix (comes with Elixir)

### Development Setup

1. Clone the repository:
```bash
git clone https://github.com/mikkihugo/ex_pgflow.git
cd ex_pgflow
```

2. Install dependencies:
```bash
mix deps.get
```

3. Set up the database:
```bash
# Create test database
createdb ex_pgflow_test

# Configure connection
export DATABASE_URL="postgres://localhost/ex_pgflow_test"

# Run migrations
mix ecto.migrate
```

4. Run tests to verify setup:
```bash
mix test
```

## Development Workflow

### Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/pgflow/executor_test.exs

# Run tests with coverage report
mix test.coverage

# Run tests in watch mode (auto-rerun on file changes)
mix test.watch
```

### Code Quality

ExPgflow enforces high code quality standards:

```bash
# Run all quality checks (recommended before committing)
mix quality

# Individual checks:
mix format              # Format code
mix credo --strict      # Linting (shows code smells)
mix dialyzer            # Type checking
mix sobelow --exit-on-warning  # Security analysis
mix deps.audit          # Check dependencies for vulnerabilities
```

### Code Style

ExPgflow follows standard Elixir conventions:

1. **Formatting**: Run `mix format` before committing
2. **Line Length**: Maximum 100 characters (enforced in .formatter.exs)
3. **Naming**: Use descriptive names, avoid abbreviations
4. **Modules**: One module per file, named after the file
5. **Documentation**: All public modules and functions require @moduledoc/@doc

### Documentation Standards

All code contributions must include:

1. **Module Documentation** (@moduledoc)
   ```elixir
   defmodule Pgflow.MyModule do
     @moduledoc """
     Brief description of what this module does.

     ## Examples

         iex> MyModule.my_function("input")
         "output"
     """
   ```

2. **Function Documentation** (@doc)
   ```elixir
   @doc """
   Description of what the function does.

   ## Parameters

   - param1: description

   ## Returns

   - ok tuple with result
   - error tuple with reason

   ## Examples

       iex> my_function("value")
       {:ok, "result"}
   """
   @spec my_function(String.t()) :: {:ok, String.t()} | {:error, term()}
   def my_function(input) do
     {:ok, input}
   end
   ```

3. **Type Specifications** (@spec)
   - Always include @spec for public functions
   - Use accurate types (not just any)

4. **Inline Comments** for complex logic
   - Explain _why_ not _what_ (code shows what)
   - Describe algorithms and performance implications
   - Note edge cases and gotchas

## Architecture Guidelines

### Database-First Design

ExPgflow uses PostgreSQL as the source of truth. When adding features:

1. **Schema Changes**: Create migrations for all schema additions
2. **SQL Functions**: Complex logic lives in PostgreSQL functions (for atomicity)
3. **Transactions**: Use Ecto's transaction API for multi-statement operations
4. **Indexes**: Add indexes for columns used in WHERE clauses frequently

### DAG Principles

When working with workflows:

1. **Acyclic**: Ensure dependency graphs remain acyclic
2. **Deterministic**: Same input should produce same execution plan
3. **Observable**: All state changes must be queryable from database
4. **Recoverable**: System must survive process crashes

## Making Changes

### Bug Fixes

1. Create a test that reproduces the bug:
   ```elixir
   describe "bug behavior" do
     test "should work correctly" do
       # Reproduce the bug
       {:error, _} = function_call()
     end
   end
   ```

2. Make the minimum change to fix it

3. Verify the test now passes

4. Run `mix quality` before committing

### New Features

1. **Open an issue first** to discuss the feature
2. **Create a test** for the feature
3. **Implement** the feature
4. **Document** the feature (code comments + docs)
5. **Update changelog** with the feature

### File Organization

```
ex_pgflow/
├── lib/pgflow/
│   ├── executor.ex          # Main entry point
│   ├── flow_builder.ex      # Dynamic workflow API
│   ├── repo.ex              # Ecto repository
│   ├── dag/                 # DAG-related modules
│   │   ├── workflow_definition.ex
│   │   ├── run_initializer.ex
│   │   ├── task_executor.ex
│   │   └── dynamic_workflow_loader.ex
│   ├── step_*.ex            # Step-related schemas
│   └── workflow_run.ex      # Workflow run schema
├── priv/repo/
│   └── migrations/          # Database migrations
├── test/
│   ├── pgflow/
│   │   └── *_test.exs       # Unit/integration tests
│   └── support/
│       └── sql_case.ex      # Test helpers
├── CHANGELOG.md             # Version history
├── ARCHITECTURE.md          # Technical deep dive
├── GETTING_STARTED.md       # User guide
├── CONTRIBUTING.md          # This file
└── mix.exs                  # Project definition
```

## Testing Strategy

### Unit Tests
- Test individual functions
- Mock external dependencies (pgmq, workflows)
- Use ExUnit.Case + Mox for mocking

### Integration Tests
- Test full workflow execution end-to-end
- Use real PostgreSQL (test transaction isolation)
- Verify database state changes

### Example Test Structure
```elixir
defmodule Pgflow.MyModuleTest do
  use ExUnit.Case
  alias Pgflow.MyModule

  describe "my_function/1" do
    test "handles valid input" do
      {:ok, result} = MyModule.my_function("input")
      assert result == "expected"
    end

    test "returns error for invalid input" do
      {:error, reason} = MyModule.my_function(nil)
      assert reason == :invalid_input
    end
  end
end
```

## Commit Message Guidelines

Write clear, descriptive commit messages:

```
[type]: Brief description

Longer explanation of the change, why it was needed, and how it works.

- Use bullet points for multiple changes
- Reference issues: "Fixes #123"
- Keep first line under 50 characters
```

### Commit Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code reorganization
- `test`: Test additions/improvements
- `perf`: Performance improvements
- `chore`: Build, dependencies, etc.

## Pull Requests

1. **Create a feature branch**:
   ```bash
   git checkout -b feature/my-feature
   ```

2. **Make your changes** with clear commits

3. **Run tests and quality checks**:
   ```bash
   mix quality
   mix test
   ```

4. **Push to GitHub** and create a Pull Request:
   ```bash
   git push origin feature/my-feature
   ```

5. **PR Description** should include:
   - What problem does this solve?
   - How does it solve the problem?
   - Any breaking changes?
   - Testing notes

6. **Respond to feedback** on code review

7. **Maintainers will merge** after approval

## Reporting Issues

When reporting bugs, include:

1. **Description**: What did you expect vs. what happened?
2. **Reproduction Steps**: How to reproduce the bug
3. **Environment**: Elixir version, PostgreSQL version, etc.
4. **Error Messages**: Full stack traces if available
5. **Minimal Code Example**: Smallest possible reproduction

## Code Review Process

All contributions go through code review:

1. **Correctness**: Does the code do what it claims?
2. **Quality**: Is the code maintainable and performant?
3. **Testing**: Are there adequate tests?
4. **Documentation**: Is it documented for users?
5. **Compatibility**: Does it maintain backward compatibility?

Reviewers may request changes. Please:
- Don't take feedback personally
- Ask for clarification if needed
- Update your PR based on feedback
- Re-request review after changes

## Release Process

ExPgflow follows [Semantic Versioning](https://semver.org/):

- **0.1.0** (current): Initial release, API may change
- **0.x.0**: Minor versions (new features, API additions)
- **1.0.0**: First stable release (stable API)
- **1.x.0**: Subsequent releases

### Publishing to Hex.pm

Only maintainers can publish releases:

1. Update version in `mix.exs`
2. Update `CHANGELOG.md`
3. Commit with message: "Release v0.x.0"
4. Tag commit: `git tag v0.x.0`
5. Push tags: `git push --tags`
6. Publish: `mix hex.publish`

## Questions?

- **General questions**: Check [GETTING_STARTED.md](GETTING_STARTED.md)
- **Architecture questions**: See [ARCHITECTURE.md](ARCHITECTURE.md)
- **Issue or PR**: Open a GitHub issue

Thank you for contributing to ExPgflow!
