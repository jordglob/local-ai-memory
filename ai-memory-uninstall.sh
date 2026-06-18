#!/usr/bin/env bash
# =============================================================================
#  ai-memory-uninstall.sh  v1.1
#  AI Memory Stack — clean reversal, EXPORT-FIRST
#
#  Reverses what setup / configure / ingest installed, but ALWAYS exports your
#  vault (your irreplaceable imported memory) to a timestamped archive BEFORE
#  removing anything. Default mode is a DRY-RUN preview: it changes nothing and
#  shows exactly what would be exported and removed.
#
#  Removes (core stack):
#    vault tree (only after export) · ~/.hermes · mcpvault (npm global) ·
#    Ollama autostart service/agent · Claude Desktop MCP entry ·
#    Session Continuity skill · shell-rc hermes() launcher · temp logs/checkpoints
#
#  KEPT unless you opt in:
#    Ollama runtime + downloaded models   (--remove-ollama)
#    Node.js / npm prefix                 (too shared — never removed)
#    remote.sh changes (sshd/WireGuard/…) (increment 2 — --remote, not yet built)
#
#  Usage:  bash ai-memory-uninstall.sh [path/to/vault] [flags]
#
#  Safe to re-run — idempotent. Never touches ~/.paperclip or anything we did
#  not create. Never runs sudo. Language: English. bash 3.2 compatible.
# =============================================================================

set -euo pipefail

VERSION="1.1"

# ── --help / --version (before anything else) ────────────────────────────────
case "${1:-}" in
  -h|--help)
    cat << 'HELP'
ai-memory-uninstall.sh — clean reversal of the AI Memory Stack (export-first)

Usage:
  bash ai-memory-uninstall.sh [path/to/vault] [flags]

Flags:
  (default)          DRY-RUN: preview only — exports/removes NOTHING
  --yes, -y          actually export + remove (non-interactive, no prompt)
  --export-only      export the vault to an archive, then STOP (remove nothing)
  --backup           alias for --export-only — back up / prepare to move machines
                     (restore on the new machine with: ai-memory-setup.sh --restore)
  --no-export        skip the vault export (requires an extra loud confirm)
  --remove-ollama    ALSO remove downloaded Ollama models (opt-in; off by default)
  --remote           reverse remote.sh changes too (increment 2 — not yet built)
  --help / --version

What it removes (core stack): the vault (only AFTER a successful export),
~/.hermes, mcpvault (npm global), the Ollama autostart service/agent, the
Claude Desktop MCP entry, the Session Continuity skill, the shell-rc hermes()
launcher, and temp logs/checkpoints.

What it KEEPS unless told otherwise: Node.js + npm prefix (shared), the Ollama
runtime + models (--remove-ollama), and all remote-access changes (--remote).

Never touches ~/.paperclip. Never runs sudo. Idempotent — safe to re-run.
HELP
    exit 0 ;;
  -V|--version)
    echo "ai-memory-uninstall.sh v$VERSION"; exit 0 ;;
esac

# ── TTY / interactivity detection ────────────────────────────────────────────
IS_TTY=false
[[ -t 1 ]] && IS_TTY=true
CAN_PROMPT=false
# Probe by actually OPENING /dev/tty: the node can be rw yet unusable when there
# is no controlling terminal (open ENXIOs), so `[[ -r/-w ]]` is a false positive.
{ : >/dev/tty; } 2>/dev/null && CAN_PROMPT=true

# ── Colors (only when stdout is a terminal) ──────────────────────────────────
if $IS_TTY; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

ok()    { echo -e "${GREEN}✓${NC}  $*"; }
info()  { echo -e "${CYAN}→${NC}  $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
die()   { echo -e "\n${RED}${BOLD}✗  ERROR: $*${NC}\n" >&2; exit 1; }
hdr()   { echo -e "\n${BOLD}── $* ──${NC}"; }
blank() { echo ""; }
lc()    { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ── Flags ────────────────────────────────────────────────────────────────────
ASSUME_YES=false
EXPORT_ONLY=false
DO_EXPORT=true
REMOVE_OLLAMA=false
DO_REMOTE=false
VAULT=""
for arg in "$@"; do
  case "$arg" in
    --yes|-y)        ASSUME_YES=true ;;
    --export-only)   EXPORT_ONLY=true ;;
    --backup)        EXPORT_ONLY=true ;;   # friendly alias: back up / prepare to migrate
    --no-export)     DO_EXPORT=false ;;
    --remove-ollama) REMOVE_OLLAMA=true ;;
    --remote)        DO_REMOTE=true ;;
    -*)              echo "Unknown flag: $arg (see --help)" >&2; exit 1 ;;
    *)               [[ -z "$VAULT" ]] && VAULT="$arg" ;;
  esac
