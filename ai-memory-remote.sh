#!/usr/bin/env bash
# =============================================================================
#  ai-memory-remote.sh  v2.6
#  Remote access & always-on setup for AI Memory Stack nodes
#
#  First question: what is this machine?
#    MAIN  — the computer you sit at. Gets an SSH keypair (one per client
#            machine, never copied), optional Tailscale client. No sshd.
#    NODE  — a machine reached remotely. SSH server + your public key,
#            hardening, optional Tailscale/RustDesk host, always-on power.
#    SOLO  — your only computer. Remote access is unnecessary; exits.
#
#  Run on the MAIN machine first (creates your key), then on each NODE.
#  Flags: --role main|node|solo  --yes
#
#  Secrets model: this script creates, moves and protects keys but NEVER
#  stores, displays or invents secrets. Only PUBLIC keys are handled.
#  RustDesk's permanent password is set in its GUI — never by this script.
#
#  Usage:  bash ai-memory-remote.sh [path/to/vault] [--yes]
#  Run ON the node (the machine you want to reach), not on your client.
# =============================================================================
set -euo pipefail

VERSION="2.6"

case "${1:-}" in
  -h|--help)
    sed -n '2,20p' "$0" | sed 's/^#//'; exit 0 ;;
  -V|--version) echo "ai-memory-remote.sh v$VERSION"; exit 0 ;;
esac

# ── TTY / colors ──────────────────────────────────────────────────────────────
IS_TTY=false; [[ -t 1 ]] && IS_TTY=true
# Probe by actually OPENING /dev/tty: the node exists with rw mode even when there
# is no controlling terminal, so `[[ -r/-w ]]` is a false positive (open ENXIOs).
CAN_PROMPT=false; { : >/dev/tty; } 2>/dev/null && CAN_PROMPT=true
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
ROLE=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--role" ]]; then ROLE="$(lc "$arg")"; prev=""; continue; fi
  case "$arg" in
    --role)   prev="--role" ;;
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
  read -r ans < /dev/tty || ans=""
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
    read -r _ < /dev/tty || _=""
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
echo -e "${BOLD}║   AI Memory Stack — Remote v2.6          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
info "OS: $OS${PKG:+ ($PKG)} · Node user: ${USER:-$(id -un)}"
echo ""
info "This configures the machine you are sitting at (or SSH'd into) as a"
info "remotely reachable node. Each part is optional and asked about."
echo ""

# ── Machine role ──────────────────────────────────────────────────────────────
if [[ -z "$ROLE" ]] && $CAN_PROMPT && ! $ASSUME_YES; then
  echo -e "${BOLD}What is this machine?${NC}"
  echo "    1) MAIN — the computer I sit at (creates your SSH key; no server)"
  echo "    2) NODE — reached remotely (SSH server, always-on, RustDesk host)"
  echo "    3) SOLO — my only computer (remote access not needed)"
  echo -e "${BOLD}Choice [1/2/3]:${NC}" > /dev/tty
  read -r _r < /dev/tty || _r=""
  case "$_r" in 1) ROLE="main" ;; 3) ROLE="solo" ;; *) ROLE="node" ;; esac
fi
ROLE="${ROLE:-node}"

if [[ "$ROLE" == "solo" ]]; then
  info "Only computer → nothing to configure here. Remote access matters only"
  info "when there is a second machine to reach. Re-run this when you add one."
  exit 0
fi

