#!/usr/bin/env bash
# =============================================================================
#  ai-memory-setup.sh  v8.11
#  AI Memory Stack — works on a brand new machine
#
#  Installs automatically:
#    Homebrew · Xcode CLI Tools · Node.js 22 · npm · git · python3
#    curl · Ollama · mcpvault · Hermes Agent
#    MCP config for Claude Desktop + Claude Code
#    Session Continuity skill
#
#  Safe to re-run — fully idempotent via step checkpoints
#  Language: English
#  Platforms: macOS · Linux (apt/dnf/pacman)
#             Windows → instructions shown on run
#
#  Usage:  bash ai-memory-setup.sh [path/to/vault]
#
# -----------------------------------------------------------------------------
#  ESTIMATED INSTALL TIME (fresh machine, 100 Mbit connection)
#
#  Mac Mini M4 Pro (48 GB)          ~15–20 min
#  Mac Mini M1/M2 (8–16 GB)         ~18–25 min
#  MacBook Pro Intel                 ~25–35 min
#  Ubuntu 24 / Debian (modern PC)   ~12–18 min
#  Ubuntu on Raspberry Pi 4          ~35–50 min
#  Fedora / RHEL                    ~15–20 min
#
#  Re-run (already installed):       ~1–2 min   (all steps skipped)
#  Slow internet (< 20 Mbit):        add 10–20 min to all estimates
#
#  Time breakdown (fresh macOS):
#    Xcode CLI Tools    5–8 min   (Apple download, manual dialog)
#    Homebrew           2–3 min
#    Node.js            1–2 min
#    Ollama             1–2 min
#    nomic-embed-text   1–2 min   (274 MB model download)
#    Hermes Agent       3–5 min   (clone + npm install)
#    Everything else    < 1 min
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

VERSION="8.9"

# ── --help / --version (before anything else) ────────────────────────────────
case "${1:-}" in
  -h|--help)
    cat << 'HELP'
ai-memory-setup.sh — AI Memory Stack installer

Usage:
  bash ai-memory-setup.sh [path/to/vault] [flags]

Flags:
  --no-hermes      skip the Hermes Agent install (vault+ingest still work)
  --hermes         install Hermes without asking
  --autostart      start Ollama at login without asking
  --no-autostart   never install Ollama as a login service
  --yes, -y        assume yes on all prompts (non-interactive)
  --help/--version

Installs: Node.js 22, git, python3, Ollama, mcpvault, Hermes Agent,
MCP config for Claude Desktop/Code, and an Obsidian vault structure.

Safe to re-run — completed steps are skipped.
Do NOT run with sudo. See header of this file for time estimates.
HELP
    exit 0 ;;
  -V|--version)
    echo "ai-memory-setup.sh v8.11"; exit 0 ;;
esac

# ── TTY detection (must happen BEFORE log redirect) ──────────────────────────
IS_TTY=false
[[ -t 1 ]] && IS_TTY=true
CAN_PROMPT=false
# Probe by actually OPENING /dev/tty: the node exists with rw mode even when there
# is no controlling terminal, so `[[ -r/-w ]]` is a false positive (open ENXIOs).
{ : >/dev/tty; } 2>/dev/null && CAN_PROMPT=true

# ── Colors (only when stdout is a terminal) ───────────────────────────────────
if $IS_TTY; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

# ── Portable helpers (bash 3.2 compatible — macOS ships 3.2) ─────────────────
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# timeout is GNU coreutils — NOT available on stock macOS
run_timeout() {
  local secs="$1"; shift
  if command -v timeout &>/dev/null;  then timeout  "$secs" "$@"
  elif command -v gtimeout &>/dev/null; then gtimeout "$secs" "$@"
  else perl -e 'alarm shift; exec @ARGV' "$secs" "$@"   # perl ships with macOS
  fi
}

TMP_DIR="${TMPDIR:-/tmp}"
TMP_DIR="${TMP_DIR%/}"

ok()    { echo -e "${GREEN}✓${NC}  $*"; }
info()  { echo -e "${CYAN}→${NC}  $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
die()   { echo -e "\n${RED}${BOLD}✗  ERROR: $*${NC}\n" >&2; exit 1; }
hdr()   { echo -e "\n${BOLD}── $* ──${NC}"; }
skip()  { echo -e "${DIM}↷  $* (already done)${NC}"; }
blank() { echo ""; }
# calm() — §2.9 reassurance printed BEFORE a slow step so a trusting user does
# not Ctrl+C mid-download (calm IS stability). $1 = one line on what/why.
# Pairs with the interrupt trap, which makes the same promise after the fact.
calm() {
  [[ -n "${1:-}" ]] && echo -e "  ${DIM}$1${NC}"
  echo -e "  ${DIM}Safe to Ctrl+C — re-running resumes where it stopped.${NC}"
  [[ -n "${LOG_FILE:-}" && "${LOG_FILE:-}" != "/dev/null" ]] \
    && echo -e "  ${DIM}Watch it live in another terminal:  tail -f $LOG_FILE${NC}"
  return 0
}

# ── Absolute script directory ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

# ── Vault path ────────────────────────────────────────────────────────────────
INSTALL_HERMES="ask"; AUTOSTART="ask"; ASSUME_YES=false
HERMES_SKIPPED=false
VAULT=""
for arg in "$@"; do
  case "$arg" in
    --no-hermes)    INSTALL_HERMES="no" ;;
    --hermes)       INSTALL_HERMES="yes" ;;
    --autostart)    AUTOSTART="yes" ;;
    --no-autostart) AUTOSTART="no" ;;
    --yes|-y)       ASSUME_YES=true ;;
    -*)             echo "Unknown flag: $arg (see --help)" >&2; exit 1 ;;
    *)              [[ -z "$VAULT" ]] && VAULT="$arg" ;;
  esac
done
VAULT="${VAULT:-$HOME/Documents/ai-memory}"
# Resolve path — fallback for systems without realpath -m
if command -v realpath &>/dev/null; then
  VAULT="$(realpath -m "$VAULT" 2>/dev/null || echo "$VAULT")"
