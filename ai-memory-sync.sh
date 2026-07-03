#!/usr/bin/env bash
# =============================================================================
#  ai-memory-sync.sh  v1.0
#  Contribute this machine's AI history to a CENTRAL vault — the recurring
#  "scrape locally, push at need" flow for a hub-and-spoke setup (one central
#  memory, satellite machines that sync manually when they have something new).
#
#  This is an OPTIONAL, isolated surface (like remote.sh and mux.sh). It is
#  NOT the one-time migration loop (uninstall --backup → setup --restore) and
#  NOT continuous sync — it is a deliberate, verifiable, add-only hand-off.
#
#  Subcommands:
#    push USER@HOST     scrape this machine (ingest --all), secret-scan, then
#                       add-only rsync of 05-AI-Sessions/ to the central vault,
#                       reindex ON the central, verify counts match
#    status USER@HOST   read-only: compare local vs central conversation counts
#
#  Lessons this script encodes (each one was a real incident):
#    · INDEX.md is NEVER copied — it is derived state and a copied index lies
#      about the receiving side's disk. It is rebuilt on the target instead.
#    · Transfers are ADD-ONLY (--ignore-existing): the target may hold history
#      this machine has never seen; nothing is ever overwritten or deleted.
#    · Outgoing sessions are SECRET-SCANNED first; a hit refuses to travel
#      non-interactively (--yes must not silence a leak).
#    · The push ends by VERIFYING file counts on both sides — a green log
#      that moved nothing is a bug, not a success.
#
#  Config (env or flags; no secrets ever):
#    AI_MEMORY_VAULT         local vault     (default ~/Documents/ai-memory)
#    AI_MEMORY_CENTRAL       default USER@HOST target, so `push` alone works
#    AI_MEMORY_REMOTE_VAULT  vault path on the central, relative to its $HOME
#                            or absolute (default Documents/ai-memory)
#
#  Usage: bash ai-memory-sync.sh push user@host [--vault P] [--no-scrape] [--yes]
#  Exit:  0 = ok · 1 = precondition/refused/verify-failed · 2 = missing dependency
# =============================================================================
set -uo pipefail

if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi
info() { echo -e "${CYAN}→${NC}  $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
err()  { echo -e "${RED}✗${NC}  $*" >&2; }
ok()   { echo -e "${GREEN}✓${NC}  $*"; }

VERSION="1.0"

# ── args ─────────────────────────────────────────────────────────────────────
# --yes is accepted for family-flag consistency (§2.8) but sync never prompts;
# its one refusal (the outgoing secret-scan) is deliberately NOT silenceable.
SUBCMD=""; TARGET=""; VAULT=""; NO_SCRAPE=false; ASSUME_YES=false
REMOTE_VAULT="${AI_MEMORY_REMOTE_VAULT:-Documents/ai-memory}"
prev=""
for arg in "$@"; do
  case "$prev" in
    --vault)        VAULT="$arg";        prev=""; continue ;;
    --remote-vault) REMOTE_VAULT="$arg"; prev=""; continue ;;
  esac
  case "$arg" in
    -h|--help)    sed -n '2,37p' "$0" | sed 's/^#//'; exit 0 ;;
    -V|--version) echo "ai-memory-sync.sh v$VERSION"; exit 0 ;;
    --no-scrape)  NO_SCRAPE=true ;;
    -y|--yes)     ASSUME_YES=true ;;
    --vault|--remote-vault) prev="$arg" ;;
    push|status)  [[ -z "$SUBCMD" ]] && SUBCMD="$arg" ;;
    -*)           ;;
    *)            [[ -z "$TARGET" ]] && TARGET="$arg" ;;
  esac
done
VAULT="${VAULT:-${AI_MEMORY_VAULT:-$HOME/Documents/ai-memory}}"
TARGET="${TARGET:-${AI_MEMORY_CENTRAL:-}}"
SESS="$VAULT/05-AI-Sessions"

# ── preconditions ────────────────────────────────────────────────────────────
for dep in ssh rsync; do
  command -v "$dep" >/dev/null 2>&1 || { err "$dep is required"; exit 2; }
done
if [[ -z "$SUBCMD" || -z "$TARGET" ]]; then
  err "usage: bash ai-memory-sync.sh push|status USER@HOST   (or set AI_MEMORY_CENTRAL)"
  exit 1
fi
if [[ ! -d "$SESS" ]]; then
  err "no local vault at $VAULT (missing 05-AI-Sessions) — run ai-memory-setup.sh first"
  exit 1
fi

SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=8"
remote() { ssh $SSH_OPTS "$TARGET" "$@"; }