if [[ "$ROLE" == "main" ]]; then
  hdr "MAIN machine — your SSH identity"
  if ! command -v ssh-keygen &>/dev/null; then
    info "Installing OpenSSH client tools..."
    case "$PKG" in
      apt)    sudo apt-get -o DPkg::Lock::Timeout=300 update -qq 2>/dev/null || true; sudo apt-get -o DPkg::Lock::Timeout=300 install -y -qq openssh-client ;;
      dnf)    sudo dnf install -y -q openssh-clients ;;
      pacman) sudo pacman -S --noconfirm --needed openssh ;;
    esac
    command -v ssh-keygen &>/dev/null || die "ssh-keygen unavailable — install OpenSSH manually"
  fi
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  KEY="$HOME/.ssh/id_ed25519"
  if [[ -f "$KEY" ]]; then
    skip "SSH keypair ($KEY)"
  else
    info "Creating your keypair (one per client machine — never copy it elsewhere)."
    info "Pick a passphrase; on macOS it is stored in the Keychain so you"
    info "rarely type it again. A stolen key file is useless without it."
    if $CAN_PROMPT && ! $ASSUME_YES; then
      ssh-keygen -t ed25519 -f "$KEY" < /dev/tty > /dev/tty 2>&1 || die "ssh-keygen failed"
    else
      ssh-keygen -t ed25519 -f "$KEY" -N "" -q || die "ssh-keygen failed"
      warn "Non-interactive: key created WITHOUT passphrase — regenerate with one"
      warn "when convenient: ssh-keygen -p -f $KEY"
    fi
    ok "Keypair created"
  fi
  if [[ "$OSTYPE" == darwin* ]]; then
    ssh-add --apple-use-keychain "$KEY" 2>/dev/null || ssh-add "$KEY" 2>/dev/null || true
    if ! grep -q "UseKeychain" "$HOME/.ssh/config" 2>/dev/null; then
      printf 'Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile %s
' "$KEY" >> "$HOME/.ssh/config"
      chmod 600 "$HOME/.ssh/config"
      ok "Keychain integration configured"
    fi
  fi
  echo ""
  echo -e "${BOLD}Your PUBLIC key (safe to share — this is what nodes receive):${NC}"
  echo -e "${CYAN}$(cat "$KEY.pub")${NC}"
  echo ""
  echo "  Recommended: add it to GitHub (github.com → Settings → SSH keys)."
  echo "  Then every node can fetch it with the 'GitHub username' option."
  if ask_yn "Install Tailscale client on this machine? (reach nodes from anywhere)" n; then
    if [[ "$OSTYPE" == darwin* ]]; then
      command -v brew &>/dev/null && brew install --cask tailscale 2>/dev/null || warn "Install from tailscale.com"
      echo "  Open the Tailscale app and log in."
    else
      info "Installer fetched with curl | sh from tailscale.com"
      curl -fsSL --max-time 60 https://tailscale.com/install.sh | sh 2>/dev/null || warn "Install failed"
      sudo tailscale up 2>/dev/null || info "Run later: sudo tailscale up"
    fi
  fi
  hdr "Checklist block — MAIN machine"
  echo -e "    Role:            MAIN (client)"
  echo -e "    Key fingerprint: $(ssh-keygen -lf "$KEY.pub" 2>/dev/null | awk '{print $2}')"
  echo -e "    Key comment:     $(awk '{print $NF}' "$KEY.pub")"
  echo -e "    ${DIM}Nothing secret to note. RustDesk on this machine is just the"
  echo -e "    client app — install when needed, no setup.${NC}"
  echo ""
  ok "Main machine done."
  # ── §B4: the LAST thing on screen is the literal next command ──────────────
  echo ""
  echo -e "${GREEN}${BOLD}▶ NEXT — on each always-on NODE machine, run:${NC}"
  echo -e "     ${CYAN}${BOLD}bash ai-memory-remote.sh${NC}"
  echo ""
  exit 0
fi

# ── NODE role from here on ────────────────────────────────────────────────────
info "sudo is needed for: SSH service, sshd config, power settings."
# Accept already-available sudo (cached timestamp or NOPASSWD) without forcing a
# prompt that aborts when sudo can't read one; only prompt interactively if able.
if sudo -n true 2>/dev/null; then
  ok "sudo access already available (cached or passwordless)"
else
  sudo -v || die "sudo required."