fi
# Make absolute if relative
[[ "$VAULT" != /* ]] && VAULT="$PWD/$VAULT"

TOOLS="$VAULT/.tools"
MCP_DIR="$VAULT/.mcp"
CHECKPOINT_DIR="$VAULT/.tools/.checkpoints"
SKILL_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands"
# Log goes to /tmp until vault exists, then moves
LOG_FILE="$TMP_DIR/ai-memory-setup-$(id -u).log"   # per-user: avoid a stale root-owned file in a shared TMPDIR

# ── OS detection ──────────────────────────────────────────────────────────────
OS="linux"
[[ "$OSTYPE" == "darwin"* ]] && OS="macos"
[[ "$OSTYPE" == "msys"* || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin"* ]] && OS="windows"

PKG_MANAGER="none"
if [[ "$OS" == "linux" ]]; then
  command -v apt-get &>/dev/null && PKG_MANAGER="apt"
  command -v dnf     &>/dev/null && PKG_MANAGER="dnf"
  command -v pacman  &>/dev/null && PKG_MANAGER="pacman"
fi

# ── Stay awake during install (no permanent power changes) ───────────────────
if [[ -z "${AIMS_STAY_AWAKE:-}" ]]; then
  export AIMS_STAY_AWAKE=1
  if [[ "$OS" == "macos" ]] && command -v caffeinate &>/dev/null; then
    # dies automatically when this script's PID exits
    caffeinate -ims -w $$ 2>/dev/null &
  elif command -v systemd-inhibit &>/dev/null \
       && systemd-inhibit --what=sleep:idle --who=probe --why=probe true 2>/dev/null; then
    exec systemd-inhibit --what=sleep:idle \
      --why="AI Memory Stack installation" --who="ai-memory-setup" \
      bash "$SCRIPT_PATH" "$@"
  fi
fi

# ── Claude Desktop config path ────────────────────────────────────────────────
case "$OS" in
  macos)   CLAUDE_DESKTOP="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
  linux)   CLAUDE_DESKTOP="$HOME/.config/Claude/claude_desktop_config.json" ;;
  windows) CLAUDE_DESKTOP="" ;;
esac

# ── Error tracking ────────────────────────────────────────────────────────────
ERRORS=0
err() { echo -e "${RED}✗${NC}  $*" >&2; ERRORS=$(( ERRORS + 1 )); }

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING — writes to /tmp first, switches to vault once vault exists
# ─────────────────────────────────────────────────────────────────────────────
start_logging() {
  # Spinner writes to /dev/tty directly, bypassing tee — so spinner is clean.
  # If the chosen log path isn't writable (e.g. a stale root-owned file left in
  # a shared TMPDIR), fall back to a private temp file so logging never aborts.
  if ! ( : >> "$LOG_FILE" ) 2>/dev/null; then
    LOG_FILE="$(mktemp "${TMP_DIR}/ai-memory-setup.XXXXXX.log" 2>/dev/null)" || LOG_FILE="/dev/null"
  fi
  exec > >(tee -a "$LOG_FILE") 2>&1
}

relocate_log() {
  # Called after vault directory is confirmed to exist
  local vault_log="$VAULT/.tools/setup.log"
  if [[ "$LOG_FILE" != "$vault_log" ]]; then
    cat "$LOG_FILE" >> "$vault_log" 2>/dev/null || true
    LOG_FILE="$vault_log"
  fi
}

start_logging

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP TRAP
# ─────────────────────────────────────────────────────────────────────────────
CLEANUP_PIDS=()
SUDO_KEEPALIVE_PID=""

cleanup() {
  local exit_code=$?
  stop_spinner 2>/dev/null || true

  # Kill spinner and other background processes (NOT sudo keepalive — let it die naturally)
  for pid in ${CLEANUP_PIDS[@]+"${CLEANUP_PIDS[@]}"}; do
    kill "$pid" 2>/dev/null || true
  done

  # Remove incomplete checkpoint markers
  if [[ -d "$CHECKPOINT_DIR" ]]; then
    rm -f "$CHECKPOINT_DIR"/*.incomplete 2>/dev/null || true
  fi

  if [[ $exit_code -ne 0 ]] && [[ $exit_code -ne 130 ]]; then
    blank
    echo -e "${RED}Setup interrupted (exit $exit_code).${NC}"
    echo -e "Safe to re-run — it continues from where it stopped:"
    echo -e "  ${CYAN}bash $SCRIPT_PATH $VAULT${NC}"
    blank
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ─────────────────────────────────────────────────────────────────────────────
# PROGRESS SPINNER — writes to /dev/tty, bypasses tee log
# ─────────────────────────────────────────────────────────────────────────────
spinner_pid=""
start_spinner() {
  local msg="${1:-Working...}"
  local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
  # Write to /dev/tty so it doesn't pollute the log file
  (
    i=0
    while true; do
      printf "\r${CYAN}%s${NC}  %s " "${chars:$((i % ${#chars})):1}" "$msg" > /dev/tty 2>/dev/null || printf "\r%s  %s " "${chars:$((i % ${#chars})):1}" "$msg"
      sleep 0.1
      i=$(( i + 1 ))
    done
  ) &
  spinner_pid=$!
  CLEANUP_PIDS+=("$spinner_pid")
}

stop_spinner() {
  if [[ -n "$spinner_pid" ]]; then
    kill "$spinner_pid" 2>/dev/null || true
    wait "$spinner_pid" 2>/dev/null || true
    spinner_pid=""
    printf "\r\033[K" > /dev/tty 2>/dev/null || printf "\r\033[K"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CHECKPOINT HELPERS
# ─────────────────────────────────────────────────────────────────────────────
# (CHECKPOINT_DIR created after vault in step 1 — pre-create in /tmp for step 0)
PRE_CHECKPOINT_DIR="$TMP_DIR/ai-memory-checkpoints-$(id -u)"
mkdir -p "$PRE_CHECKPOINT_DIR" 2>/dev/null || true

step_done() {
  [[ -f "$CHECKPOINT_DIR/step-$1.ok" ]] || \
  [[ -f "$PRE_CHECKPOINT_DIR/step-$1.ok" ]]
}

step_complete() {
  local dir="$CHECKPOINT_DIR"
  [[ -d "$dir" ]] || dir="$PRE_CHECKPOINT_DIR"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$dir/step-$1.ok"
}

step_start() {
  local dir="$CHECKPOINT_DIR"
  [[ -d "$dir" ]] || dir="$PRE_CHECKPOINT_DIR"
  touch "$dir/step-$1.incomplete"
}

step_end() {
  rm -f "$CHECKPOINT_DIR/step-$1.incomplete" \
        "$PRE_CHECKPOINT_DIR/step-$1.incomplete" 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────────
# HUMAN-IN-THE-LOOP CHECKPOINT
# ─────────────────────────────────────────────────────────────────────────────
checkpoint() {
  local id="$1" title="$2" instructions="$3" verify_cmd="$4"

  local ck_file_vault="$CHECKPOINT_DIR/checkpoint-$id.ok"
  local ck_file_tmp="$PRE_CHECKPOINT_DIR/checkpoint-$id.ok"

  if [[ -f "$ck_file_vault" ]] || [[ -f "$ck_file_tmp" ]]; then
    skip "Checkpoint: $title"; return 0
  fi

  # Non-interactive session (CI, cron, piped) — cannot prompt; skip with warning
  if ! $CAN_PROMPT; then
    warn "Non-interactive session — skipping checkpoint: $title"
    warn "Complete this manually, then re-run the script."
    return 0
  fi

  if eval "$verify_cmd" &>/dev/null 2>&1; then
    touch "$ck_file_tmp"
    skip "Checkpoint: $title"
    return 0
  fi

  local attempts=0
  while true; do
    attempts=$(( attempts + 1 ))
    blank
    echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}${BOLD}║  ACTION REQUIRED: $title${NC}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
    blank
    echo -e "$instructions"
    blank
    echo -e "${BOLD}Press ENTER when done${NC} (or type 'skip' to skip):"
    read -r response < /dev/tty || response=""

    [[ "$(lc "$response")" == "skip" ]] && {
      warn "Skipped: $title — may cause issues later"
      return 0
    }

    if eval "$verify_cmd" &>/dev/null 2>&1; then
      touch "$ck_file_tmp"
      ok "Confirmed: $title"
      return 0
    fi

    blank
    echo -e "${RED}✗  Not detected yet — $title${NC}"
    if [[ $attempts -ge 3 ]]; then
      warn "Still not working after $attempts attempts."
      echo "Type 'skip' to continue anyway, or ENTER to retry:"
      read -r response < /dev/tty || response=""
      [[ "$(lc "$response")" == "skip" ]] && return 0
    else
      echo "Press ENTER to try again, or type 'skip':"
      read -r response < /dev/tty || response=""
      [[ "$(lc "$response")" == "skip" ]] && return 0
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# DISK SPACE CHECK
# ─────────────────────────────────────────────────────────────────────────────
check_disk_space() {
  local required_gb="${1:-10}" path="${2:-$HOME}"
  local free_gb
  free_gb=$(python3 -c \
    "import shutil; s=shutil.disk_usage('$path'); print(round(s.free/1e9,1))" \
    2>/dev/null || echo "0")
  python3 -c "exit(0 if float('$free_gb') >= $required_gb else 1)" 2>/dev/null \
    || die "Not enough disk space. Need ${required_gb} GB free, have ${free_gb} GB.\nFree up space and re-run."
}

# ─────────────────────────────────────────────────────────────────────────────
# SAFE JSON MERGE — validates before touching
# ─────────────────────────────────────────────────────────────────────────────
safe_json_merge() {
  local target="$1" new_servers_json="$2"

  if [[ -f "$target" ]]; then
    if ! python3 -c \
        "import json,sys; json.load(open(sys.argv[1]))" "$target" 2>/dev/null; then
      warn "Existing config at $target has JSON syntax errors — skipping merge"
      warn "Fix manually: $target"
      return 1
    fi
    local bak="${target}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    cp "$target" "$bak"
    ok "Backup: $(basename "$bak")"
  fi

  python3 - "$target" "$new_servers_json" << 'PYMERGE'
import sys, json
from pathlib import Path
target_path  = sys.argv[1]
new_servers  = json.loads(sys.argv[2])
if Path(target_path).exists():
    with open(target_path) as f:
        config = json.load(f)
else:
    config = {}
config.setdefault("mcpServers", {}).update(new_servers)
Path(target_path).parent.mkdir(parents=True, exist_ok=True)
with open(target_path, "w") as f:
    json.dump(config, f, indent=2)
PYMERGE
}

# ─────────────────────────────────────────────────────────────────────────────
# write_once — only create if file doesn't exist
# ─────────────────────────────────────────────────────────────────────────────
write_once() {
  local path="$1"; shift
  if [[ ! -f "$path" ]]; then
    mkdir -p "$(dirname "$path")"
    cat > "$path"
    ok "Created $(basename "$path")"
  else
    skip "$(basename "$path")"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# WINDOWS — early exit
# ═════════════════════════════════════════════════════════════════════════════
if [[ "$OS" == "windows" ]]; then
  blank
  echo -e "${YELLOW}${BOLD}  Windows detected${NC}"
  blank
  echo "  This script requires bash. Choose one of:"
  blank
  echo -e "  ${BOLD}Option 1 — Git Bash (easiest):${NC}"
  echo "    1. Download: https://git-scm.com/download/win"
  echo "    2. Install with default settings"
  echo "    3. Right-click script folder → 'Git Bash Here'"
  echo "    4. Run: bash ai-memory-setup.sh"
  blank
  echo -e "  ${BOLD}Option 2 — WSL2 (recommended for development):${NC}"
  echo "    1. Open PowerShell as Administrator"
  echo "    2. Run: wsl --install"
  echo "    3. Reboot, open Ubuntu, run this script"
  blank
  exit 1
fi

# ═════════════════════════════════════════════════════════════════════════════
# BANNER
# ═════════════════════════════════════════════════════════════════════════════
blank
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   AI Memory Stack  v8.11 — Setup        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
blank
info "Vault:  $VAULT"
info "OS:     $OS${PKG_MANAGER:+ ($PKG_MANAGER)}"
info "Log:    $LOG_FILE"
blank

# ─────────────────────────────────────────────────────────────────────────────
# TIME ESTIMATE
# ─────────────────────────────────────────────────────────────────────────────
show_time_estimate() {
  local est=""
  case "$OS" in
    macos)
      # Detect Apple Silicon vs Intel
      if [[ "$(uname -m)" == "arm64" ]] || \
         sysctl -n hw.optional.arm64 2>/dev/null | grep -q "1"; then
        est="~15–20 min on Apple Silicon (M1/M2/M3/M4)"
      else
        est="~25–35 min on Intel Mac"
      fi
      ;;
    linux)
      case "$PKG_MANAGER" in
        apt)    est="~12–18 min on Ubuntu/Debian" ;;
        dnf)    est="~15–20 min on Fedora/RHEL" ;;
        pacman) est="~12–16 min on Arch/Manjaro" ;;
        *)      est="~15–25 min" ;;
      esac
      ;;
  esac

  # If already partly done, it'll be faster
  local done_count=0
  for n in 1 2 3 4 5 6; do
    step_done "$n" && done_count=$(( done_count + 1 )) || true
  done

  if [[ $done_count -gt 0 ]]; then
    echo -e "  ${DIM}Estimated time: ~1–3 min (${done_count}/6 steps already done)${NC}"
  else
    echo -e "  ${DIM}Estimated time: $est (fresh install)${NC}"
    echo -e "  ${DIM}Slow internet (< 20 Mbit): add 10–20 min${NC}"
  fi
  blank
}
show_time_estimate

# ─────────────────────────────────────────────────────────────────────────────
# GUARD: do not run as root
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  die "Do not run this script as root or with sudo.\n\n  Just run it as your normal user:\n    bash ai-memory-setup.sh\n\n  The script will ask for your password when needed (Linux only)."
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUDO EXPLANATION + ONE-TIME PROMPT (Linux only)
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$OS" == "linux" ]] && [[ "$PKG_MANAGER" != "none" ]]; then
  # Only acquire sudo if package-install work actually remains. A completed
  # re-run (all steps done) installs nothing, so it must not demand a password
  # — otherwise an idempotent re-run aborts on machines where sudo can't prompt.
  _need_sudo=false
  for n in 1 2 3 4 5 6; do step_done "$n" || _need_sudo=true; done
  if ! $_need_sudo; then
    skip "sudo not needed — all install steps already complete"
    blank
  else
    blank
    echo -e "${BOLD}  About sudo (Linux only)${NC}"
    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  This script runs as YOU, not as root."
    echo "  It needs your password once to install system packages"
    echo "  (Node.js, git, etc.) via $PKG_MANAGER."
    echo "  Everything else — Hermes, vault files, config — goes"
    echo "  into your home folder and never needs sudo."
    blank
    # Accept already-available sudo (cached timestamp or NOPASSWD) without a
    # prompt; only fall back to an interactive prompt when we can actually read
    # one. Fail only when sudo is genuinely unavailable and we need it.
    if sudo -n true 2>/dev/null; then
      ok "sudo access already available (cached or passwordless)"
    elif $CAN_PROMPT; then
      echo "  You will be asked for your password now."
      echo "  It should not be asked again during the rest of the install."
      blank
      sudo -v || die "Password incorrect or sudo not available.\nAsk your system administrator for sudo access."
      ok "sudo access confirmed"
    else
      die "sudo is required to install system packages but no password can be\n  read in this non-interactive session. Re-run in a terminal, or install\n  Node.js/git/Ollama first so no system packages are needed."
    fi
    # Keep sudo alive in background — killed naturally when script exits
    ( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
    SUDO_KEEPALIVE_PID=$!
    blank
  fi
fi

# macOS: no sudo explanation needed — Homebrew/Ollama don't require it
if [[ "$OS" == "macos" ]]; then
  info "macOS: tools install to your home folder. ONE password prompt can"
  info "appear in this terminal: the Homebrew installer asks for your account"
  info "password the first time. That is normal — type it and continue."
  blank
fi

# ─────────────────────────────────────────────────────────────────────────────
# DISK SPACE CHECK
# ─────────────────────────────────────────────────────────────────────────────
check_disk_space 10 "$HOME"
ok "Disk space: sufficient"

# ── Connectivity / proxy probe ────────────────────────────────────────────────
if curl -sI --max-time 8 https://github.com >/dev/null 2>&1; then
  ok "Network: github.com reachable"
else
  warn "Cannot reach github.com."
  if [[ -z "${HTTPS_PROXY:-}${https_proxy:-}" ]]; then
    echo "  If you are behind a corporate proxy, set it and re-run:"
    echo "    export HTTPS_PROXY=http://proxy.example.com:8080"
    echo "    export HTTP_PROXY=\$HTTPS_PROXY"
  fi
  if $CAN_PROMPT && ! $ASSUME_YES; then
    echo -e "${BOLD}Continue anyway? [y/N]${NC}"
    read -r _c < /dev/tty || _c=""
    [[ "$(lc "${_c:-n}")" == "y" ]] || die "Aborted — no network connectivity."
  else
    warn "Continuing without verified connectivity (downloads may fail)"
  fi
fi

# ── macOS folder-permission (TCC) + iCloud checks ────────────────────────────
if [[ "$OS" == "macos" ]]; then
  # iCloud Desktop & Documents sync would silently cloud-sync the vault
  if [[ "$VAULT" == "$HOME/Documents/"* ]] \
     && [[ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents" ]]; then
    warn "Your Documents folder appears to be synced to iCloud (Desktop & Documents)."
    warn "A vault there would be CLOUD-synced — against the point of this stack."
    if $CAN_PROMPT && ! $ASSUME_YES; then
      echo -e "${BOLD}Use ~/ai-memory instead (recommended)? [Y/n]${NC}"
      read -r _ic < /dev/tty || _ic=""
      [[ "$(lc "${_ic:-y}")" != "n" ]] && VAULT="$HOME/ai-memory" \
        && TOOLS="$VAULT/.tools" && MCP_DIR="$VAULT/.mcp" \
        && CHECKPOINT_DIR="$VAULT/.tools/.checkpoints" \
        && info "Vault moved to: $VAULT"
    else
      warn "Non-interactive — keeping $VAULT (consider ~/ai-memory)"
    fi
  fi
  # First touch of ~/Documents or ~/Downloads triggers a TCC popup
  if ! mkdir -p "$VAULT" 2>/dev/null; then
    checkpoint "tcc-folder" \
      "Allow Terminal to access the vault folder" \
      "  macOS showed (or blocked) a folder-access prompt.\n  Fix:\n    ${BOLD}System Settings → Privacy & Security → Files and Folders →\n    Terminal → enable Documents Folder${NC}\n  (If you clicked 'Don't Allow' earlier, this is where to undo it.)" \
      "mkdir -p '$VAULT'"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 0 — SYSTEM REQUIREMENTS
# ═════════════════════════════════════════════════════════════════════════════
hdr "Step 0/7  System requirements"

APT_UPDATED=false
# §4.1 (WSL apt-lock finding): a fresh system runs unattended-upgrades in the
# background and holds the apt/dpkg lock, so a bare `apt-get` fails immediately.
# apt_get() asks apt to WAIT for the lock (DPkg::Lock::Timeout, apt 1.9.11+;
# older apt simply ignores the unknown option) and prints a friendly heads-up
# when the lock is visibly held. All apt calls in this script go through it.
apt_lock_note() {
  [[ "$PKG_MANAGER" == "apt" ]] || return 0
  if { command -v fuser &>/dev/null && sudo fuser /var/lib/dpkg/lock-frontend &>/dev/null; } \
     || pgrep -x unattended-upgr &>/dev/null || pgrep -x apt &>/dev/null \
     || pgrep -x apt-get &>/dev/null || pgrep -x dpkg &>/dev/null; then
    warn "Package manager is busy (background updates / unattended-upgrades)."
    info "Waiting up to 5 min for the apt lock to free — this is normal on a fresh system."
  fi
}
apt_get() {  # sudo apt-get that waits for the lock instead of failing on it
  apt_lock_note
  sudo apt-get -o DPkg::Lock::Timeout=300 "$@"
}
apt_update_once() {
  if [[ "$PKG_MANAGER" == "apt" ]] && ! $APT_UPDATED; then
    start_spinner "apt-get update..."
    apt_get update -qq 2>/dev/null || warn "apt-get update had errors (a stale third-party repo?) — continuing"
    stop_spinner
    APT_UPDATED=true
  fi
}

install_pkg() {
  local binary="$1" brew_pkg="${2:-$1}" apt_pkg="${3:-$1}" \
        dnf_pkg="${4:-$1}" pacman_pkg="${5:-$1}"
  command -v "$binary" &>/dev/null && { skip "$binary"; return 0; }
  info "Installing $binary..."
  case "$OS-$PKG_MANAGER" in
    macos-*)      brew install "$brew_pkg" ;;
    linux-apt)    apt_update_once; apt_get install -y -qq "$apt_pkg" ;;
    linux-dnf)    sudo dnf install -y -q "$dnf_pkg" ;;
    linux-pacman) sudo pacman -S --noconfirm "$pacman_pkg" ;;
    *) die "$binary is missing and cannot be installed automatically.\nInstall manually and re-run." ;;
  esac
  command -v "$binary" &>/dev/null \
    || die "$binary installed but not found in PATH. Open a new terminal and re-run."
  ok "$binary installed"
}

# ── macOS: Homebrew ───────────────────────────────────────────────────────────
if [[ "$OS" == "macos" ]]; then
  if ! command -v brew &>/dev/null; then
    # Trigger installation then checkpoint for the dialog
    /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || true
    # Source into current session
    [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [[ -f /usr/local/bin/brew   ]] && eval "$(/usr/local/bin/brew shellenv)"

    checkpoint "homebrew" \
      "Homebrew installation" \
      "  Homebrew should have just installed above.\n\n  If you saw a password prompt and it completed — you're done.\n  If it failed, run this in a new terminal:\n\n    ${CYAN}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}\n\n  Then come back and press ENTER." \
      "command -v brew"

    command -v brew &>/dev/null \
      || die "Homebrew not found after installation.\nOpen a new terminal and re-run this script."
  else
    skip "Homebrew"
  fi
  # Always source for current session
  [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)" || true
  [[ -f /usr/local/bin/brew   ]] && eval "$(/usr/local/bin/brew shellenv)" || true
fi

# ── Rosetta check (Apple Silicon only) ───────────────────────────────────────
if [[ "$OS" == "macos" ]]; then
  if sysctl -n hw.optional.arm64 2>/dev/null | grep -q "1"; then
    if [[ "$(uname -m)" == "x86_64" ]]; then
      blank
      warn "You are running this terminal in Rosetta (Intel emulation) on Apple Silicon."
      warn "This can cause Homebrew to install to the wrong location."
      blank
      echo "  Fix: open Terminal → right-click → Get Info → uncheck 'Open using Rosetta'"
      echo "  Then open a fresh terminal window and re-run this script."
      blank
      if $CAN_PROMPT; then
        echo "  Press ENTER to continue anyway (not recommended), or Ctrl+C to abort:"
        read -r _ < /dev/tty || _=""
      else
        warn "Non-interactive — continuing despite Rosetta terminal"
      fi
    fi
  fi
fi

# ── macOS: Xcode Command Line Tools ──────────────────────────────────────────
if [[ "$OS" == "macos" ]] && ! xcode-select -p &>/dev/null 2>&1; then
  xcode-select --install 2>/dev/null || true
  checkpoint "xcode-cli" \
    "Install Xcode Command Line Tools" \
    "  macOS has opened (or will open) a dialog:\n\n    ${BOLD}'Install the Xcode Command Line Tools?'${NC}\n\n  Click ${BOLD}Install${NC} and wait for it to complete.\n  This takes ${BOLD}5–8 minutes${NC} — the progress bar in the dialog shows status.\n\n  When the dialog says 'Software installed' — press ENTER here." \
    "xcode-select -p"
elif [[ "$OS" == "macos" ]]; then
  skip "Xcode Command Line Tools"
fi

# ── build-essential (Linux) ───────────────────────────────────────────────────
if [[ "$OS" == "linux" ]]; then
  case "$PKG_MANAGER" in
    apt)
      if ! dpkg -l build-essential &>/dev/null 2>&1; then
        info "Installing build tools..."
        apt_update_once
        apt_get install -y -qq build-essential python3-dev 2>/dev/null
        ok "build-essential installed"
      else
        skip "build-essential"
      fi
      ;;
    dnf)
      if ! rpm -q gcc make &>/dev/null 2>&1; then
        sudo dnf groupinstall -y -q "Development Tools" 2>/dev/null
        ok "Development Tools installed"
      else
        skip "Development Tools"
      fi
      ;;
    pacman)
      if ! pacman -Qi base-devel &>/dev/null 2>&1; then
        sudo pacman -S --noconfirm --needed base-devel 2>/dev/null
        ok "base-devel installed"
      else
        skip "base-devel"
      fi
      ;;
  esac
fi

# ── Core tools ────────────────────────────────────────────────────────────────
install_pkg curl  curl  curl  curl  curl
install_pkg git   git   git   git   git
install_pkg python3 python@3 python3 python3 python
# §4.1: do NOT assume these exist — a clean WSL/Ubuntu has neither. `unzip` for
# unpacking exports; `zstd` is required by the Ollama installer's bundle.
install_pkg unzip unzip unzip unzip unzip
install_pkg zstd  zstd  zstd  zstd  zstd

# ── Node.js ───────────────────────────────────────────────────────────────────
install_node() {
  # Source version managers if present
  [[ -s "$HOME/.nvm/nvm.sh"  ]] && source "$HOME/.nvm/nvm.sh"  2>/dev/null || true
  command -v fnm   &>/dev/null && eval "$(fnm env)"             2>/dev/null || true
  [[ -d "$HOME/.volta"       ]] && export PATH="$HOME/.volta/bin:$PATH"

  if command -v node &>/dev/null; then
    local ver; ver=$(node --version | sed 's/v//' | cut -d. -f1)
    if [[ $ver -ge 18 ]]; then
      skip "Node.js ($(node --version))"; return 0
    fi
    warn "Node.js $(node --version) too old — upgrading to 22..."
  else
    info "Installing Node.js 22..."
  fi

  calm "Installing Node.js 22 (runtime for the agent tools, ~30 MB plus packages)."
  case "$OS" in
    macos)
      brew install node@22
      brew link node@22 --force --overwrite 2>/dev/null || true
      ;;
    linux)
      start_spinner "Setting up NodeSource repository..."
      if [[ "$PKG_MANAGER" == "apt" ]]; then
        curl -fsSL --max-time 60 https://deb.nodesource.com/setup_22.x \
          | sudo -E bash - 2>/dev/null \
          || die "Could not reach NodeSource. Check internet/proxy."
        stop_spinner
        apt_get install -y -qq nodejs
      elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        curl -fsSL --max-time 60 https://rpm.nodesource.com/setup_22.x \
          | sudo bash - 2>/dev/null \
          || die "Could not reach NodeSource. Check internet/proxy."
        stop_spinner
        sudo dnf install -y -q nodejs
      else
        stop_spinner
        die "Cannot install Node.js automatically.\nInstall Node.js 22 manually: https://nodejs.org"
      fi
      ;;
  esac
  command -v node &>/dev/null || die "Node.js installed but not found in PATH."
  ok "Node.js $(node --version) installed"
}
install_node

# ── npm global prefix — no sudo needed ───────────────────────────────────────
NPM_PREFIX="$HOME/.npm-global"
if [[ "$(npm config get prefix 2>/dev/null)" != "$NPM_PREFIX" ]]; then
  mkdir -p "$NPM_PREFIX"
  npm config set prefix "$NPM_PREFIX"
fi
export PATH="$NPM_PREFIX/bin:$PATH"

# ── Ollama ────────────────────────────────────────────────────────────────────
if ! command -v ollama &>/dev/null; then
  info "Installing Ollama..."
  check_disk_space 5 "$HOME"
  calm "Fetching the Ollama runtime (~30 MB). The AI model itself is a separate, larger download you choose later in configure."
  case "$OS" in
    macos)
      brew install ollama 2>/dev/null || \
        { start_spinner "Downloading Ollama..."; \
          curl -fsSL --max-time 120 https://ollama.com/install.sh | sh; \
          stop_spinner; }

      checkpoint "ollama-gatekeeper" \
        "Allow Ollama in macOS Security" \
        "  macOS may show:\n  ${BOLD}'ollama cannot be opened because the developer cannot be verified'${NC}\n\n  Fix:\n    1. Open ${BOLD}System Settings → Privacy & Security${NC}\n    2. Scroll down — find ${BOLD}'ollama was blocked'${NC}\n    3. Click ${BOLD}'Allow Anyway'${NC}\n    4. Run in another terminal: ${CYAN}ollama --version${NC}\n    5. Click ${BOLD}Open${NC} in the next dialog\n\n  If no dialog appeared, Ollama is already allowed — just press ENTER." \
        "ollama --version"
      ;;
    linux)
      start_spinner "Downloading Ollama..."
      curl -fsSL --max-time 120 https://ollama.com/install.sh | sh 2>/dev/null \
        || die "Ollama installation failed. Check internet connection."
      stop_spinner
      ;;
  esac
  command -v ollama &>/dev/null || die "Ollama installed but binary not found in PATH."
  ok "Ollama installed"
else
  skip "Ollama ($(ollama --version 2>/dev/null | head -1 | tr -d '\n'))"
fi

# ── Ollama daemon ─────────────────────────────────────────────────────────────
setup_ollama_daemon() {
  if [[ "$OS" == "macos" ]]; then
    local plist="$HOME/Library/LaunchAgents/com.ollama.serve.plist"
    local ollama_bin; ollama_bin="$(command -v ollama)"
    # Regenerate plist if ollama binary moved (e.g. after brew upgrade)
    if [[ -f "$plist" ]] && ! grep -q "$ollama_bin" "$plist" 2>/dev/null; then
      launchctl unload "$plist" 2>/dev/null || true
      rm -f "$plist"
      info "Ollama path changed — regenerating launchd agent"
    fi
    if [[ ! -f "$plist" ]]; then
      mkdir -p "$HOME/Library/LaunchAgents"
      cat > "$plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key>        <string>com.ollama.serve</string>
  <key>ProgramArguments</key>
  <array><string>$(command -v ollama)</string><string>serve</string></array>
  <key>RunAtLoad</key>    <true/>
  <key>KeepAlive</key>    <true/>
  <key>StandardOutPath</key>  <string>$HOME/.ollama/serve.log</string>
  <key>StandardErrorPath</key><string>$HOME/.ollama/serve.log</string>
</dict></plist>
PLIST
      launchctl load "$plist" 2>/dev/null || true
      ok "Ollama launchd agent installed (auto-starts on login)"

      checkpoint "ollama-firewall" \
        "Allow Ollama network access" \
        "  macOS may show:\n  ${BOLD}'Do you want ollama to accept incoming network connections?'${NC}\n\n  Click ${BOLD}Allow${NC}.\n  If no dialog appeared — it's already allowed. Press ENTER." \
        "ollama list"
    else
      skip "Ollama launchd agent"
      launchctl load "$plist" 2>/dev/null || true
    fi

  elif [[ "$OS" == "linux" ]]; then
    if command -v systemctl &>/dev/null && systemctl --user daemon-reload &>/dev/null 2>&1; then
      local svc="$HOME/.config/systemd/user/ollama.service"
      if [[ ! -f "$svc" ]]; then
        mkdir -p "$(dirname "$svc")"
        cat > "$svc" << SYSTEMD
[Unit]
Description=Ollama AI Model Server
After=network.target

[Service]
ExecStart=$(command -v ollama) serve
Restart=always
RestartSec=3
Environment=HOME=$HOME

[Install]
WantedBy=default.target
SYSTEMD
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable ollama  2>/dev/null || true
        systemctl --user start ollama   2>/dev/null || true
        ok "Ollama systemd user service installed"
      else
        skip "Ollama systemd service"
        systemctl --user start ollama 2>/dev/null || true
      fi
    else
      if ! ollama list &>/dev/null 2>&1; then
        nohup ollama serve >> "$HOME/.ollama/serve.log" 2>&1 &
        sleep 3
      fi
    fi
  fi

  # Wait up to 15s for Ollama to respond
  local i=0
  while ! ollama list &>/dev/null 2>&1 && [[ $i -lt 15 ]]; do
    sleep 1; i=$(( i + 1 ))
  done
  ollama list &>/dev/null 2>&1 \
    && ok "Ollama is running" \
    || warn "Ollama not responding — start manually: ollama serve"
}
if command -v ollama &>/dev/null; then
  mkdir -p "$HOME/.ollama"
  DO_AUTO="$AUTOSTART"
  if [[ "$DO_AUTO" == "ask" ]]; then
    if $ASSUME_YES || ! $CAN_PROMPT; then
      DO_AUTO="yes"
    else
      echo -e "${BOLD}Start Ollama automatically at login? [Y/n]${NC}"
      echo -e "  ${DIM}(background service; uses no RAM until a model is loaded)${NC}"
      read -r _a < /dev/tty || _a=""
      [[ "$(lc "${_a:-y}")" == "n" ]] && DO_AUTO="no" || DO_AUTO="yes"
    fi
  fi
  if [[ "$DO_AUTO" == "yes" ]]; then
    setup_ollama_daemon
  else
    info "Autostart skipped — starting Ollama for this session only"
    if ! ollama list &>/dev/null 2>&1; then
      nohup ollama serve >> "$HOME/.ollama/serve.log" 2>&1 &
      sleep 3
    fi
    ollama list &>/dev/null 2>&1 \
      && ok "Ollama running (this session only)" \
      || warn "Ollama not responding — start manually: ollama serve"
  fi
fi

# ── nomic-embed-text ──────────────────────────────────────────────────────────
if command -v ollama &>/dev/null && ollama list &>/dev/null 2>&1; then
  if ! ollama list 2>/dev/null | grep -q "nomic-embed"; then
    info "Pulling nomic-embed-text (274 MB — needed by Hermes for memory search)..."
    ollama pull nomic-embed-text 2>/dev/null \
      && ok "nomic-embed-text ready" \
      || warn "Could not pull nomic-embed-text — run later: ollama pull nomic-embed-text"
  else
    skip "nomic-embed-text"
  fi
fi

blank
ok "All system requirements satisfied"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — VAULT STRUCTURE
# ═════════════════════════════════════════════════════════════════════════════
if step_done "1"; then
  skip "Step 1/7 — Vault structure"
else
  hdr "Step 1/7  Vault structure"
  step_start "1"

  CREATED=0
  for d in \
    "00-Inbox" "01-Projects" "02-Areas" \
    "03-Resources/AI-Models" "04-Archive" \
    "05-AI-Sessions/claude-web" "05-AI-Sessions/claude-code" \
    "05-AI-Sessions/hermes" "05-AI-Sessions/ollama" \
    "entities" ".tools" ".mcp" ".obsidian" ".tools/.checkpoints"; do
    if [[ ! -d "$VAULT/$d" ]]; then
      mkdir -p "$VAULT/$d"
      CREATED=$(( CREATED + 1 ))
    fi
  done
  [[ $CREATED -gt 0 ]] && ok "$CREATED directories created" || skip "Directory structure"

  # Correct permissions — not world-readable for sensitive dirs
  chmod 700 "$VAULT/.mcp" "$VAULT/.tools" 2>/dev/null || true

  # Network filesystem warning (df -T is GNU-only; skip on macOS)
  if [[ "$OS" == "linux" ]] && df -T "$VAULT" 2>/dev/null | grep -qE "nfs|cifs|smb|fuse"; then
    warn "Vault is on a network filesystem (NFS/SMB)."
    warn "Hermes uses SQLite which may be unstable on network drives."
    warn "Consider moving the vault to a local disk."
  fi

  # Migrate pre-checkpoints to vault
  if [[ -d "$PRE_CHECKPOINT_DIR" ]]; then
    cp "$PRE_CHECKPOINT_DIR"/step-*.ok "$CHECKPOINT_DIR/" 2>/dev/null || true
    cp "$PRE_CHECKPOINT_DIR"/checkpoint-*.ok "$CHECKPOINT_DIR/" 2>/dev/null || true
  fi

  # Relocate log to vault
  mkdir -p "$VAULT/.tools"
  relocate_log

  VAULT_USER="${USER:-$(id -un 2>/dev/null || echo user)}"
  write_once "$VAULT/entities/user.md" << USERMD
# User

## Basic Info
- name: $VAULT_USER
- role:
- location:

## Active Projects
<!-- Add links like: [[entities/my-project.md]] -->

## AI Setup
<!-- Filled in by ai-memory-configure.sh -->

## Notes
USERMD

  write_once "$VAULT/README.md" << 'READMEMD'
# AI Memory Vault

## Commands
```bash
bash .tools/resume.sh              # Resume session (Claude Code)
bash .tools/resume.sh hermes       # Resume with Hermes Agent
bash ai-memory-configure.sh        # Configure models and API keys
bash ai-memory-setup.sh            # Re-run installation (safe)
```

## Structure
- `00-Inbox/`               — Capture everything, sort later
- `01-Projects/`            — Active projects
- `02-Areas/`               — Ongoing responsibilities
- `03-Resources/AI-Models/` — Model inventory and reports
- `04-Archive/`             — Completed work
- `05-AI-Sessions/`         — AI conversation exports + session logs
- `entities/`               — Entity files (Hermes + mem-agent)
READMEMD

  write_once "$VAULT/00-Inbox/AI-INBOX.md" << 'INBOXMD'
# AI Inbox

Add tasks here from any device.
The agent reads and confirms them at the start of the next session.

## Tasks
<!-- - [ ] [date] Your task here -->
INBOXMD

  step_end "1"
  step_complete "1"
fi

# ── Family self-install: permanent home for all scripts ──────────────────────
mkdir -p "$TOOLS"
COPIED=0
for s in "$SCRIPT_DIR"/ai-memory-*.sh; do
  [[ -f "$s" ]] || continue
  dest="$TOOLS/$(basename "$s")"
  if [[ "$s" != "$dest" ]] && ! cmp -s "$s" "$dest" 2>/dev/null; then
    cp "$s" "$dest" && chmod +x "$dest"
    COPIED=$(( COPIED + 1 ))
  fi
done
if [[ $COPIED -gt 0 ]]; then
  ok "Scripts installed to $TOOLS ($COPIED file(s)) — safe to delete the downloads"
else
  skip "Scripts already installed in $TOOLS"
fi

# ── AGENTS.md — the bridge: auto-injected into Hermes' system prompt ─────────
# (written outside the step gate so re-runs on existing installs also get it)
write_once "$VAULT/AGENTS.md" << AGENTSMD
# AI Memory Vault — workspace instructions

You are running inside a personal knowledge vault. Treat it as the user's
long-term, agent-neutral memory.

## Layout
- 00-Inbox/AI-INBOX.md      — tasks left for you; read, confirm, then clear
- 01-Projects/ 02-Areas/    — active work and ongoing responsibilities
- 05-AI-Sessions/           — imported history (claude-web/, claude-code/)
- entities/                 — distilled facts, one markdown file per entity
- entities/user.md          — root profile of the user

## Your routine
1. At session start, read entities/user.md and check 00-Inbox/AI-INBOX.md.
2. When you learn a durable fact (decision, preference, project state),
   write it to the matching file in entities/ — create the file if needed.
   Use wiki-links like [[entities/other-entity.md]] between related entities.
3. The imported archive in 05-AI-Sessions/ is searchable history from before you
   were installed. SEARCH it whenever the user references past work or asks
   "where were we on X", "what do I know about Y", or names any past topic.
   DO THIS FIRST — do not guess filenames, and do not look only in 01-Projects/.
   Recipe (run from the vault root via your terminal tool):
       grep -rli "KEYWORD" 05-AI-Sessions/
   then read the matching files and answer from them. Try keyword variants.
   Only say you found nothing AFTER that grep returns nothing.
4. Keep entity files short and factual. This vault outlives any single agent —
   write for a future reader, not for yourself.

## Update Advisor (read-only — never self-modify)
Once per day, or when the user asks "check for updates":
1. Inventory installed components: hermes --version, ollama --version,
   ollama list, and the ai-memory scripts (--version).
2. Check PRIMARY SOURCES ONLY for newer releases:
   github.com/NousResearch/hermes-agent/releases and
   github.com/ollama/ollama/releases. Ignore blogs and aggregators.
3. Write a short report with findings and exact upgrade commands to
   00-Inbox/UPDATES.md. NEVER install or upgrade anything yourself.
   The user decides; you may execute an upgrade only after explicit approval.
AGENTSMD

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — mcpvault
# ═════════════════════════════════════════════════════════════════════════════
if step_done "2"; then
  skip "Step 2/7 — mcpvault"
else
  hdr "Step 2/7  mcpvault"
  step_start "2"

  if npm list -g @bitbonsai/mcpvault &>/dev/null 2>&1; then
    skip "mcpvault"
  else
    calm "Installing mcpvault from npm (small, but npm can sit quietly for a bit)."
    start_spinner "Installing mcpvault..."
    npm install -g @bitbonsai/mcpvault --no-audit --no-fund --silent 2>/dev/null \
      && { stop_spinner; ok "mcpvault installed"; } \
      || { stop_spinner; warn "Global install failed — npx fallback will be used automatically"; }
  fi

  step_end "2"
  step_complete "2"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — Hermes Agent
# ═════════════════════════════════════════════════════════════════════════════
if step_done "3"; then
  skip "Step 3/7 — Hermes Agent"
else
  hdr "Step 3/7  Hermes Agent"
  step_start "3"

  check_disk_space 3 "$HOME"
  mkdir -p "$VAULT/05-AI-Sessions/hermes"

  # Hermes is a Python project with its own official installer.
  # It handles uv, Python 3.11, Node 22 and everything else itself.
  if command -v hermes &>/dev/null || [[ -d "$HOME/.hermes" ]]; then
    skip "Hermes Agent (found 'hermes' command or ~/.hermes)"
  else
    DO_HERMES="$INSTALL_HERMES"
    if [[ "$DO_HERMES" == "ask" ]]; then
      if $ASSUME_YES || ! $CAN_PROMPT; then
        DO_HERMES="yes"
      else
        blank
        echo -e "  Hermes Agent is the local AI agent layer (recommended, optional)."
        echo -e "  Its official installer runs ${BOLD}curl | bash${NC} from NousResearch."
        echo -e "  Review it first if you wish:"
        echo -e "  ${CYAN}https://github.com/NousResearch/hermes-agent/blob/main/scripts/install.sh${NC}"
        echo -e "${BOLD}Install Hermes Agent? [Y/n]${NC}"
        read -r _h < /dev/tty || _h=""
        [[ "$(lc "${_h:-y}")" == "n" ]] && DO_HERMES="no" || DO_HERMES="yes"
      fi
    fi
    if [[ "$DO_HERMES" == "no" ]]; then
      HERMES_SKIPPED=true
      info "Skipping Hermes — vault and ingest remain fully functional"
    else
      info "Running the official Hermes installer (this takes 3–6 minutes)..."
      info "Source: https://github.com/NousResearch/hermes-agent"
      blank
      # Run interactively so its own prompts work; do NOT pipe through our spinner
      if curl -fsSL --max-time 60 \
           https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
           | bash -s -- --skip-setup; then
        ok "Hermes Agent installed"
      else
        warn "Hermes installer failed — install manually later:"
        warn "  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash"
      fi
      # PATH may need a new shell for the 'hermes' command
      if ! command -v hermes &>/dev/null && [[ -d "$HOME/.hermes" ]]; then
        info "'hermes' command not in PATH yet — a new terminal will pick it up"
      fi
    fi
  fi

  step_end "3"
  step_complete "3"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — MCP configuration
# ═════════════════════════════════════════════════════════════════════════════
if step_done "4"; then
  skip "Step 4/7 — MCP configuration"
else
  hdr "Step 4/7  MCP configuration"
  step_start "4"

  MCP_SERVERS_JSON='{"obsidian-vault":{"command":"npx","args":["-y","@bitbonsai/mcpvault@latest","'"$VAULT"'"]}}'

  # Claude Desktop — only merge if file already exists
  if [[ -f "$CLAUDE_DESKTOP" ]]; then
    safe_json_merge "$CLAUDE_DESKTOP" "$MCP_SERVERS_JSON" \
      && ok "Claude Desktop config updated"
  else
    info "Claude Desktop not installed yet — config will be added when it is"
  fi

  # Claude Code (.mcp.json — auto-detected in vault root)
  echo "{\"mcpServers\":$MCP_SERVERS_JSON}" \
    | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin),indent=2))" \
    > "$VAULT/.mcp.json"
  ok ".mcp.json written (Claude Code auto-detects this)"

  echo "$MCP_SERVERS_JSON" > "$MCP_DIR/mcp-servers.json"

  step_end "4"
  step_complete "4"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 — Session Continuity skill
# ═════════════════════════════════════════════════════════════════════════════
if step_done "5"; then
  # Always re-write skill — may have improved in newer versions of setup.sh
  # But only if the step was previously completed (not a fresh run reaching here)
  mkdir -p "$SKILL_DIR"
  cat > "$SKILL_DIR/session-continuity.md" << SKILLMD
# Session Continuity

## At session start
1. Read \`$VAULT/05-AI-Sessions/CURRENT_SESSION.md\` if it exists
2. Summarize: "Continuing from: [summary]"
3. Check \`$VAULT/00-Inbox/AI-INBOX.md\` — read, confirm, clear

## During session
- Update CURRENT_SESSION.md at important decisions or forks
- Format: date · context · decision · next steps · open questions

## At session end
1. Write final CURRENT_SESSION.md
2. Confirm: "Session saved. Will resume automatically next time."
SKILLMD
  skip "Step 5/7 — Session Continuity skill (refreshed)"
else
  hdr "Step 5/7  Session Continuity skill"
  step_start "5"

  mkdir -p "$SKILL_DIR"
  cat > "$SKILL_DIR/session-continuity.md" << SKILLMD
# Session Continuity

## At session start
1. Read \`$VAULT/05-AI-Sessions/CURRENT_SESSION.md\` if it exists
2. Summarize: "Continuing from: [summary]"
3. Check \`$VAULT/00-Inbox/AI-INBOX.md\` — read, confirm, clear

## During session
- Update CURRENT_SESSION.md at important decisions or forks
- Format: date · context · decision · next steps · open questions

## At session end
1. Write final CURRENT_SESSION.md
2. Confirm: "Session saved. Will resume automatically next time."
SKILLMD
  ok "Skill installed: $SKILL_DIR/session-continuity.md"

  step_end "5"
  step_complete "5"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 — resume.sh
# ═════════════════════════════════════════════════════════════════════════════
if step_done "6"; then
  skip "Step 6/7 — resume.sh"
else
  hdr "Step 6/7  resume.sh"
  step_start "6"

  cat > "$TOOLS/resume.sh" << RESUMESH
#!/usr/bin/env bash
# resume.sh — Resume AI session with full context
# Usage: bash .tools/resume.sh [claude|hermes] [project]

set -euo pipefail
AGENT="\${1:-hermes}"
PROJECT="\${2:-default}"
VAULT="$VAULT"
CONFIG="$MCP_DIR/ai-config.json"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   AI Memory Stack — Resume session       ║"
echo "╚══════════════════════════════════════════╝"
echo ""

if [[ -f "\$CONFIG" ]]; then
  MODEL=\$(python3 -c "import json; print(json.load(open('\$CONFIG'))['primary']['model'])" \
    2>/dev/null || echo "not configured")
  echo "  Primary model: \$MODEL"
fi

SESSION_FILE="\$VAULT/05-AI-Sessions/CURRENT_SESSION.md"
if [[ -f "\$SESSION_FILE" ]]; then
  echo ""
  echo "── Last session ───────────────────────────"
  head -25 "\$SESSION_FILE"
  echo "───────────────────────────────────────────"
fi

if command -v ollama &>/dev/null && ollama list &>/dev/null 2>&1; then
  echo ""
  echo "── Local models ───────────────────────────"
  ollama list
  echo "───────────────────────────────────────────"
fi

echo ""
cd "\$VAULT"

case "\$AGENT" in
  hermes)
    echo "Starting Hermes Agent..."
    if command -v hermes &>/dev/null; then
      exec hermes chat
    else
      echo "Hermes not found in PATH. Install or open a new terminal:"
      echo "  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash"
    fi
    ;;
  claude)
    echo "Starting Claude Code..."
    exec claude --project "\$PROJECT" 2>/dev/null \
      || exec claude 2>/dev/null \
      || echo "Claude Code not installed. Open Claude Desktop — MCP starts automatically."
    ;;
  *)
    echo "Unknown agent '\$AGENT' — defaulting to hermes"
    exec bash "\$0" hermes ;;
esac
RESUMESH
  chmod +x "$TOOLS/resume.sh"
  ok "resume.sh created"

  step_end "6"
  step_complete "6"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7 — VERIFICATION
# ═════════════════════════════════════════════════════════════════════════════
hdr "Step 7/7  Verification"

verify() {
  local label="$1" check="$2"
  eval "$check" &>/dev/null 2>&1 && ok "$label" || err "$label"
}

verify "git"               "git --version"
verify "Node.js 18+"       "[[ \$(node --version | sed 's/v//' | cut -d. -f1) -ge 18 ]]"
verify "npm"               "npm --version"
verify "python3"           "python3 --version"
verify "Ollama installed"  "command -v ollama"
verify "Vault structure"   "[[ -d '$VAULT/entities' && -d '$VAULT/00-Inbox' ]]"
verify "mcpvault (npx)"    "npx --yes @bitbonsai/mcpvault@latest --help"
if [[ "$HERMES_SKIPPED" != "true" ]]; then
  verify "Hermes present"    "command -v hermes || [[ -d \$HOME/.hermes ]]"
fi
verify "MCP .mcp.json"     "[[ -f '$VAULT/.mcp.json' ]]"
verify "Session skill"     "[[ -f '$SKILL_DIR/session-continuity.md' ]]"
verify "resume.sh"         "[[ -f '$TOOLS/resume.sh' ]]"

# ── Result ────────────────────────────────────────────────────────────────────
blank
if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}  ✓  Installation complete — no errors    ${NC}"
  echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
  blank
  echo -e "  Vault:  ${CYAN}$VAULT${NC}"
  echo -e "  Log:    ${CYAN}$LOG_FILE${NC}"
  blank
  echo -e "${BOLD}What was created/modified:${NC}"
  echo -e "  ${DIM}• $VAULT/                      (vault + all content)${NC}"
  echo -e "  ${DIM}• ~/.npm-global/               (npm prefix, no sudo)${NC}"
  [[ -d "$HOME/.hermes" ]] && \
  echo -e "  ${DIM}• ~/.hermes/                   (Hermes Agent home)${NC}"
  echo -e "  ${DIM}• $SKILL_DIR/session-continuity.md${NC}"
  [[ -f "$CLAUDE_DESKTOP" ]] && \
  echo -e "  ${DIM}• $CLAUDE_DESKTOP (merged, backup saved)${NC}"
  [[ "$OS" == "macos" ]] && \
  echo -e "  ${DIM}• ~/Library/LaunchAgents/com.ollama.serve.plist${NC}"
  [[ "$OS" == "linux" ]] && \
  echo -e "  ${DIM}• ~/.config/systemd/user/ollama.service${NC}"
  blank
  echo -e "${BOLD}Next steps:${NC}"
  blank
  echo -e "  1. Open Obsidian → point it at: ${CYAN}$VAULT${NC}  (optional, do anytime)"
  echo -e "  2. Configure your model (next)   3. Import history   4. (optional) remote node"
  blank

  # ── Chain into configure (Model B: offer, don't force) ─────────────────────
  # New tools (Ollama, brew, hermes) may not be on PATH in THIS shell yet, so a
  # fresh shell is the safe default — but we offer to continue right here too.
  CONFIGURE="$TOOLS/ai-memory-configure.sh"
  if $ASSUME_YES || ! $CAN_PROMPT; then
    echo -e "  Next: ${CYAN}bash $CONFIGURE $VAULT${NC}"
    echo -e "  ${DIM}(open a new terminal first so freshly-installed tools are on PATH)${NC}"
  else
    blank
    echo -e "  Freshly-installed tools (Ollama, etc.) are picked up reliably in a"
    echo -e "  ${BOLD}new terminal window${NC}. Recommended: open one and run:"
    echo -e "     ${CYAN}bash $CONFIGURE $VAULT${NC}"
    blank
    echo -e "${BOLD}Or continue here now? [y/N]${NC}"
    echo -e "  ${DIM}(fine in most cases; choose 'n' if a later step can't find 'ollama')${NC}"
    read -r _cont < /dev/tty || _cont=""
    if [[ "$(lc "${_cont:-n}")" == "y" ]]; then
      # refresh PATH best-effort for this session before handing off
      [[ -d "$NPM_PREFIX/bin" ]] && export PATH="$NPM_PREFIX/bin:$PATH"
      [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
      [[ -f /usr/local/bin/brew   ]] && eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
      if [[ -f "$CONFIGURE" ]]; then
        echo -e "${CYAN}→ Launching configure...${NC}"
        exec bash "$CONFIGURE" "$VAULT"
      fi
    fi
  fi
  blank
  # Identity block — copy onto the checklist
  IDENT_HOST="$(hostname 2>/dev/null || echo '?')"
  if [[ "$OS" == "macos" ]]; then
    IDENT_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo '?')"
  else
    IDENT_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    IDENT_IP="${IDENT_IP:-?}"
  fi
  IDENT_USER="${USER:-$(id -un 2>/dev/null || echo user)}"
  echo -e "${BOLD}Identity block — copy onto your checklist:${NC}"
  echo -e "    Hostname:  $IDENT_HOST"
  echo -e "    Local IP:  $IDENT_IP"
  echo -e "    SSH line:  ssh $IDENT_USER@$IDENT_IP"
  command -v tailscale &>/dev/null && \
  echo -e "    Tailscale: $(tailscale ip -4 2>/dev/null | head -1 || echo 'not connected')"
  blank
  echo -e "  ${DIM}Tip: once everything works — see the Tips & Tricks page in the"
  echo -e "  checklist: cmux for agent workflows (macOS), Syncthing for vault sync.${NC}"
  blank
  # ── §B4: the LAST thing on screen is the literal next command ──────────────
  echo -e "${GREEN}${BOLD}▶ NEXT — open a NEW terminal and run:${NC}"
  echo -e "     ${CYAN}${BOLD}bash $CONFIGURE $VAULT${NC}"
  echo -e "  ${DIM}(a fresh terminal so freshly-installed tools are on PATH)${NC}"
  blank
else
  echo -e "${RED}${BOLD}══════════════════════════════════════════${NC}"
  echo -e "${RED}${BOLD}  ✗  $ERRORS error(s) — fix and re-run    ${NC}"
  echo -e "${RED}${BOLD}══════════════════════════════════════════${NC}"
  blank
  echo -e "  ${CYAN}bash $SCRIPT_PATH $VAULT${NC}"
  blank
  exit 1
fi