done

# DRY_RUN is the default. --yes or --export-only switch to a real run.
DRY_RUN=true
{ $ASSUME_YES || $EXPORT_ONLY; } && DRY_RUN=false

# ── Guard: never run as root (we only touch the user's own files) ────────────
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  die "Do not run this as root or with sudo.\n  Run it as your normal user — it only removes things in your home folder."
fi

# ── Resolve the vault path ───────────────────────────────────────────────────
VAULT="${VAULT:-$HOME/Documents/ai-memory}"
if command -v realpath &>/dev/null; then
  VAULT="$(realpath -m "$VAULT" 2>/dev/null || echo "$VAULT")"
fi
[[ "$VAULT" != /* ]] && VAULT="$PWD/$VAULT"

# ── Paths every installer in the family creates (single source of truth) ─────
OS="linux"; [[ "$OSTYPE" == "darwin"* ]] && OS="macos"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SKILL_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands"
SKILL_FILE="$SKILL_DIR/session-continuity.md"
case "$OS" in
  macos) CLAUDE_DESKTOP="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
  *)     CLAUDE_DESKTOP="$HOME/.config/Claude/claude_desktop_config.json" ;;
esac
OLLAMA_SVC="$HOME/.config/systemd/user/ollama.service"
OLLAMA_PLIST="$HOME/Library/LaunchAgents/com.ollama.serve.plist"
MCPVAULT_PKG="@bitbonsai/mcpvault"
RC_BASH="$HOME/.bashrc"
RC_ZSH="$HOME/.zshrc"
RC_MARK_START="# >>> ai-memory hermes launcher >>>"
TMP_DIR="${TMPDIR:-/tmp}"; TMP_DIR="${TMP_DIR%/}"
TMP_LOG="$TMP_DIR/ai-memory-setup-$(id -u).log"
TMP_CKPT="$TMP_DIR/ai-memory-checkpoints-$(id -u)"
SCAN_REPORT="$VAULT/ai-scan-report.md"

# ── HARD RULE: never under any circumstances touch ~/.paperclip ──────────────
PAPERCLIP="$HOME/.paperclip"

# ── Predicates — ONE place that decides what exists (plan and act share these)─
vault_ok() {  # treat as OUR vault only if it carries our markers
  [[ -d "$VAULT/entities" ]] && { [[ -d "$VAULT/.tools" ]] || [[ -f "$VAULT/AGENTS.md" ]]; }
}
hermes_present()    { [[ -d "$HERMES_HOME" ]]; }
mcpvault_present()  { command -v npm &>/dev/null && npm ls -g --depth=0 "$MCPVAULT_PKG" &>/dev/null; }
ollama_svc_present(){ [[ -f "$OLLAMA_SVC" ]] && grep -q "Ollama AI Model Server" "$OLLAMA_SVC" 2>/dev/null; }
ollama_plist_present(){ [[ -f "$OLLAMA_PLIST" ]]; }
skill_present()     { [[ -f "$SKILL_FILE" ]]; }
rc_block_present()  { [[ -f "$1" ]] && grep -qF "$RC_MARK_START" "$1" 2>/dev/null; }
claude_entry_present(){ [[ -f "$CLAUDE_DESKTOP" ]] && grep -q "obsidian-vault" "$CLAUDE_DESKTOP" 2>/dev/null; }
tmp_present()       { [[ -f "$TMP_LOG" ]] || [[ -d "$TMP_CKPT" ]] || ls "$TMP_DIR"/ai-memory-setup.*.log &>/dev/null; }
scan_report_present(){ [[ -f "$SCAN_REPORT" ]]; }

# pretty present/absent line for the plan
plan_line() {  # plan_line present|absent "label" "detail"
  if [[ "$1" == present ]]; then
    echo -e "    ${GREEN}✓${NC}  $2${3:+   ${DIM}$3${NC}}"
  else
    echo -e "    ${DIM}·  $2   (not found — already gone)${NC}"
  fi
}
yn() { if "$@"; then echo present; else echo absent; fi; }

# ═════════════════════════════════════════════════════════════════════════════
# BANNER
# ═════════════════════════════════════════════════════════════════════════════
blank
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   AI Memory Stack  v1.1 — Uninstall      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
blank
info "Vault:  $VAULT"
if $DRY_RUN; then
  echo -e "  ${BOLD}${CYAN}Mode:   DRY-RUN — preview only, nothing will be changed${NC}"
elif $EXPORT_ONLY; then
  echo -e "  ${BOLD}Mode:   EXPORT-ONLY — back up the vault, remove nothing${NC}"
else
  echo -e "  ${BOLD}${YELLOW}Mode:   LIVE — will export, then remove${NC}"
fi
blank

# ═════════════════════════════════════════════════════════════════════════════
# EXPORT TARGET (computed once, used by plan + the real export)
# ═════════════════════════════════════════════════════════════════════════════
EXPORT_DIR="$HOME"; [[ -d "$HOME/Downloads" ]] && EXPORT_DIR="$HOME/Downloads"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ARCHIVE="$EXPORT_DIR/ai-memory-export-$STAMP.tar.gz"

vault_size() {  # human-readable size of the vault, best-effort
  du -sh "$VAULT" 2>/dev/null | awk '{print $1}' || echo "?"
}

# Migration manifest (§4.12): a tiny, secret-free record placed at the archive
# root so a future `setup --restore` knows what it's looking at and what was
# DELIBERATELY left out (config is hardware-specific; keys never travel).
MANIFEST_NAME="ai-memory-export-manifest.json"
build_manifest() {  # build_manifest <out-path> ; 0 on success, 1 if no python3
  command -v python3 &>/dev/null || return 1
  python3 - "$1" "$VAULT" "$OS" "$STAMP" << 'PY'
import sys, json, os, socket, getpass
out, vault, os_name, stamp = sys.argv[1:5]
m = {
  "format": "ai-memory-vault-export",
  "schema_version": 1,
  "created_utc": stamp,
  "source": {"os": os_name, "host": socket.gethostname(), "user": getpass.getuser()},
  "vault_dir": os.path.basename(vault.rstrip("/")),
  "exported_by": "ai-memory-uninstall.sh v1.1",
  "includes": ["vault: markdown memory, notes, imported AI sessions"],
  "excludes": [
    "~/.hermes/config.yaml  (hardware-specific — re-derived by configure on the new machine)",
    "~/.hermes/.env API keys (secrets never travel in an export — re-enter on the new machine)",
    "Hermes native state.db (agent-private, version-coupled)",
  ],
  "restore_hint": "On the new machine run: bash ai-memory-setup.sh — a future version will offer to restore this archive as your vault.",
}
open(out, "w").write(json.dumps(m, indent=2) + "\n")
PY
}

# ═════════════════════════════════════════════════════════════════════════════
# THE PLAN — read-only, prints exactly what export + removal would do
# ═════════════════════════════════════════════════════════════════════════════
show_plan() {
  hdr "Step 1/3  Export your memory (always first)"
  if ! $DO_EXPORT; then
    warn "Export DISABLED (--no-export) — your imported memory will NOT be backed up."
  elif vault_ok; then
    echo -e "    Vault → portable archive (your data is never destroyed without a copy):"
    echo -e "      ${CYAN}$ARCHIVE${NC}"
    echo -e "      ${DIM}source: $VAULT  (~$(vault_size) of markdown + notes)${NC}"
    echo -e "      ${DIM}+ a small migration manifest (no secrets) so a new machine can restore it${NC}"
  else
    plan_line absent "vault at $VAULT — nothing to export"
  fi

  hdr "Step 2/3  Remove the AI Memory stack (core)"
  echo -e "  ${BOLD}Would remove — created by setup / configure / ingest:${NC}"
  plan_line "$(yn claude_entry_present)" "Claude Desktop MCP entry" "obsidian-vault (surgical; backup saved first)"
  plan_line "$(yn mcpvault_present)"     "mcpvault (npm global)"    "$MCPVAULT_PKG"
  if [[ "$OS" == "macos" ]]; then
    plan_line "$(yn ollama_plist_present)" "Ollama autostart agent" "$OLLAMA_PLIST"
  else
    plan_line "$(yn ollama_svc_present)"   "Ollama autostart service" "${OLLAMA_SVC/#$HOME/~}"
  fi
  plan_line "$(yn skill_present)"        "Session Continuity skill" "${SKILL_FILE/#$HOME/~}"
  plan_line "$(yn 'rc_block_present' "$RC_BASH")" "shell launcher block" "${RC_BASH/#$HOME/~} (between our markers)"
  rc_block_present "$RC_ZSH" && plan_line present "shell launcher block" "${RC_ZSH/#$HOME/~} (between our markers)"
  plan_line "$(yn tmp_present)"          "temp logs + checkpoints"  "${TMP_DIR}/ai-memory-*"
  plan_line "$(yn scan_report_present)"  "scan report"              "${SCAN_REPORT/#$HOME/~} (inside vault)"
  plan_line "$(yn hermes_present)"       "Hermes Agent home"        "${HERMES_HOME/#$HOME/~}  (config + keys + Hermes' own memory)"
  if vault_ok; then
    plan_line present "vault tree"  "$VAULT  ${YELLOW}(removed LAST, only after a verified export)${NC}"
  else
    plan_line absent  "vault tree"  ""
  fi

  blank
  echo -e "  ${BOLD}Kept — shared tools, never removed silently:${NC}"
  echo -e "    ${DIM}•  Node.js + npm prefix (~/.npm-global)   other tools may rely on it${NC}"
  if $REMOVE_OLLAMA; then
    echo -e "    ${YELLOW}•  Ollama models — WILL be removed (--remove-ollama):${NC}"
    ollama list 2>/dev/null | awk 'NR>1{print "       - "$1"  ("$3" "$4")"}' || echo -e "       ${DIM}(ollama not responding)${NC}"
  else
    echo -e "    ${DIM}•  Ollama runtime + models   kept; opt in with --remove-ollama${NC}"
  fi
  echo -e "    ${DIM}•  remote.sh changes (sshd/WireGuard/linger/RustDesk)   see --remote below${NC}"

  blank
  echo -e "  ${DIM}Never touched: ~/.paperclip, and anything we did not create.${NC}"

  if $DO_REMOTE; then
    blank
    warn "--remote: reversing remote-access changes is INCREMENT 2 and is not built yet."
    echo -e "  ${DIM}sshd hardening, WireGuard wg0, linger, sleep-mask and RustDesk are left"
    echo -e "  in place. Reverse them by hand for now; a future version will automate it.${NC}"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# EXPORT — real (export-first; never destroy memory without a copy)
# ═════════════════════════════════════════════════════════════════════════════
do_export() {
  if ! $DO_EXPORT; then
    warn "Skipping export (--no-export)."
    return 0
  fi
  if ! vault_ok; then
    info "No vault to export at $VAULT — skipping export."
    return 0
  fi
  hdr "Exporting your memory"
  info "Archiving the vault — this is your safety copy."
  local stage; stage="$(mktemp -d 2>/dev/null || echo '')"
  local extra=()
  if [[ -n "$stage" ]] && build_manifest "$stage/$MANIFEST_NAME"; then
    extra=(-C "$stage" "$MANIFEST_NAME")
  else
    warn "Skipping migration manifest (python3 unavailable) — vault still exported."
  fi
  if tar -czf "$ARCHIVE" ${extra[@]+"${extra[@]}"} \
        -C "$(dirname "$VAULT")" "$(basename "$VAULT")" 2>/dev/null \
       && [[ -s "$ARCHIVE" ]]; then
    ok "Exported → $ARCHIVE  ($(du -h "$ARCHIVE" 2>/dev/null | awk '{print $1}'))"
    [[ ${#extra[@]} -gt 0 ]] && info "Included migration manifest ($MANIFEST_NAME) — contains no secrets."
    EXPORT_OK=true
  else
    rm -f "$ARCHIVE" 2>/dev/null || true
    [[ -n "$stage" ]] && rm -rf "$stage" 2>/dev/null || true
    die "Export FAILED — refusing to remove anything. Your vault is untouched.\n  Free up space or check permissions, then re-run."
  fi
  [[ -n "$stage" ]] && rm -rf "$stage" 2>/dev/null || true
}

# ═════════════════════════════════════════════════════════════════════════════
# REMOVAL — real (each step is idempotent and guarded by a marker/predicate)
# ═════════════════════════════════════════════════════════════════════════════
remove_claude_entry() {
  claude_entry_present || { return 0; }
  command -v python3 &>/dev/null || { warn "python3 not found — leaving $CLAUDE_DESKTOP untouched"; return 0; }
  cp "$CLAUDE_DESKTOP" "$CLAUDE_DESKTOP.bak.$STAMP" 2>/dev/null || true
  python3 - "$CLAUDE_DESKTOP" "$VAULT" << 'PY' && ok "Removed Claude Desktop MCP entry (backup saved)"
import sys, json
p, vault = sys.argv[1], sys.argv[2]
try:
    cfg = json.load(open(p))
except Exception:
    sys.exit(0)
servers = cfg.get("mcpServers", {})
# remove only the entry WE added (its args reference this vault path)
for name in list(servers.keys()):
    s = servers[name]
    args = s.get("args", []) if isinstance(s, dict) else []
    if name == "obsidian-vault" and any(vault in str(a) for a in args):
        servers.pop(name, None)
json.dump(cfg, open(p, "w"), indent=2)
PY
}
remove_mcpvault() {
  mcpvault_present || return 0
  npm rm -g "$MCPVAULT_PKG" --silent &>/dev/null && ok "Removed mcpvault (npm global)" \
    || warn "Could not remove mcpvault — try: npm rm -g $MCPVAULT_PKG"
}
remove_ollama_autostart() {
  if [[ "$OS" == "macos" ]]; then
    ollama_plist_present || return 0
    launchctl unload "$OLLAMA_PLIST" 2>/dev/null || true
    rm -f "$OLLAMA_PLIST" && ok "Removed Ollama launchd agent"
  else
    ollama_svc_present || return 0
    systemctl --user disable --now ollama 2>/dev/null || true
    rm -f "$OLLAMA_SVC"
    systemctl --user daemon-reload 2>/dev/null || true
    ok "Removed Ollama autostart service (the Ollama runtime itself is kept)"
  fi
}
remove_skill() {
  skill_present || return 0
  rm -f "$SKILL_FILE" && ok "Removed Session Continuity skill"
}
remove_rc_block() {  # strip only the block between our markers
  local rc="$1"
  rc_block_present "$rc" || return 0
  command -v python3 &>/dev/null || { warn "python3 not found — leave the launcher in ${rc/#$HOME/~} manually"; return 0; }
  python3 - "$rc" << 'PY' && ok "Removed shell launcher from ${rc/#$HOME/~}"
import sys, re
rc = sys.argv[1]
start = "# >>> ai-memory hermes launcher >>>"
end   = "# <<< ai-memory hermes launcher <<<"
text  = open(rc).read()
text  = re.sub(re.escape(start) + r".*?" + re.escape(end) + r"\n?", "", text, flags=re.S)
text  = re.sub(r"\n{3,}", "\n\n", text)
open(rc, "w").write(text)
PY
}
remove_tmp() {
  tmp_present || return 0
  rm -f "$TMP_LOG" 2>/dev/null || true
  rm -rf "$TMP_CKPT" 2>/dev/null || true
  rm -f "$TMP_DIR"/ai-memory-setup.*.log 2>/dev/null || true
  ok "Removed temp logs + checkpoints"
}
remove_hermes() {
  hermes_present || return 0
  # Guard: must be exactly ~/.hermes, never a symlink pointing elsewhere, never paperclip
  [[ "$HERMES_HOME" == "$HOME/.hermes" && ! -L "$HERMES_HOME" ]] \
    || { warn "Skipping $HERMES_HOME — not the expected ~/.hermes path"; return 0; }
  rm -rf "$HERMES_HOME" && ok "Removed Hermes home (~/.hermes — config, keys, native memory)"
}
remove_ollama_models() {
  $REMOVE_OLLAMA || return 0
  command -v ollama &>/dev/null && ollama list &>/dev/null 2>&1 || { warn "Ollama not responding — skipping model removal"; return 0; }
  hdr "Removing Ollama models (--remove-ollama)"
  local m
  for m in $(ollama list 2>/dev/null | awk 'NR>1{print $1}'); do
    ollama rm "$m" &>/dev/null && ok "Removed model $m" || warn "Could not remove model $m"
  done
  info "The Ollama runtime/binary itself is left in place (shared tool)."
  info "To remove Ollama entirely, see: https://github.com/ollama/ollama#uninstall"
}
remove_vault() {
  vault_ok || return 0
  # Vault is removed LAST and ONLY when its data is safe.
  if ! $DO_EXPORT; then
    : # --no-export path already required a loud confirm up front
  elif [[ "${EXPORT_OK:-false}" != true ]]; then
    warn "No verified export — keeping the vault at $VAULT (your memory stays put)."
    return 0
  fi
  # Guard: never delete $HOME itself or a path we don't recognise as our vault
  [[ "$VAULT" != "$HOME" && "$VAULT" != "/" && "$VAULT" != "$PAPERCLIP"* ]] \
    || die "Refusing to remove $VAULT — unsafe path."
  rm -rf "$VAULT" && ok "Removed vault tree ($VAULT) — your export is at $ARCHIVE"
}

do_remove() {
  hdr "Removing the AI Memory stack"
  remove_claude_entry
  remove_mcpvault
  remove_ollama_autostart
  remove_skill
  remove_rc_block "$RC_BASH"
  remove_rc_block "$RC_ZSH"
  remove_tmp
  remove_ollama_models
  remove_hermes
  remove_vault   # always last
}

# ═════════════════════════════════════════════════════════════════════════════
# DRIVER
# ═════════════════════════════════════════════════════════════════════════════
show_plan

# ── DRY-RUN: never changes anything; tell the user the exact command to act ───
if $DRY_RUN; then
  # If we can prompt, offer to proceed right here.
  if $CAN_PROMPT; then
    blank
    echo -e "${BOLD}Proceed for real now — export, then remove? [y/N]${NC}"
    read -r _go < /dev/tty || _go=""
    if [[ "$(lc "${_go:-n}")" == "y" ]]; then
      DRY_RUN=false
    fi
  fi
fi

if $DRY_RUN; then
  hdr "Step 3/3  Dry-run — nothing was changed"
  echo -e "  Your stack is exactly as it was. To actually export + remove, run:"
  blank
  echo -e "${GREEN}${BOLD}▶ NEXT — export your vault, then remove the stack:${NC}"
  echo -e "     ${CYAN}${BOLD}bash $0 --yes${NC}"
  echo -e "  ${DIM}(add --remove-ollama to also delete downloaded models;"
  echo -e "   add --export-only to make just the backup archive)${NC}"
  blank
  exit 0
fi

# ── REAL run — confirm (unless --yes), with extra ceremony for --no-export ────
if ! $ASSUME_YES; then
  blank
  if ! $DO_EXPORT && ! $EXPORT_ONLY; then
    echo -e "${RED}${BOLD}  --no-export: your imported memory will NOT be backed up.${NC}"
    echo -e "${BOLD}  Type 'DELETE' to remove the stack WITHOUT a backup:${NC}"
    read -r _c < /dev/tty || _c=""
    [[ "$_c" == "DELETE" ]] || die "Aborted — nothing was changed."
  else
    echo -e "${BOLD}This will export your vault, then remove the stack. Type 'y' to continue:${NC}"
    read -r _c < /dev/tty || _c=""
    [[ "$(lc "${_c:-n}")" == "y" ]] || die "Aborted — nothing was changed."
  fi
fi

EXPORT_OK=false
do_export

if $EXPORT_ONLY; then
  blank
  echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}  ✓  Export complete — nothing removed    ${NC}"
  echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
  blank
  echo -e "  Backup: ${CYAN}$ARCHIVE${NC}"
  blank
  exit 0
fi

do_remove

blank
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✓  AI Memory stack removed              ${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
blank
$DO_EXPORT && echo -e "  Your memory is safe in: ${CYAN}$ARCHIVE${NC}"
echo -e "  ${DIM}Kept: Node.js, npm prefix$($REMOVE_OLLAMA || echo ", Ollama + models").${NC}"
blank
# ── §B4: the LAST thing on screen is the literal next command ────────────────
echo -e "${GREEN}${BOLD}▶ NEXT — reinstall any time from a fresh start:${NC}"
echo -e "     ${CYAN}${BOLD}bash ai-memory-setup.sh${NC}"
blank