fi
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
      apt)    sudo apt-get -o DPkg::Lock::Timeout=300 update -qq 2>/dev/null || true; sudo apt-get -o DPkg::Lock::Timeout=300 install -y -qq openssh-server ;;
      dnf)    sudo dnf install -y -q openssh-server ;;
      pacman) sudo pacman -S --noconfirm --needed openssh ;;
      *)      die "No supported package manager found" ;;
    esac
    sudo systemctl enable --now ssh 2>/dev/null || sudo systemctl enable --now sshd 2>/dev/null
    # If the ufw firewall is active it will block port 22 — open it
    if command -v ufw &>/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
      sudo ufw allow ssh >/dev/null 2>&1 && ok "ufw: SSH allowed through the firewall"
    fi
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
  read -r choice < /dev/tty || choice=""
  case "$choice" in
    1)
      echo -e "${BOLD}GitHub username:${NC}" > /dev/tty
      read -r ghuser < /dev/tty || ghuser=""
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
      read -r pasted < /dev/tty || pasted=""
      [[ -n "$pasted" ]] && add_key "$pasted"
      ;;
    3)
      echo -e "${BOLD}Path to the .pub file:${NC}" > /dev/tty
      read -r kpath < /dev/tty || kpath=""
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
    # sshd is FIRST-MATCH-WINS and reads sshd_config.d/*.conf alphabetically, so a
    # distro drop-in like 50-cloud-init.conf (PasswordAuthentication yes) beats a
    # 99- file. We therefore sort FIRST (00-) to win, fall back to the main config
    # when there is no Include, and ALWAYS verify the EFFECTIVE setting with
    # `sshd -T` instead of trusting that the file took effect.
    SSHD_DIR="/etc/ssh/sshd_config.d"
    SSHD_DROPIN="$SSHD_DIR/00-ai-memory-hardening.conf"
    if sudo grep -qiE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config 2>/dev/null; then
      sudo mkdir -p "$SSHD_DIR" 2>/dev/null || true
      printf '# ai-memory: sorts before distro drop-ins (sshd uses the first match)\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n' | sudo tee "$SSHD_DROPIN" >/dev/null
      sudo rm -f "$SSHD_DIR/99-ai-memory.conf" 2>/dev/null || true   # drop the old-named file from earlier versions
    else
      # No drop-in Include (e.g. stock Arch) — a drop-in would be ignored.
      warn "sshd_config has no drop-in Include — writing into the main config instead"
      SSHD_DROPIN="/etc/ssh/sshd_config"
      sudo sed -i -E 's/^[[:space:]]*(PasswordAuthentication|KbdInteractiveAuthentication)[[:space:]].*/# &  (superseded by ai-memory)/I' /etc/ssh/sshd_config 2>/dev/null || true
      printf '\n# ai-memory hardening\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n' | sudo tee -a /etc/ssh/sshd_config >/dev/null
    fi
    if ! sudo sshd -t 2>/dev/null; then
      warn "sshd config test failed — NOT restarting. Password login left ON; fix sshd_config first."
    else
      if [[ "$OS" == "macos" ]]; then
        sudo launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true
      else
        sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd 2>/dev/null || true
      fi
      EFF="$(sudo sshd -T 2>/dev/null | awk '$1=="passwordauthentication"{print $2}')"
      if [[ "$EFF" == "no" ]]; then
        ok "Password login disabled and VERIFIED (sshd -T: passwordauthentication no) — $SSHD_DROPIN"
        warn "Keep your key safe — it is now the only way in over SSH"
      else
        warn "Tried to disable password login, but sshd still reports passwordauthentication=${EFF:-unknown}."
        warn "Password login is STILL ON (so you are not locked out). A higher-priority setting overrides ours."
        warn "Inspect: sudo sshd -T | grep -i passwordauthentication   and the files in $SSHD_DIR"
      fi
    fi
  else
    info "Password login kept (you can re-run this script later)"
  fi
else
  info "No key installed — skipping hardening (password login stays on)"
fi

# ═════════════════════════════════════════════════════════════════════════════
hdr "4/6  Remote networking — analysis, then your choice"
# ═════════════════════════════════════════════════════════════════════════════

# ── Network analysis (facts before recommendation) ───────────────────────────
info "Checking how this machine is reachable..."
PUB4="$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || echo '')"
PUB6="$(curl -fsS --max-time 8 -6 https://api64.ipify.org 2>/dev/null || echo '')"
[[ "$PUB6" == "$PUB4" ]] && PUB6=""   # api64 falls back to v4; ignore if same
IS_CGNAT=false
case "$PUB4" in
  100.6[4-9].*|100.7[0-9].*|100.8[0-9].*|100.9[0-9].*|100.1[0-1][0-9].*|100.12[0-7].*) IS_CGNAT=true ;;
