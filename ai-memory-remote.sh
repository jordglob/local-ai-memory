#!/usr/bin/env bash
# =============================================================================
#  ai-memory-remote.sh  v1.0
#  Remote access & always-on setup for AI Memory Stack nodes
#
#  What it configures (each part asked, nothing silent):
#    1. SSH server          — enable + install your public key
#    2. SSH hardening       — disable password login (only after key verified)
#    3. Tailscale           — reach the node from anywhere (optional)
#    4. RustDesk            — graphical access for macOS popups (optional)
#    5. Always-on power     — no sleep, auto-restart after power loss
#    6. Identity block      — everything you need to write on the checklist
#
#  Secrets model: this script creates, moves and protects keys but NEVER
#  stores, displays or invents secrets. Only PUBLIC keys are handled.
#  RustDesk's permanent password is set in its GUI — never by this script.
#
#  Usage:  bash ai-memory-remote.sh [path/to/vault] [--yes]
#  Run ON the node (the machine you want to reach), not on your client.
# =============================================================================
set -euo pipefail

VERSION="1.0"

case "${1:-}" in
  -h|--help)
    sed -n '2,20p' "$0" | sed 's/^#//'; exit 0 ;;
  -V|--version) echo "ai-memory-remote.sh v$VERSION"; exit 0 ;;
esac

# ── TTY / colors ──────────────────────────────────────────────────────────────
IS_TTY=false; [[ -t 1 ]] && IS_TTY=true
CAN_PROMPT=false; [[ -r /dev/tty && -w /dev/tty ]] && CAN_PROMPT=true
if $IS_TTY; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi
ok()   { echo -e "${GREEN}✓${NC}  $*"; }
info() { echo -e "${CYAN}→${NC}  $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
die()  { echo -e "\n${RED}${BOLD}✗  ERROR: $*${NC}\n" >&2; exit 1; }
hdr()  { echo -e "\n${BOLD}── $* ──${NC}"; }
skip() { echo -e "${DIM}↷  $* (already done)${NC}"; }
lc()   { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

ASSUME_YES=false
VAULT=""
for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=true ;;
    -*) echo "Unknown flag: $arg (see --help)" >&2; exit 1 ;;
    *)  [[ -z "$VAULT" ]] && VAULT="$arg" ;;
  esac
done
VAULT="${VAULT:-$HOME/Documents/ai-memory}"

ask_yn() {  # ask_yn "question" default(y|n)
  local q="$1" def="${2:-y}" ans
  if $ASSUME_YES; then return 0; fi
  if ! $CAN_PROMPT; then
    warn "Non-interactive — assuming '$def' for: $q"
    [[ "$def" == "y" ]]; return $?
  fi
  if [[ "$def" == "y" ]]; then
    echo -e "${BOLD}$q [Y/n]${NC}" > /dev/tty
  else
    echo -e "${BOLD}$q [y/N]${NC}" > /dev/tty
  fi
  read -r ans < /dev/tty
  ans="$(lc "${ans:-$def}")"
  [[ "$ans" == "y" || "$ans" == "yes" || "$ans" == "j" || "$ans" == "ja" ]]
}

pause_for() {  # blocking instruction without verification
  local msg="$1"
  blank=""; echo ""
  echo -e "${YELLOW}${BOLD}ACTION REQUIRED:${NC}"
  echo -e "$msg"
  if $CAN_PROMPT && ! $ASSUME_YES; then
    echo -e "${BOLD}Press ENTER when done:${NC}" > /dev/tty
    read -r _ < /dev/tty
  else
    warn "Non-interactive — complete this manually later"
  fi
}

# ── OS / sudo ────────────────────────────────────────────────────────────────
OS="linux"; [[ "$OSTYPE" == "darwin"* ]] && OS="macos"
PKG="none"
if [[ "$OS" == "linux" ]]; then
  command -v apt-get &>/dev/null && PKG="apt"
  command -v dnf     &>/dev/null && PKG="dnf"
  command -v pacman  &>/dev/null && PKG="pacman"
