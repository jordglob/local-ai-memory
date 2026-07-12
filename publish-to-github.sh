#!/usr/bin/env bash
# One-command publish: requires GitHub CLI (gh) logged in once: gh auth login
# Publishes UNSUPPORTED, with Issues OFF (see the README "Status" banner).
# Usage: bash publish-to-github.sh [vX.Y.Z]
#   Pass a tag to tag this publish; with no argument NO tag is created —
#   tagging is a deliberate act, not a side effect of publishing.
set -euo pipefail
cd "$(dirname "$0")"
command -v gh >/dev/null || { echo "Install GitHub CLI first: https://cli.github.com (brew install gh)"; exit 1; }
gh auth status >/dev/null 2>&1 || gh auth login

LOGIN="$(gh api user -q .login)"
DESC="Own your AI conversation history as a local markdown vault + run a local agent on it. Source-available, unsupported, for technical users."

gh repo create local-ai-memory --public --source=. --remote=origin --push --description "$DESC"

# Unsupported by design — turn off the channels that imply a maintainer.
gh repo edit "$LOGIN/local-ai-memory" \
  --enable-issues=false --enable-projects=false --enable-wiki=false 2>/dev/null \
  || echo "Note: could not toggle features automatically — turn Issues OFF in repo Settings → Features."

TAG="${1:-}"
if [[ -n "$TAG" ]]; then
  git tag "$TAG"
  git push origin "$TAG"
  echo "Tagged $TAG."
else
  echo "No tag created (to tag a release: bash publish-to-github.sh v1.2.0)."
fi
echo ""
echo "✓ Published (Issues OFF, unsupported): https://github.com/$LOGIN/local-ai-memory"