count_local()  { find "$SESS" -name "*.md" ! -name "INDEX.md" 2>/dev/null | wc -l | tr -d ' '; }
count_remote() { remote "find '$REMOTE_VAULT/05-AI-Sessions' -name '*.md' ! -name 'INDEX.md' 2>/dev/null | wc -l" 2>/dev/null | tr -d ' \r'; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   AI Memory Stack  v$VERSION — Sync           ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
info "local vault:  $VAULT"
info "central:      $TARGET:$REMOTE_VAULT"

if ! remote "true" 2>/dev/null; then
  err "cannot reach $TARGET over ssh (key-based, non-interactive)"
  err "   check: ssh $TARGET   — and that your key is in its authorized_keys"
  exit 1
fi

# ── status: read-only compare ────────────────────────────────────────────────
if [[ "$SUBCMD" = "status" ]]; then
  ln=$(count_local); rn=$(count_remote)
  info "conversations here:    ${ln:-0}"
  info "conversations central: ${rn:-0 (no vault found)}"
  if [[ -n "$rn" && "$rn" -ge "$ln" ]]; then
    ok "central is complete (holds everything this machine has)"
  else
    warn "central is BEHIND this machine — run: bash ai-memory-sync.sh push $TARGET"
  fi
  exit 0
fi

# ── push step 1: scrape this machine ─────────────────────────────────────────
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INGEST=""
for cand in "$here/ai-memory-ingest.sh" "$VAULT/.tools/ai-memory-ingest.sh"; do
  [[ -f "$cand" ]] && { INGEST="$cand"; break; }
done
if $NO_SCRAPE; then
  info "skipping local scrape (--no-scrape)"
elif [[ -n "$INGEST" ]]; then
  info "scraping this machine (ingest --all) ..."
  bash "$INGEST" "$VAULT" --all --yes 2>/dev/null | sed -n '/TOTAL/p' || true
else
  warn "ai-memory-ingest.sh not found — pushing what is already in the vault"
fi

# ── push step 2: secret-scan what is about to travel ─────────────────────────
# The scrub in ingest v2.14+ redacts on import, but files written by OLDER
# versions (or edited by hand) may still carry a pasted key. A leak must not
# cross the network silently — and --yes must not become the silencer.
leaks=$(grep -rlE '\bsk-[A-Za-z0-9_-]{16,}|\bgh[pousr]_[A-Za-z0-9]{30,}|\bAKIA[0-9A-Z]{16}|\bxox[baprs]-[A-Za-z0-9-]{10,}|BEGIN [A-Z ]*PRIVATE KEY' \
        "$SESS" 2>/dev/null | head -5 || true)
if [[ -n "$leaks" ]]; then
  err "possible secrets found in outgoing sessions:"
  echo "$leaks" | sed 's/^/      /'
  err "refusing to push. Re-run ingest (v2.14+ self-sanitizes on re-import),"
  err "or redact these files by hand, then push again."
  $ASSUME_YES && warn "(--yes does not override the secret gate — by design)"
  exit 1
fi
ok "secret-scan clean"

# ── push step 3: add-only transfer (never INDEX.md, never a delete) ──────────
remote "mkdir -p '$REMOTE_VAULT/05-AI-Sessions' '$REMOTE_VAULT/.tools'" 2>/dev/null
info "pushing new sessions (add-only) ..."
rsync -a --ignore-existing --exclude 'INDEX.md' -e "ssh $SSH_OPTS" \
  "$SESS/" "$TARGET:$REMOTE_VAULT/05-AI-Sessions/" || { err "transfer failed"; exit 1; }
# Keep the central's toolbox current so the reindex below runs today's code.
if [[ -n "$INGEST" ]]; then
  rsync -a -e "ssh $SSH_OPTS" "$INGEST" "$TARGET:$REMOTE_VAULT/.tools/ai-memory-ingest.sh" 2>/dev/null || true
fi

# ── push step 4: reindex ON the central (derived state is rebuilt, not copied) ─
info "rebuilding index on the central ..."
if remote "command -v python3 >/dev/null && bash '$REMOTE_VAULT/.tools/ai-memory-ingest.sh' '$REMOTE_VAULT' --reindex" 2>/dev/null | grep -q "Index rebuilt"; then
  ok "central index rebuilt"
else
  warn "could not rebuild the central index (python3 or .tools missing there?)"
  warn "   run on the central: bash $REMOTE_VAULT/.tools/ai-memory-ingest.sh --reindex"
fi

# ── push step 5: verify — counts must prove the move happened ────────────────
ln=$(count_local); rn=$(count_remote)
info "conversations here:    ${ln:-0}"
info "conversations central: ${rn:-?}"
if [[ -n "$rn" ]] && [[ "$rn" -ge "$ln" ]] 2>/dev/null; then
  ok "verified: the central holds everything this machine has"
else
  err "VERIFY FAILED: central ($rn) is missing files this machine has ($ln)"
  exit 1
fi

echo ""
echo -e "${BOLD}▶ NEXT${NC}  health-check the central:  ssh $TARGET 'bash $REMOTE_VAULT/.tools/ai-memory-doctor.sh'"