fi
[[ "${EUID:-$(id -u)}" -eq 0 ]] && die "Run as your normal user, not root.\nThe script asks for sudo when needed."

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   AI Memory Stack — Remote v1.0          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
info "OS: $OS${PKG:+ ($PKG)} · Node user: ${USER:-$(id -un)}"
echo ""
info "This configures the machine you are sitting at (or SSH'd into) as a"
info "remotely reachable node. Each part is optional and asked about."
echo ""

info "sudo is needed for: SSH service, sshd config, power settings."
sudo -v || die "sudo required."
( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
SUDO_PID=$!
trap 'kill $SUDO_PID 2>/dev/null || true' EXIT

REMOTE_USER="${USER:-$(id -un)}"

# ═════════════════════════════════════════════════════════════════════════════
hdr "1/6  SSH server"
# ═════════════════════════════════════════════════════════════════════════════
ssh_running() { nc -z localhost 22 2>/dev/null || pgrep -x sshd >/dev/null 2>&1; }

if ssh_running; then
  skip "SSH server"
else
  if [[ "$OS" == "macos" ]]; then
    info "Enabling Remote Login..."
    if sudo systemsetup -setremotelogin on 2>/dev/null && ssh_running; then
      ok "Remote Login enabled"
    else
      pause_for "  macOS blocked the command (common on newer versions).\n  Enable manually:\n    ${BOLD}System Settings → General → Sharing → Remote Login → On${NC}\n  Allow access for: your user."
      ssh_running && ok "Remote Login confirmed" || warn "SSH still not responding — fix before relying on this node"
    fi
  else
    info "Installing OpenSSH server..."
    case "$PKG" in
      apt)    sudo apt-get update -qq; sudo apt-get install -y -qq openssh-server ;;
      dnf)    sudo dnf install -y -q openssh-server ;;
      pacman) sudo pacman -S --noconfirm --needed openssh ;;
      *)      die "No supported package manager found" ;;
    esac
    sudo systemctl enable --now ssh 2>/dev/null || sudo systemctl enable --now sshd 2>/dev/null
    ssh_running && ok "SSH server running" || warn "sshd not responding — check: systemctl status sshd"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
hdr "2/6  Your public key"
# ═════════════════════════════════════════════════════════════════════════════
AUTH="$HOME/.ssh/authorized_keys"
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; touch "$AUTH"; chmod 600 "$AUTH"

add_key() {  # add_key "ssh-ed25519 AAAA... comment"
  local k="$1"
  [[ "$k" == ssh-* || "$k" == ecdsa-* ]] || { warn "That does not look like a public key — skipped"; return 1; }
  if grep -qF "$(echo "$k" | awk '{print $2}')" "$AUTH" 2>/dev/null; then
    skip "Key already installed"
  else
    echo "$k" >> "$AUTH"
    ok "Key added to authorized_keys"
  fi
}

if $CAN_PROMPT && ! $ASSUME_YES; then
  echo "  How do you want to install your PUBLIC key? (the private key never leaves your client)"
  echo "    1) Fetch from GitHub   (https://github.com/<username>.keys)"
  echo "    2) Paste it"
  echo "    3) Read from a file on this machine"
  echo "    Enter) Skip"
  echo -e "${BOLD}Choice:${NC}" > /dev/tty
  read -r choice < /dev/tty
  case "$choice" in
    1)
      echo -e "${BOLD}GitHub username:${NC}" > /dev/tty
      read -r ghuser < /dev/tty
      if [[ -n "$ghuser" ]]; then
        keys="$(curl -fsSL --max-time 15 "https://github.com/${ghuser}.keys" 2>/dev/null || true)"
        if [[ -n "$keys" ]]; then
          echo "$keys" | while IFS= read -r k; do [[ -n "$k" ]] && add_key "$k"; done
        else
          warn "No keys found for github.com/$ghuser"
        fi
      fi
      ;;
    2)
      echo -e "${BOLD}Paste the public key (one line, starts with ssh-ed25519/ssh-rsa):${NC}" > /dev/tty
      read -r pasted < /dev/tty
      [[ -n "$pasted" ]] && add_key "$pasted"
      ;;
    3)
      echo -e "${BOLD}Path to the .pub file:${NC}" > /dev/tty
      read -r kpath < /dev/tty
      [[ -f "$kpath" ]] && add_key "$(cat "$kpath")" || warn "File not found: $kpath"
      ;;
    *) info "Key installation skipped" ;;
  esac
