# Release Process for quantum_flow

## CI/CD Protection

The release process has multiple protection layers to ensure quality:

1. **CI must pass** - All tests, formatting, and security checks must succeed
2. **Manual approval required** - A designated reviewer must approve the release
3. **Then auto-publishes** - After approval, the package is automatically published to Hex.pm

### Protection Layers

#### 1. Branch Protection (for main)
- Pull requests required with code review
- CI status checks must pass
- Code owner review required (via CODEOWNERS file)

#### 2. Release Approval Gate
- Uses GitHub Environment Protection
- Requires manual approval in 'production' environment
- Reviewers are notified when a release is pending

#### 3. Tag Protection
- Only maintainers can create `v*` tags
- Prevents accidental releases

## Pre-Release Checks

All checks are **automated in the CI workflow**:

✅ **Automatic Checks** (run on every tag):
- Tests pass
- Code is formatted
- Credo analysis passes
- Dialyzer type checking passes
- Sobelow security audit passes
- Dependencies are audited
- Documentation builds successfully
- CHANGELOG.md is updated (for release tags)
- mix.exs version matches the tag (for release tags)

**Local Verification (Optional)**:
If you want to verify before pushing a tag:
```bash
./scripts/release-checklist.sh
```

## Release Steps

### 1. Update Version

Update version in `mix.exs`:
```elixir
def project do
  [
    app: :quantum_flow,
    version: "0.1.0",  # Must match tag below
    ...
  ]
end
```

### 2. Update CHANGELOG

Add release notes to `CHANGELOG.md` with this header:
```markdown
## [0.1.0] - 2025-10-25

### Added
- Initial release of quantum_flow
```

### 3. Commit Changes

```bash
git add mix.exs CHANGELOG.md
git commit -m "Prepare v0.1.0 release"
git push origin main
```

### 4. Create and Push Tag

This is the **only** command you need:
```bash
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

**Important:**
- Tag MUST start with `v` (e.g., `v0.1.0`)
- Version in tag MUST match `version:` in `mix.exs`
- CHANGELOG MUST have `## [0.1.0]` header

### 5. Workflow Runs Automatically

1. Push triggers CI workflow
2. CI runs all checks:
   - ✅ Tests pass (PostgreSQL 18 + Elixir 1.19)
   - ✅ Dialyzer type checking
   - ✅ Security audit
   - ✅ CHANGELOG verification
   - ✅ Version match verification
3. If CI passes → waits for approval
4. Approve in GitHub → auto-publishes to Hex.pm

**View Progress:**
- Go to [GitHub Actions](https://github.com/mikkihugo/quantum_flow/actions)
- Click on your version tag workflow
- Click "Approve" when ready to publish

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

## Initial Setup (One-time)

### Configure GitHub Protection

Run the protection setup script:
```bash
chmod +x scripts/setup-github-protection.sh
./scripts/setup-github-protection.sh
```

Then manually configure environment reviewers:
1. Go to [Settings → Environments](https://github.com/mikkihugo/quantum_flow/settings/environments)
2. Click on 'production' environment
3. Enable "Required reviewers"
4. Add reviewers (yourself, team members, or teams)
5. Save protection rules

### Setup Complete!

Now every release will require:
- ✅ CI tests to pass
- ✅ Manual approval from designated reviewer
- ✅ Then auto-publish to Hex.pm

## Post-Release

After successful release:

1. Verify package on [Hex.pm](https://hex.pm/packages/quantum_flow)
2. Check documentation on [HexDocs](https://hexdocs.pm/quantum_flow)
3. Update main branch for next version:
   ```elixir
   version: "0.2.0-dev",  # Next version with -dev suffix
   ```
4. Add new "Unreleased" section to CHANGELOG.md
5. Announce release (optional)