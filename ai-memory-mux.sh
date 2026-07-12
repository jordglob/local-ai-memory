#!/usr/bin/env bash
# =============================================================================
#  ai-memory-mux.sh  v1.3
#  v1.3: back in the main family as the STANDARD interface (July 2026 —
#        briefly split to local-ai-memory-fleet). Defaults confirmed and now
#        normative: mouse support ON and a two-pane SIDE-BY-SIDE split
#        (split-window -h: agent chat left, working terminal right).
#  v1.2: ingest-on-start — before the agent launches, fast local sources
#        (hermes state.db + Claude Code transcripts) are archived into the
#        vault so every session starts with a fresh index. Deterministic,
#        quiet, never blocks the launch; opt out with AI_MEMORY_NO_INGEST=1.
#  v1.1: honor the "env wins" contract — environment variables now survive a
#        sourced mux.conf instead of being clobbered by its assignments.
#  Mouse-driven tmux launcher + menu for the AI Memory Stack's local agent.
#  Opens the agent (default: `hermes chat`) in one tmux pane with a working
#  terminal pane SIDE BY SIDE, mouse control on (click a pane, drag the border,
#  wheel-scroll, select-to-copy), so the agent runs in its own persistent
#  "terminal tab" you can detach from and re-attach to.
#
#  This is the STANDARD way to talk to your agent (plain `hermes chat` works
#  without tmux). It is an isolated surface: it never touches the vault's
#  contents, never stores or prints a secret, and only manages a tmux session
#  that YOU start. It applies its tmux options at the SESSION scope, so it
#  does not clobber your ~/.tmux.conf (use `install-tmux-conf` to opt into a
#  global, marker-blocked snippet).
#
#  Subcommands:
#    start   (default)  create-or-attach the session (agent + terminal split)
#    attach             attach to an existing session
#    menu               interactive menu (auto-shown when run on a TTY)
#    ls                 list tmux sessions
#    kill               kill the session
#    tips               print the mouse/tmux cheat-sheet
#    restart-agent      respawn just the agent pane (leave the terminal pane)
#    install-tmux-conf  add a marker-blocked mouse/quality-of-life snippet to
#                       ~/.tmux.conf (backs up first; idempotent; reversible)
#
#  Config (all optional; no secrets): env vars or ~/.config/ai-memory/mux.conf
#    AI_MEMORY_VAULT       vault dir              (default ~/Documents/ai-memory)
#    AI_MEMORY_AGENT_CMD   command in main pane   (default "hermes chat")
#    AI_MEMORY_MUX_SESSION tmux session name      (default "hermes")
#  Model-mode switches (only shown when configured, no hardcoded hosts/models):
#    AI_MEMORY_LOCAL_URL / AI_MEMORY_LOCAL_MODEL   local (e.g. Ollama) endpoint
#    AI_MEMORY_CLOUD_URL / AI_MEMORY_CLOUD_MODEL   cloud endpoint + model id
#
#  Usage: bash ai-memory-mux.sh [subcommand] [path/to/vault] [--no-attach] [--yes]
#  Exit:  0 = ok · 1 = usage/precondition error · 2 = tmux missing
# =============================================================================

# NOTE: intentionally NOT `set -e` — this is an interactive launcher that RUNS
# subcommands which are allowed to fail (a missing session, an agent that
# exits). We handle each result explicitly rather than aborting the menu.
set -uo pipefail

if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi
info() { echo -e "${CYAN}→${NC}  $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
err()  { echo -e "${RED}✗${NC}  $*" >&2; }
ok()   { echo -e "${GREEN}✓${NC}  $*"; }

VERSION="1.3"

# ── args ─────────────────────────────────────────────────────────────────────
SUBCMD=""
VAULT=""
NO_ATTACH=false
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    -h|--help)    sed -n '2,48p' "$0" | sed 's/^#//'; exit 0 ;;
    -V|--version) echo "ai-memory-mux.sh v$VERSION"; exit 0 ;;
    --no-attach)  NO_ATTACH=true ;;
    -y|--yes)     ASSUME_YES=true ;;
    start|attach|menu|ls|kill|tips|restart-agent|install-tmux-conf)
                  [[ -z "$SUBCMD" ]] && SUBCMD="$arg" ;;
    -*)           ;;
    *)            [[ -z "$VAULT" ]] && VAULT="$arg" ;;
  esac
done