else
  info "Non-interactive — key installation skipped (add manually to ~/.ssh/authorized_keys)"
fi

# ═════════════════════════════════════════════════════════════════════════════
hdr "3/6  SSH hardening (disable password login)"
# ═════════════════════════════════════════════════════════════════════════════
if [[ -s "$AUTH" ]] && grep -q "ssh-" "$AUTH" 2>/dev/null; then
  echo "  Before disabling password login, key login MUST be verified."
  echo "  From your CLIENT machine, open a NEW terminal and run:"
  IPGUESS="$( [[ "$OS" == "macos" ]] && ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' )"
  echo -e "    ${CYAN}ssh $REMOTE_USER@${IPGUESS:-<this-machine-ip>}${NC}"
  echo "  It must log in WITHOUT asking for the account password"
  echo "  (a key passphrase prompt is fine — that is your key, not the account)."
  if ask_yn "Did key login work, and do you want to disable password login?" n; then
    SSHD_DROPIN="/etc/ssh/sshd_config.d/99-ai-memory.conf"
    sudo mkdir -p /etc/ssh/sshd_config.d 2>/dev/null || true
    printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' | sudo tee "$SSHD_DROPIN" >/dev/null
    if [[ "$OS" == "macos" ]]; then
      sudo launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true
    else
      sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd 2>/dev/null || true
    fi
    ok "Password login disabled ($SSHD_DROPIN)"
    warn "Keep your key safe — it is now the only way in over SSH"
  else
    info "Password login kept (you can re-run this script later)"
  fi
else
  info "No key installed — skipping hardening (password login stays on)"
fi

# ═════════════════════════════════════════════════════════════════════════════
hdr "4/6  Tailscale (optional — reach the node from anywhere)"
# ═════════════════════════════════════════════════════════════════════════════
if command -v tailscale &>/dev/null && tailscale status &>/dev/null 2>&1; then
  skip "Tailscale (connected)"
elif ask_yn "Install Tailscale? (encrypted mesh VPN; login via browser; control plane is a cloud service)" n; then
  if [[ "$OS" == "macos" ]]; then
    command -v brew &>/dev/null || die "Homebrew required — run ai-memory-setup.sh first"
    brew install --cask tailscale 2>/dev/null || warn "brew cask install failed"
    pause_for "  Open the ${BOLD}Tailscale${NC} app (Applications), log in in the browser,\n  and approve this machine."
  else
    info "Installer is fetched with curl | sh from tailscale.com — review at https://tailscale.com/install.sh"
    if ask_yn "Proceed?" y; then
      curl -fsSL --max-time 60 https://tailscale.com/install.sh | sh || warn "Installer failed"
      if $CAN_PROMPT && ! $ASSUME_YES; then
        info "Starting auth — a login URL will be printed. Open it in any browser."
        sudo tailscale up || warn "tailscale up did not complete"
      else
        info "Non-interactive — run later: sudo tailscale up"
      fi
    fi
  fi
  tailscale status &>/dev/null 2>&1 && ok "Tailscale connected" || info "Tailscale not connected yet"
else
  info "Tailscale skipped (plain WireGuard is the no-cloud alternative — see Tips)"
fi

