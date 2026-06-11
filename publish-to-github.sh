#!/usr/bin/env bash
# One-command publish: requires GitHub CLI (gh) logged in once: gh auth login
set -euo pipefail
cd "$(dirname "$0")"
command -v gh >/dev/null || { echo "Install GitHub CLI first: https://cli.github.com (brew install gh)"; exit 1; }
gh auth status >/dev/null 2>&1 || gh auth login
gh repo create local-ai-memory --public --source=. --remote=origin --push \
  --description "Consolidate your AI conversations into one local vault — and run a local agent on top. No cloud, no lock-in."
git tag v1.0.0 2>/dev/null || true
git push origin v1.0.0 2>/dev/null || true
echo ""
echo "✓ Published: https://github.com/$(gh api user -q .login)/local-ai-memory"