esac
RDNS=""
[[ -n "$PUB4" ]] && command -v dig &>/dev/null && RDNS="$(dig +short -x "$PUB4" 2>/dev/null | head -1)"
LOOKS_DYNAMIC=false
echo "$RDNS" | grep -qiE 'dyn|dhcp|pool|cust|client|dsl|cable|broadband' && LOOKS_DYNAMIC=true

echo ""
echo -e "  Public IPv4:  ${BOLD}${PUB4:-not detected}${NC}$( $IS_CGNAT && echo '  ⚠ CGNAT (carrier-NAT)' )"
[[ -n "$PUB6" ]] && echo -e "  Public IPv6:  ${BOLD}$PUB6${NC}  (often a stable prefix — may avoid DDNS)"
[[ -n "$RDNS" ]] && echo -e "  Reverse DNS:  ${DIM}$RDNS${NC}$( $LOOKS_DYNAMIC && echo '  (looks dynamic)' )"

# Optional: user already has a domain/endpoint pointing home
USER_DOMAIN=""
if $CAN_PROMPT && ! $ASSUME_YES; then
  echo -e "${BOLD}Already have a domain pointing home (e.g. vpn.example.org)? Enter it, or leave blank:${NC}" > /dev/tty
  read -r USER_DOMAIN < /dev/tty || USER_DOMAIN=""
  if [[ -n "$USER_DOMAIN" ]] && command -v dig &>/dev/null; then
    RESOLVED="$(dig +short "$USER_DOMAIN" 2>/dev/null | tail -1)"
    if [[ -n "$RESOLVED" ]]; then
      echo -e "  $USER_DOMAIN → ${BOLD}$RESOLVED${NC}$( [[ "$RESOLVED" == "$PUB4" ]] && echo '  ✓ matches this network' || echo '  ⚠ does not match current IP' )"
    else
      warn "$USER_DOMAIN does not resolve yet"
    fi
  fi
fi

# ── Recommendation logic ──────────────────────────────────────────────────────
if $IS_CGNAT; then
  REC="tailscale"
  REC_WHY="you are behind carrier-NAT — a home WireGuard port cannot be reached directly"
elif [[ -n "$USER_DOMAIN" ]]; then
  REC="wg-domain"; REC_WHY="you have a domain and a reachable public IP — fully local works"
elif [[ -n "$PUB4" ]] && ! $LOOKS_DYNAMIC; then
  REC="wg-ip"; REC_WHY="you have a public, seemingly static IP"
elif [[ -n "$PUB4" ]]; then
  REC="wg-ddns"; REC_WHY="public IP but possibly dynamic — a name that follows your IP helps"
else
  REC="tailscale"; REC_WHY="no reachable public IP detected"
fi

star() { [[ "$1" == "$REC" ]] && echo "  ${GREEN}${BOLD}★ RECOMMENDED${NC} — $REC_WHY" || echo ""; }

echo ""
echo -e "${BOLD}Remote access options — all available, recommendation marked:${NC}"
echo ""
echo -e "  1) WireGuard, fully local$([[ "$REC" == wg-* ]] && echo "$(star "$REC")")"
echo -e "       ${DIM}+ nothing leaves your control   − needs a router port + an outside test${NC}"
echo -e "  2) WireGuard + Cloudflare DNS updater (if you own a domain on Cloudflare)"
echo -e "       ${DIM}+ survives IP changes, still all yours   − needs a scoped API token${NC}"
echo -e "  3) Tailscale$([[ "$REC" == tailscale ]] && echo "$(star tailscale)")"
echo -e "       ${DIM}+ zero-config, beats CGNAT   − cloud directory; login (GitHub/Apple/Passkey/your own OIDC — not only Google)${NC}"
echo -e "  4) Skip remote networking"
echo ""

NETCHOICE=""
if $CAN_PROMPT && ! $ASSUME_YES; then
  echo -e "${BOLD}Choice [1-4]:${NC}" > /dev/tty
  read -r NETCHOICE < /dev/tty || NETCHOICE=""
else
  info "Non-interactive — skipping remote networking (run again interactively to set it up)"
  NETCHOICE="4"
fi

