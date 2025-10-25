# Release Process for ex_pgflow

## CI/CD Protection

The release process is protected by GitHub Actions workflows to ensure quality:

1. **CI must pass** - The `CI` workflow runs on all tags starting with `v*`
2. **Publish requires CI success** - The `Publish to Hex.pm` workflow only runs after CI succeeds
3. **Automated publishing** - If CI passes, the package is automatically published to Hex.pm

## Pre-Release Checklist

Before creating a release tag, run the release checklist script:

```bash
./scripts/release-checklist.sh
```

This script verifies:
- ✅ On main branch
- ✅ Working directory is clean
- ✅ Up to date with origin/main
- ✅ All tests pass
- ✅ Code is formatted
- ✅ Credo analysis passes
- ✅ Dialyzer type checking passes
- ✅ Sobelow security audit passes
- ✅ Documentation builds successfully
- ✅ CHANGELOG.md is updated
- ✅ mix.exs version matches release

## Release Steps

### 1. Update Version

Update version in `mix.exs`:
```elixir
def project do
  [
    app: :ex_pgflow,
    version: "0.1.0",  # Update this
    ...
  ]
end
```

### 2. Update CHANGELOG

Add release notes to `CHANGELOG.md` under the appropriate version header.

### 3. Commit Changes

```bash
git add -A
git commit -m "Prepare v0.1.0 release"
git push origin main
```

### 4. Run Release Checklist

```bash
./scripts/release-checklist.sh
```

Only proceed if all checks pass!

### 5. Create and Push Tag

```bash
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

### 6. Monitor CI/CD

1. Go to [GitHub Actions](https://github.com/mikkihugo/ex_pgflow/actions)
2. Watch the CI workflow run on your tag
3. If CI passes, the Publish workflow will automatically:
   - Publish to Hex.pm
   - Create a GitHub Release

## What Gets Published to Hex.pm

The Hex package includes only essential files:
- `lib/` - Source code
- `priv/repo/migrations/` - Database migrations
- `mix.exs` - Package configuration
- `README.md` - Main documentation
- `LICENSE.md` - MIT License
- `CHANGELOG.md` - Version history
- `GETTING_STARTED.md` - Installation guide
- `ARCHITECTURE.md` - Technical documentation
- `CONTRIBUTING.md` - Contribution guidelines

**Excluded from Hex package:**
- `.github/` - GitHub Actions workflows
- `.claude/` - Claude AI files
- `test/` - Test files
- `docs/` - Additional documentation
- `scripts/` - Development scripts
- `.formatter.exs` - Formatter config
- `.git/` - Git repository

## Troubleshooting

### CI Fails on Tag

1. Fix the issues locally
2. Delete the tag: `git tag -d v0.1.0 && git push origin :v0.1.0`
3. Commit fixes
4. Create the tag again

### Hex.pm Publishing Fails

Check that `HEX_API_KEY` is set in GitHub Secrets:
1. Go to Settings → Secrets → Actions
2. Verify `HEX_API_KEY` exists
3. Update if needed (get key from `mix hex.user key generate`)

### Manual Publishing (Emergency Only)

If automation fails, you can publish manually:

```bash
mix hex.publish
```

You'll be prompted for confirmation and Hex.pm credentials.

## Post-Release

After successful release:

1. Verify package on [Hex.pm](https://hex.pm/packages/ex_pgflow)
2. Check documentation on [HexDocs](https://hexdocs.pm/ex_pgflow)
3. Update main branch for next version:
   ```elixir
   version: "0.2.0-dev",  # Next version with -dev suffix
   ```
4. Add new "Unreleased" section to CHANGELOG.md
5. Announce release (optional)