# ═════════════════════════════════════════════════════════════════════════════
hdr "5/6  RustDesk (optional — graphical access, e.g. for macOS popups)"
# ═════════════════════════════════════════════════════════════════════════════
if ask_yn "Install RustDesk?" n; then
  if [[ "$OS" == "macos" ]]; then
    command -v brew &>/dev/null || die "Homebrew required — run ai-memory-setup.sh first"
    brew install --cask rustdesk 2>/dev/null && ok "RustDesk installed" || warn "Install failed — get it from rustdesk.com"
    pause_for "  Open ${BOLD}RustDesk${NC} once and approve the permissions macOS asks for:\n    System Settings → Privacy & Security → ${BOLD}Screen Recording${NC} → RustDesk\n    System Settings → Privacy & Security → ${BOLD}Accessibility${NC} → RustDesk\n  Then, in RustDesk: Settings → Security → set a ${BOLD}permanent password${NC}\n  (store it in your password manager — this script never touches it).\n  Note the ${BOLD}RustDesk ID${NC} shown in the main window for your checklist."
  else
    warn "On Linux, download the package for your distro from https://rustdesk.com"
    pause_for "  Install the downloaded package, open RustDesk, set a permanent\n  password (Settings → Security), and note the RustDesk ID."
  fi
else
  info "RustDesk skipped"
fi

# ═════════════════════════════════════════════════════════════════════════════
hdr "6/6  Always-on power profile"
# ═════════════════════════════════════════════════════════════════════════════
if ask_yn "Is this an always-on node? (disable sleep, auto-restart after power loss)" y; then
  if [[ "$OS" == "macos" ]]; then
    sudo pmset -a sleep 0 disksleep 0 2>/dev/null && ok "System sleep disabled"
    sudo pmset -a displaysleep 10 2>/dev/null || true
    sudo pmset -a womp 1 2>/dev/null && ok "Wake-on-LAN enabled"
    sudo pmset -a autorestart 1 2>/dev/null && ok "Auto-restart after power loss set"
    warn "Apple Silicon minis sometimes IGNORE autorestart — the pull-the-plug"
    warn "test on the checklist is mandatory before trusting this node."
    pause_for "  For services to return after an unattended reboot, enable autologin:\n    ${BOLD}System Settings → Users & Groups → Automatically log in as → $REMOTE_USER${NC}\n  (Requires FileVault to be OFF — see the checklist's Tips page for the tradeoff.)"
  else
    sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null \
      && ok "Sleep/suspend masked"
    if command -v loginctl &>/dev/null; then
      loginctl enable-linger "$REMOTE_USER" 2>/dev/null \
        && ok "Linger enabled — your services start at boot without login" \
        || warn "Could not enable linger — run: loginctl enable-linger $REMOTE_USER"
    fi
    warn "BIOS 'Restore on AC Power Loss' cannot be scripted — set it in BIOS"
    warn "(checklist has the steps), then do the pull-the-plug test."
  fi
else
  info "Power profile unchanged"
fi

# ═════════════════════════════════════════════════════════════════════════════
hdr "Identity block — copy onto your checklist"
# ═════════════════════════════════════════════════════════════════════════════
IDENT_HOST="$(hostname 2>/dev/null || echo '?')"
if [[ "$OS" == "macos" ]]; then
  IDENT_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo '?')"
else
  IDENT_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"; IDENT_IP="${IDENT_IP:-?}"
fi
echo ""
echo -e "    Hostname:   ${BOLD}$IDENT_HOST${NC}"
echo -e "    Local IP:   ${BOLD}$IDENT_IP${NC}"
echo -e "    SSH line:   ${BOLD}ssh $REMOTE_USER@$IDENT_IP${NC}"
if command -v tailscale &>/dev/null; then
  TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"
  [[ -n "$TS_IP" ]] && echo -e "    Tailscale:  ${BOLD}$TS_IP${NC}  (works from anywhere)"
fi
echo -e "    RustDesk ID: see the RustDesk main window"
echo ""
echo -e "${BOLD}Final step (mandatory for nodes):${NC} the pull-the-plug test."
echo "  Shut down → pull the power cord → wait 1 min → plug back in."
echo "  The machine must boot, log in, and be reachable over SSH by itself."
echo "  If it does not power on: see the checklist (BIOS setting on PCs;"
echo "  on Apple Silicon minis autorestart is known to be unreliable)."
echo ""
ok "Remote setup done"
