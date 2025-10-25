#!/bin/bash
# Release Checklist Script for ex_pgflow
# Run this before creating a version tag to ensure everything is ready

set -e

echo "🚀 ex_pgflow Release Checklist"
echo "=============================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track if we have any failures
FAILED=0

# Function to check a condition
check() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        FAILED=1
    fi
}

echo "📋 Running pre-release checks..."
echo ""

# 1. Check if on main branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" = "main" ]; then
    check 0 "On main branch"
else
    check 1 "On main branch (currently on $CURRENT_BRANCH)"
fi

# 2. Check if working directory is clean
if git diff-index --quiet HEAD --; then
    check 0 "Working directory is clean"
else
    check 1 "Working directory is clean (uncommitted changes)"
fi

# 3. Check if up to date with remote
git fetch origin main --quiet
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)
if [ "$LOCAL" = "$REMOTE" ]; then
    check 0 "Up to date with origin/main"
else
    check 1 "Up to date with origin/main"
fi

# 4. Run tests
echo ""
echo "🧪 Running tests..."
mix test > /dev/null 2>&1
check $? "All tests pass"

# 5. Check formatting
mix format --check-formatted > /dev/null 2>&1
check $? "Code is formatted"

# 6. Run Credo
mix credo --strict > /dev/null 2>&1
check $? "Credo analysis passes"

# 7. Run Dialyzer
echo ""
echo "🔍 Running Dialyzer (this may take a moment)..."
mix dialyzer > /dev/null 2>&1
check $? "Dialyzer type checking passes"

# 8. Run Sobelow security check
mix sobelow --exit-on-warning > /dev/null 2>&1
check $? "Sobelow security audit passes"

# 9. Check documentation
mix docs > /dev/null 2>&1
check $? "Documentation builds successfully"

# 10. Verify CHANGELOG.md is updated
if grep -q "## \[0.1.0\]" CHANGELOG.md; then
    check 0 "CHANGELOG.md is updated for v0.1.0"
else
    check 1 "CHANGELOG.md is updated for v0.1.0"
fi

# 11. Verify mix.exs version matches intended release
VERSION=$(grep 'version:' mix.exs | head -1 | sed 's/.*version: "\(.*\)".*/\1/')
if [ "$VERSION" = "0.1.0" ]; then
    check 0 "mix.exs version is 0.1.0"
else
    check 1 "mix.exs version is 0.1.0 (currently $VERSION)"
fi

# 12. Check if HEX_API_KEY is set in GitHub secrets (can't verify directly)
echo ""
echo -e "${YELLOW}⚠${NC}  Ensure HEX_API_KEY is set in GitHub Secrets"

# Summary
echo ""
echo "=============================="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo ""
    echo "Ready to create a release tag:"
    echo "  git tag -a v0.1.0 -m \"Release v0.1.0\""
    echo "  git push origin v0.1.0"
    echo ""
    echo "The CI/CD pipeline will:"
    echo "1. Run all tests again"
    echo "2. Publish to Hex.pm if tests pass"
    echo "3. Create a GitHub release"
else
    echo -e "${RED}❌ Some checks failed!${NC}"
    echo ""
    echo "Please fix the issues above before creating a release tag."
    exit 1
fi