setup_wireguard() {  # $1 = endpoint (domain or IP), may be empty
  local endpoint="$1"
  if ! command -v wg &>/dev/null; then
    info "Installing WireGuard tools..."
    case "$OS-$PKG" in
      macos-*)      brew install wireguard-tools 2>/dev/null ;;
      linux-apt)    sudo apt-get -o DPkg::Lock::Timeout=300 update -qq 2>/dev/null || true; sudo apt-get -o DPkg::Lock::Timeout=300 install -y -qq wireguard-tools ;;
      linux-dnf)    sudo dnf install -y -q wireguard-tools ;;
      linux-pacman) sudo pacman -S --noconfirm --needed wireguard-tools ;;
    esac
  fi
  command -v wg &>/dev/null || { warn "wireguard-tools missing — install manually"; return 1; }

  local WGDIR="$HOME/.config/wireguard"
  mkdir -p "$WGDIR"; chmod 700 "$WGDIR"
  # This NODE becomes the hub. Generate its keypair (private stays here).
  if [[ ! -f "$WGDIR/hub_private.key" ]]; then
    (umask 077; wg genkey > "$WGDIR/hub_private.key")
    wg pubkey < "$WGDIR/hub_private.key" > "$WGDIR/hub_public.key"
    ok "Hub keypair created (private key never leaves this machine)"
  else
    skip "Hub keypair"
  fi
  local HUB_PUB; HUB_PUB="$(cat "$WGDIR/hub_public.key")"
  local HUB_PRIV_REF="$WGDIR/hub_private.key"

  # Client (your MAIN machine / phone) keypair — generated here for convenience,
  # delivered via QR; the client's private key is shown once, not stored by us.
  local CLI_PRIV CLI_PUB
  CLI_PRIV="$(wg genkey)"; CLI_PUB="$(printf '%s' "$CLI_PRIV" | wg pubkey)"

  # Hub config: split tunnel (only the home LAN routes through the tunnel)
  local LAN_CIDR; LAN_CIDR="$(ip -o -f inet addr show 2>/dev/null | awk '/scope global/{print $4; exit}')"
  LAN_CIDR="${LAN_CIDR:-192.168.1.0/24}"
  local HUB_CONF="$WGDIR/wg0.conf"
  if [[ ! -f "$HUB_CONF" ]]; then
    cat > "$HUB_CONF" <<WG
[Interface]
Address = 10.99.0.1/24
ListenPort = 51820
PostUp = sysctl -w net.ipv4.ip_forward=1
# PrivateKey is read from: $HUB_PRIV_REF (kept out of this file on purpose)

[Peer]
# MAIN / client
PublicKey = $CLI_PUB
AllowedIPs = 10.99.0.2/32
WG
    chmod 600 "$HUB_CONF"
    ok "Hub config written: $HUB_CONF"
  else
    info "Hub config exists — leaving it (add peers manually or re-create)"
  fi

  # Client profile (split tunnel) — shown as QR for phones, text for laptops
  local EP="${endpoint:-${PUB4:-YOUR_PUBLIC_IP}}"
  local CLIENT_PROFILE
  CLIENT_PROFILE="$(cat <<WG
[Interface]
PrivateKey = $CLI_PRIV
Address = 10.99.0.2/24

