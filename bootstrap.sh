#!/usr/bin/env bash
# =============================================================================
#  bootstrap.sh — one-line beginner install for local-ai-memory.
#
#  Purpose: get the project onto a brand-new machine WITHOUT assuming `git` is
#  installed (the classic "git: command not found" wall), then start the guided
#  installer. Meant to be run as:
#
#      curl -fsSL https://raw.githubusercontent.com/jordglob/local-ai-memory/main/bootstrap.sh | bash
#
#  Cautious? Read this file first (it's short), then run it. It downloads the
#  project's own tarball over HTTPS, unpacks it into your home folder, and runs
#  ai-memory-setup.sh — which itself asks before anything opinionated and uses
#  `sudo` only where it must. This script never calls sudo itself.
# =============================================================================
set -euo pipefail

REPO_TARBALL="https://github.com/jordglob/local-ai-memory/archive/refs/heads/main.tar.gz"
DEST="$HOME/local-ai-memory-main"

say() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Don't run this as root. Run it as your normal user; it asks for a password when it needs one."

say "AI Memory Stack — bootstrap (no git required)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "Downloading the project…"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$REPO_TARBALL" -o "$tmp/lam.tar.gz" || die "Download failed. Check your internet connection and try again."
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$tmp/lam.tar.gz" "$REPO_TARBALL" || die "Download failed. Check your internet connection and try again."
else
  die "This machine has neither 'curl' nor 'wget'. Install one (e.g. 'sudo apt install -y curl'), then re-run."
fi

say "Unpacking to $DEST …"
tar xzf "$tmp/lam.tar.gz" -C "$HOME" || die "Could not unpack the download."

[ -f "$DEST/ai-memory-setup.sh" ] || die "Unpacked, but ai-memory-setup.sh is missing — please report this."

cd "$DEST"
say "Starting the installer. It will explain each step and ask when it needs your password."
say "(Nothing shows on screen while you type a password — that's normal.)"
# setup.sh reads its prompts from /dev/tty, so interactive questions still work
# even though this bootstrap arrived through a pipe.
exec bash ai-memory-setup.sh
