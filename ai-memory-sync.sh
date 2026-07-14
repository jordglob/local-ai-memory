#!/usr/bin/env bash
# =============================================================================
#  ai-memory-sync.sh  v1.3
#  v1.3: NEVER-DOWNGRADE tool install. push used to rsync its own
#        ai-memory-ingest.sh onto the central unconditionally — so one stale
#        clone on any machine silently reverted the central's tools on every
#        push (live incident 2026-07-14→15: a v2.26 clone's nightly autosync
#        overwrote the central's v3.1 at 21:00 each evening). Now the install
#        happens only when the local version is STRICTLY newer (sort -V via
#        _tool_newer; missing remote = first install; unparsable local =
#        install nothing), and lib/ ships along with the launcher — a v3.0+
#        launcher is thin and dead without its engine.
#  v1.2: comment-only — the remote and mux scripts moved to the companion
#        repo local-ai-memory-fleet; the "isolated surface" note no longer
#        names scripts that don't ship in this repo. No behavior change.
#  v1.1: (1) the outgoing secret gate now matches ingest's FULL scrub set
#        (github_pat_, AIza, whsec_, JWTs were missing — tests/run.sh now
#        enforces parity so the two lists can never drift again). (2) the
#        local scrape's stderr and exit code are surfaced — a failed ingest
#        WARNS loudly but does not block the push (the vault still holds
#        everything that DID import; blocking would strand good data).
#        (3) files UPDATED locally (re-scrubbed by a newer ingest, retitled
#        in place) that the add-only rsync will never replace on the central
#        are DETECTED and listed with the exact command to push them
#        deliberately — overwriting the central stays a human decision
#        because add-only is this script's hard promise.
#  Contribute this machine's AI history to a CENTRAL vault — the recurring
#  "scrape locally, push at need" flow for a hub-and-spoke setup (one central
#  memory, satellite machines that sync manually when they have something new).
#
#  This is an OPTIONAL, isolated surface (like the fleet scripts in the
#  companion repo local-ai-memory-fleet). It is
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

VERSION="1.3"

# v1.3: strictly-newer version check for tool installs on the central.
# Usage: _tool_newer LOCAL_VER REMOTE_VER → 0 iff LOCAL is strictly newer
# (an empty/unreadable REMOTE counts as older — first install).
_tool_newer() {
  [[ -z "$2" ]] && return 0
  [[ "$1" == "$2" ]] && return 1
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -1)" == "$1" ]]
}

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
    -h|--help)    sed -n '2,47p' "$0" | sed 's/^#//'; exit 0 ;;
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
  # stderr flows through and the exit code is CHECKED (v1.1) — the old
  # `2>/dev/null … || true` hid every scrape failure behind a green push.
  # Policy: a failed scrape warns loudly but does NOT block the push — the
  # vault still holds everything that DID import, and blocking would strand
  # good data. (`set -o pipefail` carries ingest's exit code past the sed.)
  if ! bash "$INGEST" "$VAULT" --all --yes | sed -n '/TOTAL/p'; then
    warn "local scrape reported FAILURES (see errors above) — pushing what DID"
    warn "import; fix the failing source, then push again."
  fi
else
  warn "ai-memory-ingest.sh not found — pushing what is already in the vault"
fi