[Peer]
PublicKey = $HUB_PUB
Endpoint = ${EP}:51820
AllowedIPs = 10.99.0.0/24, ${LAN_CIDR}
PersistentKeepalive = 25
WG
)"
  echo ""
  echo -e "${BOLD}Client profile (split tunnel — only home traffic goes through it):${NC}"
  echo -e "${DIM}Scan on a phone, or save as wg0.conf on a laptop. Shown once.${NC}"
  echo ""
  if command -v qrencode &>/dev/null; then
    echo "$CLIENT_PROFILE" | qrencode -t ansiutf8
  else
    info "(install 'qrencode' to show a scannable QR; profile printed below)"
    echo "$CLIENT_PROFILE"
  fi
  echo ""
  warn "This profile contains the client's PRIVATE key — capture it now, it is not saved."
  echo ""
  echo -e "${YELLOW}${BOLD}Router step (manual):${NC} forward ${BOLD}UDP 51820${NC} to this hub"
  echo -e "  ($IDENT_HINT). See the checklist for router examples."
  echo -e "${BOLD}Verify from OUTSIDE${NC} (phone hotspot) — a port-checker website will"
  echo -e "wrongly say 'closed' because WireGuard stays silent by design."
  # start the hub
  if [[ "$OS" == "linux" ]] && command -v systemctl &>/dev/null; then
    sudo cp "$HUB_CONF" /etc/wireguard/wg0.conf 2>/dev/null &&     sudo sed -i "/PrivateKey/d" /etc/wireguard/wg0.conf 2>/dev/null
    # inject private key into the system copy only
    sudo sed -i "/^\[Interface\]/a PrivateKey = $(cat "$HUB_PRIV_REF")" /etc/wireguard/wg0.conf 2>/dev/null
    sudo chmod 600 /etc/wireguard/wg0.conf
    sudo systemctl enable --now wg-quick@wg0 2>/dev/null && ok "WireGuard hub running (wg-quick@wg0)"       || warn "Start manually: sudo wg-quick up wg0"
    if command -v ufw &>/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
      sudo ufw allow 51820/udp >/dev/null 2>&1 && ok "ufw: UDP 51820 opened"
    fi
  else
    info "Start the hub with: sudo wg-quick up $HUB_CONF"
  fi
}

setup_cloudflare_ddns() {
  local domain="$1"
  echo ""
  warn "The DNS record for $domain must be 'DNS only' (GREY cloud) in Cloudflare —"
  warn "the orange proxy does NOT carry WireGuard's UDP. This is a common trap."
  echo ""
  echo "  Create a scoped API token: Cloudflare dashboard → My Profile → API Tokens"
  echo "  → Create → permissions: Zone:DNS:Edit, limited to this zone only."
  if $CAN_PROMPT && ! $ASSUME_YES; then
    echo -e "${BOLD}Paste the API token (stored chmod 600, never logged):${NC}" > /dev/tty
    read -r -s CF_TOKEN < /dev/tty; echo ""
    if [[ -n "$CF_TOKEN" ]]; then
      local CFDIR="$HOME/.config/ai-memory"; mkdir -p "$CFDIR"; chmod 700 "$CFDIR"
      printf 'CF_API_TOKEN=%s
CF_RECORD=%s
' "$CF_TOKEN" "$domain" > "$CFDIR/cloudflare-ddns.env"
      chmod 600 "$CFDIR/cloudflare-ddns.env"
      cat > "$CFDIR/cloudflare-ddns.sh" <<'DDNS'
#!/usr/bin/env bash
# Updates a Cloudflare A record to this network's current public IP.
set -euo pipefail
source "$(dirname "$0")/cloudflare-ddns.env"
IP="$(curl -fsS https://api.ipify.org)"
ZONE="$(printf '%s' "$CF_RECORD" | awk -F. '{print $(NF-1)"."$NF}')"
api() { curl -fsS -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" "$@"; }
ZID="$(api "https://api.cloudflare.com/client/v4/zones?name=$ZONE" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"][0]["id"])')"
REC="$(api "https://api.cloudflare.com/client/v4/zones/$ZID/dns_records?name=$CF_RECORD&type=A")"
RID="$(printf '%s' "$REC" | python3 -c 'import sys,json;r=json.load(sys.stdin)["result"];print(r[0]["id"] if r else "")')"
BODY="$(printf '{"type":"A","name":"%s","content":"%s","ttl":120,"proxied":false}' "$CF_RECORD" "$IP")"
if [[ -n "$RID" ]]; then
  api -X PUT "https://api.cloudflare.com/client/v4/zones/$ZID/dns_records/$RID" --data "$BODY" >/dev/null
else
  api -X POST "https://api.cloudflare.com/client/v4/zones/$ZID/dns_records" --data "$BODY" >/dev/null
fi
echo "Updated $CF_RECORD → $IP"
DDNS
      chmod +x "$CFDIR/cloudflare-ddns.sh"
      "$CFDIR/cloudflare-ddns.sh" 2>/dev/null && ok "Cloudflare record updated to current IP"         || warn "First update failed — check token/zone; script saved at $CFDIR/cloudflare-ddns.sh"
      # schedule
      if [[ "$OS" == "linux" ]] && command -v systemctl &>/dev/null; then
        (crontab -l 2>/dev/null; echo "*/15 * * * * $CFDIR/cloudflare-ddns.sh >/dev/null 2>&1") | crontab - 2>/dev/null           && ok "Scheduled every 15 min (cron)"
      elif [[ "$OS" == "macos" ]]; then
        info "To run it regularly, add a launchd job (see Tips) — or it runs on demand."
      fi
    fi
  fi
}

IDENT_HINT="this machine"
case "$NETCHOICE" in
  1) setup_wireguard "$USER_DOMAIN" ;;
  2) setup_wireguard "$USER_DOMAIN"; setup_cloudflare_ddns "${USER_DOMAIN:-}" ;;
  3)
    if command -v tailscale &>/dev/null && tailscale status &>/dev/null 2>&1; then
      skip "Tailscale (connected)"
    else
      if [[ "$OS" == "macos" ]]; then
        command -v brew &>/dev/null && brew install --cask tailscale 2>/dev/null || warn "Install from tailscale.com"
        pause_for "  Open ${BOLD}Tailscale${NC}, log in (GitHub/Apple/Passkey/your own OIDC — not only Google),
  and approve this machine."
      else
        info "Installer fetched with curl | sh from tailscale.com — review at https://tailscale.com/install.sh"
        ask_yn "Proceed?" y && curl -fsSL --max-time 60 https://tailscale.com/install.sh | sh 2>/dev/null || warn "skipped/failed"
        $CAN_PROMPT && ! $ASSUME_YES && sudo tailscale up 2>/dev/null || info "Run later: sudo tailscale up"
      fi
      tailscale status &>/dev/null 2>&1 && ok "Tailscale connected" || info "Tailscale not connected yet"
    fi
    ;;
  *) info "Remote networking skipped (WireGuard is the recommended local path — re-run to set up)" ;;
