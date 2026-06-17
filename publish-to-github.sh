#!/usr/bin/env bash
# One-command publish: requires GitHub CLI (gh) logged in once: gh auth login
# Publishes UNSUPPORTED, with Issues OFF (see the README "Status" banner).
set -euo pipefail
cd "$(dirname "$0")"
command -v gh >/dev/null || { echo "Install GitHub CLI first: https://cli.github.com (brew install gh)"; exit 1; }
gh auth status >/dev/null 2>&1 || gh auth login

LOGIN="$(gh api user -q .login)"
DESC="Own your AI conversation history as a local markdown vault + run a local agent on it. Source-available, unsupported, for technical users."

# Put the real clone URL into the README before the first push (was a placeholder).
if grep -q 'YOUR-USERNAME' README.md; then
  sed -i.bak "s|YOUR-USERNAME|$LOGIN|g" README.md && rm -f README.md.bak
  git add README.md
  git commit -m "README: set clone URL to $LOGIN" >/dev/null 2>&1 || true
fi

gh repo create local-ai-memory --public --source=. --remote=origin --push --description "$DESC"

# Unsupported by design — turn off the channels that imply a maintainer.
gh repo edit "$LOGIN/local-ai-memory" \
  --enable-issues=false --enable-projects=false --enable-wiki=false 2>/dev/null \
  || echo "Note: could not toggle features automatically — turn Issues OFF in repo Settings → Features."

git tag v1.0.0 2>/dev/null || true
git push origin v1.0.0 2>/dev/null || true
echo ""
echo "✓ Published (Issues OFF, unsupported): https://github.com/$LOGIN/local-ai-memory"
