#!/bin/bash
# Setup GitHub branch protection and release approval
# Requires gh CLI and appropriate permissions

set -e

echo "🔒 Setting up GitHub Protection Rules"
echo "====================================="
echo ""

REPO="mikkihugo/ex_pgflow"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "📝 Setting up branch protection for main branch..."

# Create branch protection rule for main
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/$REPO/branches/main/protection \
  -f required_status_checks='{"strict":true,"contexts":["CI Tests"]}' \
  -f enforce_admins=false \
  -f required_pull_request_reviews='{"dismiss_stale_reviews":true,"require_code_owner_reviews":true,"required_approving_review_count":1}' \
  -f restrictions=null \
  -f allow_force_pushes=false \
  -f allow_deletions=false \
  -f required_conversation_resolution=true \
  -f lock_branch=false \
  -f allow_fork_syncing=false 2>/dev/null || {
    echo -e "${YELLOW}⚠ Branch protection might already exist or you need admin access${NC}"
}

echo ""
echo "🌍 Setting up production environment for release approval..."

# Create production environment with protection rules
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/$REPO/environments/production \
  -f wait_timer=0 \
  -f reviewers='[{"type":"User","id":0}]' \
  -f deployment_branch_policy='{"protected_branches":false,"custom_branch_policies":true}' 2>/dev/null || {

    # If creation fails, just update the environment
    echo "Environment might already exist, updating protection rules..."

    # Note: You'll need to manually add reviewers through GitHub UI
    echo -e "${YELLOW}⚠ Please manually configure environment protection:${NC}"
    echo "  1. Go to https://github.com/$REPO/settings/environments"
    echo "  2. Click on 'production' environment"
    echo "  3. Enable 'Required reviewers'"
    echo "  4. Add yourself or team members as reviewers"
    echo "  5. Optionally add deployment branch restrictions (tags only)"
}

echo ""
echo "🏷️ Setting up tag protection..."

# Create tag protection rule for version tags
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/$REPO/tags/protection \
  -f pattern='v*' 2>/dev/null || {
    echo -e "${YELLOW}⚠ Tag protection might already exist${NC}"
}

echo ""
echo -e "${GREEN}✅ Protection setup complete!${NC}"
echo ""
echo "📋 Summary of protections:"
echo ""
echo "1. Main Branch Protection:"
echo "   - Requires pull request with 1 review"
echo "   - Requires CI tests to pass"
echo "   - Dismisses stale reviews on new commits"
echo "   - Requires code owner review (CODEOWNERS file)"
echo "   - Requires conversation resolution"
echo ""
echo "2. Release Approval (Production Environment):"
echo "   - Manual approval required before publishing"
echo "   - Configure reviewers at: https://github.com/$REPO/settings/environments"
echo ""
echo "3. Tag Protection:"
echo "   - Only maintainers can create v* tags"
echo ""
echo "🎯 Release workflow now requires:"
echo "   1. CI tests must pass"
echo "   2. Manual approval in 'production' environment"
echo "   3. Then auto-publishes to Hex.pm"
echo ""
echo "⚠️ IMPORTANT: Manually configure environment reviewers at:"
echo "   https://github.com/$REPO/settings/environments/production"