esac

# ═════════════════════════════════════════════════════════════════════════════
hdr "5/6  RustDesk (optional — graphical access, e.g. for macOS popups)"
# ═════════════════════════════════════════════════════════════════════════════
if ask_yn "Install RustDesk?" n; then
  if [[ "$OS" == "macos" ]]; then
    command -v brew &>/dev/null || die "Homebrew required — run ai-memory-setup.sh first"
    brew install --cask rustdesk 2>/dev/null && ok "RustDesk installed" || warn "Install failed — get it from rustdesk.com"
    pause_for "  Open ${BOLD}RustDesk${NC} once. macOS may first say it was downloaded\n  from the internet — click ${BOLD}Open${NC}. Then approve:\n    System Settings → Privacy & Security → ${BOLD}Screen Recording${NC} → RustDesk\n    System Settings → Privacy & Security → ${BOLD}Accessibility${NC} → RustDesk\n  Then, in RustDesk: Settings → Security → set a ${BOLD}permanent password${NC}\n  (store it in your password manager — this script never touches it).\n  Newer macOS may also ask about ${BOLD}Local Network${NC} access — click Allow.\n  Note the ${BOLD}RustDesk ID${NC} shown in the main window for your checklist."
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
echo -e "    Role:       ${BOLD}NODE${NC}"
echo -e "    Hostname:   ${BOLD}$IDENT_HOST${NC}"
echo -e "    Local IP:   ${BOLD}$IDENT_IP${NC}"
echo -e "    SSH line:   ${BOLD}ssh $REMOTE_USER@$IDENT_IP${NC}"
if command -v tailscale &>/dev/null; then
  TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"
  [[ -n "$TS_IP" ]] && echo -e "    Tailscale:  ${BOLD}$TS_IP${NC}  (works from anywhere)"
fi
echo -e "    RustDesk ID: see the RustDesk main window"
echo ""
ok "Remote NODE configured — this completes the setup chain."
# ── §B4: end on the one mandatory action, not on "done" ──────────────────────
echo ""
echo -e "${GREEN}${BOLD}▶ NEXT (mandatory for nodes) — the pull-the-plug test:${NC}"
echo "     Shut down → pull the power cord → wait 1 min → plug back in."
echo "     The machine must boot, log in, and be reachable over SSH by itself."
echo -e "     ${DIM}If it does not power on: see the checklist (BIOS setting on PCs;"
echo -e "     on Apple Silicon minis autorestart is known to be unreliable).${NC}"
echo ""
