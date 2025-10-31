# GitHub Repository Setup for QuantumFlow

This guide covers configuring the GitHub repository for QuantumFlow v0.1.0 release.

## Repository Description

Update the repository description to help potential users understand the project:

### Current Description
```
Elixir implementation of QuantumFlow's database-driven DAG execution engine
```

### Setup Steps

1. Go to https://github.com/mikkihugo/singularity_workflow
2. Click **Settings** (gear icon)
3. In the "General" section at the top, find the **Description** field
4. Update to:
   ```
   Elixir implementation of QuantumFlow - database-driven DAG execution engine with 100% feature parity.
   Parallel execution, map steps, dependency merging, multi-instance scaling via PostgreSQL + pgmq.
   ```
5. Add a **Website** URL (optional):
   ```
   https://hexdocs.pm/singularity_workflow
   ```
6. Click **Save**

## Enable Issues

Issues allow users to report bugs and request features.

### Setup Steps

1. Go to https://github.com/mikkihugo/singularity_workflow/settings
2. Scroll down to **Features** section
3. Check the **Issues** checkbox (should be enabled by default)
4. Click **Save**

## Optional: Enable Discussions

Discussions provide a space for Q&A and community discussion:

1. Go to **Settings**
2. In **Features** section, check **Discussions**
3. Choose template categories or create custom ones
4. Click **Save**

**Suggested Discussion Categories:**
- Q&A - Questions about usage and best practices
- Announcements - Release notes and updates
- Ideas - Feature requests and suggestions
- Show and tell - Community projects using QuantumFlow

## Repository Topics

Add topics to help discoverability:

1. Go to **Settings**
2. Scroll to **Topics** section
3. Add these topics:
   - `elixir`
   - `postgresql`
   - `workflow`
   - `dag`
   - `task-execution`
   - `QuantumFlow`
   - `distributed-systems`

## Branch Protection Rules (Optional)

Protect the `main` branch to enforce quality standards:

1. Go to **Settings → Branches**
2. Click **Add rule**
3. Configure:
   - **Branch name pattern**: `main`
   - **Require pull request reviews before merging**: ✓
   - **Require status checks to pass**: ✓
   - **Require branches to be up to date**: ✓
   - **Require code reviews**: 1 approval
4. Click **Create**

## Labels for Issues

GitHub creates default labels. Customize them for QuantumFlow:

1. Go to **Issues → Labels**
2. Keep/customize these labels:
   - `bug` - Something isn't working (red)
   - `enhancement` - New feature (blue)
   - `documentation` - Docs improvements (light blue)
   - `help wanted` - Need community help (green)
   - `good first issue` - Good for newcomers (light green)
   - `question` - User questions (purple)
   - `test` - Test-related (yellow)

3. Add QuantumFlow-specific labels:
   - `migration` - Related to database migrations
   - `performance` - Performance improvements/issues
   - `security` - Security concerns
   - `workflow-definition` - Workflow definition/parsing
   - `execution` - Task execution/coordination

## GitHub Actions CI/CD (Recommended)

Set up automated testing and quality checks:

### Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:17
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-elixir@v1
        with:
          elixir-version: 1.14.0
          otp-version: 26.0

      - name: Cache deps
        uses: actions/cache@v3
        with:
          path: deps
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-

      - name: Install dependencies
        run: mix deps.get

      - name: Create test database
        run: |
          export PGPASSWORD=postgres
          psql -h localhost -U postgres -c "CREATE DATABASE singularity_workflow_test;"
          psql -h localhost -U postgres singularity_workflow_test -c "CREATE EXTENSION IF NOT EXISTS pgmq;"
        env:
          PGPASSWORD: postgres

      - name: Run tests
        run: mix test
        env:
          DATABASE_URL: "postgres://postgres:postgres@localhost:5432/singularity_workflow_test"

      - name: Run code quality checks
        run: |
          mix format --check-formatted
          mix credo --strict
          mix sobelow --exit-on-warning
          mix deps.audit
```

## Release Process

When publishing v0.1.0:

1. **Create Release Draft**:
   - Go to **Code → Releases**
   - Click **Draft a new release**
   - Tag: `v0.1.0`
   - Title: `QuantumFlow v0.1.0`
   - Description: Copy from CHANGELOG.md

2. **Publish Release**:
   - Click **Publish release**
   - GitHub automatically creates a `.zip` and `.tar.gz` archive

3. **Hex.pm Publication**:
   - After testing release, publish to Hex.pm
   - Link will be available in releases page

## Contributing Guidelines

Make contributing easy by setting up:

### 1. Pull Request Template

Create `.github/pull_request_template.md`:

```markdown
## What does this PR do?

Brief description of changes.

## Related Issues

Fixes #123

## Testing

- [ ] Tests added
- [ ] Tests passing locally (`mix test`)
- [ ] Code quality passing (`mix quality`)

## Checklist

- [ ] Documentation updated
- [ ] CHANGELOG.md updated (if user-facing change)
- [ ] No breaking changes (or documented in CHANGELOG)
```

### 2. Issue Templates

Create `.github/ISSUE_TEMPLATE/bug_report.md`:

```markdown
## Describe the bug

Clear description of what the bug is.

## To reproduce

Steps to reproduce the behavior:
1. ...
2. ...

## Expected behavior

What should happen instead.

## Environment

- Elixir version: `elixir --version`
- PostgreSQL version: `psql --version`
- QuantumFlow version: 0.1.0

## Additional context

Any other context about the problem.
```

Create `.github/ISSUE_TEMPLATE/feature_request.md`:

```markdown
## Is your feature request related to a problem?

Describe the problem.

## Describe the solution you'd like

How you want the feature to work.

## Describe alternatives you've considered

Alternative approaches.

## Additional context

Any other context or screenshots.
```

## Security Policy

Create `SECURITY.md`:

```markdown
# Security Policy

## Reporting a Vulnerability

Please do NOT open a public GitHub issue for security vulnerabilities.

Instead, email security concerns to: [your email]

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will respond within 48 hours and work on a fix in a private security advisory.

## Security Considerations

QuantumFlow is designed for internal use cases. Key security aspects:

- Database connections should use strong credentials
- pgmq queue should not be publicly accessible
- Workflow definitions should be validated before execution
- See [SECURITY_AUDIT.md](SECURITY_AUDIT.md) for detailed analysis
```

## Repository Visibility

Current settings:
- ✅ Public repository (anyone can see and fork)
- ✅ Issues enabled (anyone can report bugs)
- ✅ Discussions enabled (optional - good for Q&A)

## Summary Checklist

- [ ] Repository description updated
- [ ] Website URL set to hexdocs.pm
- [ ] Issues enabled
- [ ] Topics added (elixir, postgresql, workflow, dag, etc.)
- [ ] Labels created/customized
- [ ] GitHub Actions CI/CD configured (optional)
- [ ] PR template created (optional)
- [ ] Issue templates created (optional)
- [ ] Security policy created (optional)
- [ ] Branch protection rules configured (optional)

Once complete, repository is ready to accept community contributions!