# ── config (optional file; env wins; no secrets ever) ────────────────────────
MUX_CONF="${AI_MEMORY_MUX_CONF:-$HOME/.config/ai-memory/mux.conf}"
# "env wins" is a promise: a plain assignment in the sourced conf would
# silently clobber the caller's environment, so snapshot the env first and
# restore any value the caller actually set after the conf has loaded.
_env_vault="${AI_MEMORY_VAULT-}";        _env_agent="${AI_MEMORY_AGENT_CMD-}"
_env_session="${AI_MEMORY_MUX_SESSION-}"; _env_lurl="${AI_MEMORY_LOCAL_URL-}"
_env_lmodel="${AI_MEMORY_LOCAL_MODEL-}";  _env_curl="${AI_MEMORY_CLOUD_URL-}"
_env_cmodel="${AI_MEMORY_CLOUD_MODEL-}"
# shellcheck source=/dev/null
[[ -f "$MUX_CONF" ]] && . "$MUX_CONF"
[[ -n "$_env_vault"   ]] && AI_MEMORY_VAULT="$_env_vault"
[[ -n "$_env_agent"   ]] && AI_MEMORY_AGENT_CMD="$_env_agent"
[[ -n "$_env_session" ]] && AI_MEMORY_MUX_SESSION="$_env_session"
[[ -n "$_env_lurl"    ]] && AI_MEMORY_LOCAL_URL="$_env_lurl"
[[ -n "$_env_lmodel"  ]] && AI_MEMORY_LOCAL_MODEL="$_env_lmodel"
[[ -n "$_env_curl"    ]] && AI_MEMORY_CLOUD_URL="$_env_curl"
[[ -n "$_env_cmodel"  ]] && AI_MEMORY_CLOUD_MODEL="$_env_cmodel"

