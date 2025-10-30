#!/bin/bash
set -e

echo "🚀 Setting up GitHub repository for QuantumFlow v0.1.0"
echo ""

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) not found. Please install it:"
    echo "   brew install gh  (macOS)"
    echo "   nix shell"
    exit 1
fi

REPO="mikkihugo/quantum_flow"

# Authenticate with GitHub if needed
if ! gh auth status &> /dev/null; then
    echo "🔐 Authenticating with GitHub..."
    gh auth login
fi

echo "✅ Using repository: $REPO"
echo ""

# Update repository description
echo "📝 Updating repository description..."
gh repo edit "$REPO" \
    --description "Elixir implementation of QuantumFlow - database-driven DAG execution engine with 100% feature parity. Parallel execution, map steps, dependency merging, multi-instance scaling via PostgreSQL + pgmq." \
    --homepage "https://hexdocs.pm/quantum_flow"

# Add topics
echo "🏷️  Adding repository topics..."
gh repo edit "$REPO" --add-topic "elixir"
gh repo edit "$REPO" --add-topic "postgresql"
gh repo edit "$REPO" --add-topic "workflow"
gh repo edit "$REPO" --add-topic "dag"
gh repo edit "$REPO" --add-topic "task-execution"
gh repo edit "$REPO" --add-topic "QuantumFlow"
gh repo edit "$REPO" --add-topic "distributed-systems"

# Enable Issues (should be on by default)
echo "🐛 Ensuring Issues are enabled..."
gh repo edit "$REPO" --enable-issues

# Enable Discussions (optional but helpful for Q&A)
echo "💬 Enabling Discussions..."
gh repo edit "$REPO" --enable-discussions || echo "⚠️  Discussions may already be enabled"

echo ""
echo "✨ GitHub repository setup complete!"
echo ""
echo "Next steps:"
echo "1. Visit: https://github.com/$REPO"
echo "2. Check Settings → General to verify configuration"
echo "3. Go to Actions tab to see CI/CD in action on next push"
echo ""
echo "Users can now:"
echo "  ✓ Open issues for bugs and feature requests"
echo "  ✓ View automatically generated documentation"
echo "  ✓ See CI/CD status on pull requests"