# ── push step 2: secret-scan what is about to travel ─────────────────────────
# The scrub in ingest v2.14+ redacts on import, but files written by OLDER
# versions (or edited by hand) may still carry a pasted key. A leak must not
# cross the network silently — and --yes must not become the silencer.
# SECRET_ERE mirrors ingest's _SECRET_PATTERNS one-to-one (v1.1) — grep is
# line-based, so the private-key pattern is its BEGIN marker only. Keep the
# two lists in lockstep: tests/run.sh extracts BOTH and fails on any drift.
SECRET_ERE='\bsk-[A-Za-z0-9_-]{16,}|\bgh[pousr]_[A-Za-z0-9]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{22,}\b|\bAKIA[0-9A-Z]{16}\b|\bAIza[0-9A-Za-z_-]{35}\b|\bxox[baprs]-[A-Za-z0-9-]{10,}\b|\bwhsec_[A-Za-z0-9]{16,}\b|\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}\b|-----BEGIN [A-Z ]*PRIVATE KEY-----'
leaks=$(grep -rlE "$SECRET_ERE" "$SESS" 2>/dev/null | head -5 || true)
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
# v1.1: --ignore-existing means a file UPDATED locally (re-scrubbed by a newer
# ingest, retitled in place, a grown chat) is never pushed over the central's
# older copy — including a copy that still carries a secret the local re-scrub
# removed. Overwriting automatically would break the add-only promise (the
# central may hold intentional edits), so the honest minimal fix: DETECT the
# divergence (checksum dry-run over files existing on BOTH sides) and print
# the exact command for a deliberate, human-decided update push.
if difflist=$(rsync -rcn --existing --exclude 'INDEX.md' --out-format='%n' \
     -e "ssh $SSH_OPTS" "$SESS/" "$TARGET:$REMOTE_VAULT/05-AI-Sessions/" 2>/dev/null); then
  difflist=$(printf '%s\n' "$difflist" | grep -v '/$' | grep -v '^$' || true)
  if [[ -n "$difflist" ]]; then
    ndiff=$(printf '%s\n' "$difflist" | wc -l | tr -d ' ')
    warn "$ndiff local file(s) DIFFER from the central's copy and were NOT pushed (add-only):"
    printf '%s\n' "$difflist" | head -10 | sed 's/^/      /'
    [[ "$ndiff" -gt 10 ]] && echo "      … ($((ndiff-10)) more)"
    warn "if the LOCAL versions are the keepers (e.g. re-scrubbed), push them deliberately:"
    echo "      rsync -rc --existing --exclude 'INDEX.md' -e \"ssh $SSH_OPTS\" '$SESS/' '$TARGET:$REMOTE_VAULT/05-AI-Sessions/'"
  fi
else
  warn "could not compare local vs central copies (rsync too old for the dry-run?) —"
  warn "locally re-scrubbed/retitled files may silently differ on the central."
fi
# Keep the central's toolbox current so the reindex below runs today's code —
# but NEVER DOWNGRADE it (v1.3). The old unconditional install let any stale
# clone overwrite the central's newer tools on every push (live incident
# 2026-07-14→15: a v2.26 clone's nightly push reverted the central's v3.1 fix
# at 21:00 each evening). Install only when the local copy is strictly newer,
# and ship lib/ along with it — a v3.0+ launcher is thin and dead without its
# engine. An unparsable local version installs nothing (can't prove newer).
if [[ -n "$INGEST" ]]; then
  lver=$(sed -n 's/^#  ai-memory-ingest\.sh  v\([0-9][0-9.]*\).*/\1/p' "$INGEST" | head -1)
  rver=$(remote "sed -n 's/^#  ai-memory-ingest\.sh  v\([0-9][0-9.]*\).*/\1/p' '$REMOTE_VAULT/.tools/ai-memory-ingest.sh' 2>/dev/null" | head -1)
  if [[ -n "$lver" ]] && _tool_newer "$lver" "$rver"; then
    rsync -a -e "ssh $SSH_OPTS" "$INGEST" "$TARGET:$REMOTE_VAULT/.tools/ai-memory-ingest.sh" 2>/dev/null || true
    libdir="$(cd "$(dirname "$INGEST")" && pwd)/lib"
    if [[ -d "$libdir" ]]; then
      remote "mkdir -p '$REMOTE_VAULT/.tools/lib'" 2>/dev/null
      rsync -a -e "ssh $SSH_OPTS" "$libdir/" "$TARGET:$REMOTE_VAULT/.tools/lib/" 2>/dev/null || true
    fi
    info "central toolbox updated: v${rver:-none} → v$lver"
  else
    info "central toolbox kept at v${rver:-?} (local is v${lver:-unparsable} — not newer)"
  fi
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