VAULT="${VAULT:-${AI_MEMORY_VAULT:-$HOME/Documents/ai-memory}}"
[[ "$VAULT" != /* ]] && VAULT="$PWD/$VAULT"
AGENT_CMD="${AI_MEMORY_AGENT_CMD:-hermes chat}"
SESSION="${AI_MEMORY_MUX_SESSION:-hermes}"
LOCAL_URL="${AI_MEMORY_LOCAL_URL:-}"
LOCAL_MODEL="${AI_MEMORY_LOCAL_MODEL:-}"
CLOUD_URL="${AI_MEMORY_CLOUD_URL:-}"
CLOUD_MODEL="${AI_MEMORY_CLOUD_MODEL:-}"

# Single-quote-escape a string for safe embedding in a shell command line.
shq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

have_tmux() { command -v tmux >/dev/null 2>&1; }
session_exists() { tmux has-session -t "$SESSION" 2>/dev/null; }

require_tmux() {
  if ! have_tmux; then
    err "tmux is not installed. Install it first:"
    echo "      Debian/Ubuntu/WSL:  sudo apt-get install -y tmux"
    echo "      macOS (brew):       brew install tmux"
    exit 2
  fi
}

# Apply mouse + quality-of-life options at SESSION scope (does not touch
# ~/.tmux.conf). Safe to call repeatedly.
apply_session_options() {
  tmux set-option -t "$SESSION" mouse on 2>/dev/null || true
  tmux set-option -t "$SESSION" history-limit 50000 2>/dev/null || true
  tmux set-option -t "$SESSION" pane-border-status top 2>/dev/null || true
  tmux set-option -t "$SESSION" pane-border-format \
    " #{pane_index}: #{pane_current_command} " 2>/dev/null || true
}

# Archive fast local history (the agent's own past sessions + Claude Code
# transcripts) into the vault before the agent wakes, so every start begins
# with a fresh, complete index. Deterministic and idempotent — deliberately a
# script's job, never the agent's. Quiet; failures never block the launch.
# Opt out with AI_MEMORY_NO_INGEST=1.
ingest_on_start() {
  [[ "${AI_MEMORY_NO_INGEST:-0}" = "1" ]] && return 0
  local here ing src
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for ing in "$here/ai-memory-ingest.sh" "$VAULT/.tools/ai-memory-ingest.sh"; do
    [[ -f "$ing" ]] || continue
    info "refreshing memory index (hermes + claude-code → vault)"
    for src in hermes claude-code; do
      bash "$ing" "$VAULT" --source "$src" --yes >/dev/null 2>&1 || true
    done
    return 0
  done
}

# ── core: start / attach ─────────────────────────────────────────────────────
mux_start() {
  require_tmux
  if [[ ! -d "$VAULT" ]]; then
    warn "vault dir not found: $VAULT"
    warn "run ai-memory-setup.sh first, or pass the right path."
  fi
  ingest_on_start
  if session_exists; then
    info "attaching to the existing '$SESSION' session"
    mux_attach
    return
  fi

  info "starting tmux session '$SESSION'"
  info "  main pane:     $AGENT_CMD"
  info "  side pane:     interactive shell in $VAULT"

  tmux new-session -d -s "$SESSION" -x 220 -y 50 || { err "could not create session"; return 1; }
  apply_session_options
  # Mark the environment so an agent can detect it runs inside the mux tab.
  tmux set-environment -t "$SESSION" AI_MEMORY_MUX 1 2>/dev/null || true

  # Right-hand terminal pane, parked in the vault.
  tmux split-window -h -t "$SESSION:0" "cd $(shq "$VAULT") && exec \"\$SHELL\"" 2>/dev/null \
    || tmux split-window -h -t "$SESSION:0" "cd $(shq "$VAULT") && exec bash"
  tmux select-layout -t "$SESSION:0" main-vertical 2>/dev/null || true
  tmux set-option  -t "$SESSION" main-pane-width 78 2>/dev/null || true
  tmux select-pane -t "$SESSION:0.0" -T "agent" 2>/dev/null || true
  tmux select-pane -t "$SESSION:0.1" -T "terminal" 2>/dev/null || true

  # Launch the agent in the main pane. send-keys (not exec) so that if the agent
  # exits you drop to a shell in the vault rather than killing the pane.
  tmux send-keys -t "$SESSION:0.0" \
    "cd $(shq "$VAULT") && export AI_MEMORY_MUX=1 && $AGENT_CMD" C-m

  if $NO_ATTACH; then
    ok "session '$SESSION' created (not attaching: --no-attach)"
    return 0
  fi
  mux_attach
}

mux_attach() {
  require_tmux
  if ! session_exists; then
    warn "no '$SESSION' session — starting a new one"
    mux_start
    return
  fi
  apply_session_options
  if [[ -n "${TMUX:-}" ]]; then
    # Already inside tmux: switch instead of nesting.
    tmux switch-client -t "$SESSION" 2>/dev/null && return 0
    warn "already inside tmux; run 'tmux switch-client -t $SESSION' or detach first."
    return 1
  fi
  tmux attach -t "$SESSION"
}

mux_kill() {
  require_tmux
  if ! session_exists; then info "no '$SESSION' session to kill."; return 0; fi
  if ! $ASSUME_YES; then
    printf "  kill tmux session '%s'? [y/N] " "$SESSION"
    local reply=""; read -r reply < /dev/tty 2>/dev/null || reply=""
    case "$reply" in y|Y|yes|YES) ;; *) info "left running."; return 0 ;; esac
  fi
  tmux kill-session -t "$SESSION" && ok "session '$SESSION' closed."
}

mux_ls() {
  require_tmux
  echo "  tmux sessions:"
  tmux ls 2>/dev/null | sed 's/^/    /' || echo "    (none)"
}

mux_restart_agent() {
  require_tmux
  if ! session_exists; then info "no '$SESSION' session — starting one."; mux_start; return; fi
  tmux respawn-pane -k -t "$SESSION:0.0" \
    "cd $(shq "$VAULT") && export AI_MEMORY_MUX=1 && $AGENT_CMD" 2>/dev/null \
    && ok "restarted the agent pane ($SESSION:0.0)"
  [[ -z "${TMUX:-}" ]] && ! $NO_ATTACH && mux_attach
}

mux_tips() {
cat <<'T'
  📜 tmux cheat-sheet (mouse mode is ON)
  Scroll:         mouse wheel.  Or: Ctrl-b [  → ↑/↓ / PgUp / PgDn,  q = quit
  Search scrollback: Ctrl-b [ , then Ctrl-s , type + Enter , n = next,  q = quit
  Switch pane:    click it with the mouse  (or Ctrl-b + arrow)
  Zoom a pane:    Ctrl-b z   (toggle fullscreen)
  Resize pane:    drag the border with the mouse  (or Ctrl-b + hold Ctrl + arrow)
  Detach:         Ctrl-b d   (everything keeps running in the background)
  Copy text:      select with the mouse (auto-copies)  ·  paste: Ctrl-b ]
  New/close pane: Ctrl-b %  (v)  ·  Ctrl-b "  (h)  ·  exit  (close)
  Re-attach later: tmux attach -t hermes   (or: bash ai-memory-mux.sh attach)
T
}

# ── optional: model-mode switches (only when configured) ─────────────────────
modes_configured() { [[ -n "$LOCAL_URL$CLOUD_URL" ]]; }

mode_local() {
  if [[ -z "$LOCAL_URL" || -z "$LOCAL_MODEL" ]]; then
    warn "local mode not configured (set AI_MEMORY_LOCAL_URL + AI_MEMORY_LOCAL_MODEL)"; return 1
  fi
  hermes config set model.provider ollama       >/dev/null 2>&1 || true
  hermes config set model.base_url "$LOCAL_URL"  >/dev/null 2>&1 || true
  hermes config set model.default  "$LOCAL_MODEL">/dev/null 2>&1 || true
  ok "mode: LOCAL ($LOCAL_MODEL @ $LOCAL_URL). restart the agent to apply."
}
mode_cloud() {
  if [[ -z "$CLOUD_URL" || -z "$CLOUD_MODEL" ]]; then
    warn "cloud mode not configured (set AI_MEMORY_CLOUD_URL + AI_MEMORY_CLOUD_MODEL)"; return 1
  fi
  hermes config set model.provider auto         >/dev/null 2>&1 || true
  hermes config set model.base_url "$CLOUD_URL" >/dev/null 2>&1 || true
  hermes config set model.default  "$CLOUD_MODEL">/dev/null 2>&1 || true
  ok "mode: CLOUD ($CLOUD_MODEL @ $CLOUD_URL). restart the agent to apply."
}
mode_show() {
  if command -v hermes >/dev/null 2>&1; then
    hermes config show 2>/dev/null | grep -iE "provider|base_url|default" | head -3 | sed 's/^/    /'
  else
    echo "    (hermes not found on PATH)"
  fi
}

# ── install a marker-blocked tmux.conf snippet (opt-in, reversible) ──────────
mux_install_tmux_conf() {
  local rc="$HOME/.tmux.conf"
  local begin="# >>> ai-memory-mux >>>"
  local end="# <<< ai-memory-mux <<<"
  if [[ -f "$rc" ]] && grep -qF "$begin" "$rc"; then
    ok " ~/.tmux.conf already has the ai-memory-mux block (nothing to do)."
    return 0
  fi
  if [[ -f "$rc" ]]; then
    cp -p "$rc" "$rc.bak.$$" && info "backed up existing ~/.tmux.conf → $rc.bak.$$"
  fi
  {
    printf '%s\n' "$begin"
    printf '%s\n' "set -g mouse on"
    printf '%s\n' "set -g history-limit 50000"
    printf '%s\n' "set -g pane-border-status top"
    printf '%s\n' 'set -g pane-border-format " #{pane_index}: #{pane_current_command} "'
    printf '%s\n' "$end"
  } >> "$rc"
  ok "added mouse/quality-of-life block to ~/.tmux.conf (reversible: delete the marked block)."
}

# ── interactive menu ─────────────────────────────────────────────────────────
mux_menu() {
  local c=""
  while true; do
    echo ""
    echo -e "  ${BOLD}═══════════ AI MEMORY · MUX ═══════════${NC}"
    echo    "    vault:    $VAULT"
    echo    "    agent:    $AGENT_CMD"
    if session_exists; then
      echo -e "    session:  ${GREEN}🟢 '$SESSION' running${NC}"
    else
      echo -e "    session:  ${DIM}⚪ '$SESSION' not started${NC}"
    fi
    if modes_configured; then
      echo    "    model:  "; mode_show
    fi
    echo    "  ─────────────────────────────────────────"
    echo    "    1) open / attach  (agent + terminal, mouse on)"
    echo    "    2) list sessions        3) kill session"
    echo    "    4) restart agent pane   5) tmux tips"
    if modes_configured; then
      echo  "    6) local model mode     7) cloud model mode"
    fi
    echo    "    0) plain shell (quit)"
    echo -e "  ${BOLD}═══════════════════════════════════════${NC}"
    printf  "  choice> "
    read -r c < /dev/tty 2>/dev/null || c="0"
    c="${c%$'\r'}"
    case "$c" in
      1|h|H|"")  mux_start ;;
      2)         mux_ls ;;
      3)         mux_kill ;;
      4)         mux_restart_agent ;;
      5|t|T)     mux_tips ;;
      6)         modes_configured && mode_local ;;
      7)         modes_configured && mode_cloud ;;
      0|q|Q)     info "back to your shell (run 'bash ai-memory-mux.sh menu' to return)."; break ;;
      *)         warn "unknown choice: $c" ;;
    esac
  done
}

# ── dispatch ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   AI Memory Stack  v$VERSION — Mux (tmux)     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"

case "${SUBCMD:-}" in
  start|"")         if [[ -z "$SUBCMD" && -t 0 && -t 1 ]]; then mux_menu; else mux_start; fi ;;
  attach)           mux_attach ;;
  menu)             mux_menu ;;
  ls)               mux_ls ;;
  kill)             mux_kill ;;
  tips)             mux_tips ;;
  restart-agent)    mux_restart_agent ;;
  install-tmux-conf) mux_install_tmux_conf ;;
  *)                err "unknown subcommand: $SUBCMD"; exit 1 ;;
esac

# ── NEXT ─────────────────────────────────────────────────────────────────────
if [[ "${SUBCMD:-}" != "menu" && "${SUBCMD:-}" != "" ]]; then
  echo ""
  echo -e "${BOLD}▶ NEXT${NC}  verify the stack is healthy:"
  echo    "  bash ai-memory-doctor.sh"
fi
