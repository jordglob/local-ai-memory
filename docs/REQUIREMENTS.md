# AI Memory Stack — Requirements Specification v1.33

<!-- v1.33 (2026-06-18): §4.3.1 KEYSTONE first slice BUILT + PROVEN end-to-end on
     the Mac (configure v4.8). The cwd-independent HANDOVER ships: configure writes
     an orientation block (absolute vault paths + search-don't-guess + "call the
     tool, don't describe it") into ~/.hermes/SOUL.md, the one file Hermes injects
     into EVERY system prompt regardless of launch dir/door. TWO live diagnoses
     CORRECT earlier hypotheses: (1) TERMINAL_CWD is NOT ignored in this Hermes —
     system_prompt.py + tool_executor.py both read `os.getenv("TERMINAL_CWD") or
     os.getcwd()`, so it IS a real lever (old §4.3 note was outdated); the dashboard
     was blind only because it was launched from the install dir, loading the dev
     AGENTS.md. (2) tool_use_enforcement is NOT the refusal lever — "qwen" is in
     TOOL_USE_ENFORCEMENT_MODELS so guidance WAS injected; the refusal is the wrong
     context file + a weak model. PROOF (same wrong cwd $HOME, same vault, same
     handover, only the model changed): qwen3.5 → 0 tool calls (hallucinated grep,
     twice); claude-haiku-4.5 via OpenRouter → 6 REAL tool calls, ran the absolute-
     path grep, cited the real imported OpenClaw files. So the handover is sound AND
     the model floor (§4.2) is decisive, not optional. SOUL.md is the global-
     instruction home for handover work. Still TODO (next bundles): model-floor
     warning in configure, ingest import INDEX, `doctor` per-door verifier. -->


<!-- v1.32 (2026-06-18): §6 next-phase plan added (KEYSTONE-FIRST, decided with
     user) + §5.4 gains the re-run/idempotency rule ("the first run lies", from
     the set_env re-run crash). §4.3.1 point 8: dashboard agent refused its own
     tools — reachability fix must verify a REAL tool call, not just rooting. -->


<!-- v1.31 (2026-06-18): §4.3.1 added — TOP PRIORITY: reachability must hold from
     EVERY entry point (shell/dashboard/TUI/gateway), cwd-independent. Found by
     live macOS dashboard use: shell hermes reaches the vault, the web dashboard
     chat is memory-blind. This is the project's core promise; ships before new
     features. Also: macOS hardening round — configure pipefail crash (line 386)
     + 6 pipefail siblings + 3 read EOF-guards fixed (configure live-proven on
     Apple Silicon; remote.sh fixes static-only pending the deferred remote round). -->


Status: agreed baseline for the next build round (June 2026).
v1.30 (CC): §4.11 BUILT — `ai-memory-uninstall.sh` v1.0 (pkg v12), the 5th family
script: EXPORT-FIRST (vault → tar.gz + a secret-free migration manifest) and
DRY-RUN by default. Export path LIVE-verified on this box; destructive removal
render-but-unproven (held for a hands-on look-and-feel run). One spec deviation,
deliberate: the Claude-Desktop reversal SURGICALLY removes only our `obsidian-vault`
MCP server (backup saved) instead of restoring a stale `.bak` — a stale restore
could clobber unrelated servers the user added since. Also RECORDED (not built):
§4.12 hardware-migration / vault-portability (the manifest is its first increment;
restore lands in setup) and §4.13 guided/expert verbosity mode (explicit `--expert`
only, default guided; the "state the honest reason when you hand the user a real
command" rule). New zip-naming convention: a `<main-build-event>` suffix on the
bundle filename.
v1.29 (CC): §4.11 added — `ai-memory-uninstall.sh`, a 5th family script (clean
reversal with EXPORT-FIRST of the vault). User-requested as the NEXT BUILD so the
real scripts can be run + reset between manual look-and-feel passes. Backlog only,
not yet built; core-stack reversal first, remote layer as increment 2.
v1.28 (CC): §2.9 FIRST SLICE BUILT — the reassurance layer's top-priority items
(safe-to-interrupt line + what/why before a slow step + live-log hint), realized
as a `calm()` helper in setup.sh printed BEFORE each previously-silent download
(Ollama, Node.js, mcpvault). Pairs with the existing interrupt trap (which made
the same promise only AFTER a Ctrl+C). Hermes already had a time estimate + source
so it was left as-is. setup v8.11, package v11. STILL OPEN in §2.9: bandwidth probe
(needs new curl+timing code), two-stage download-size estimate in configure (needs
a model-size lookup), closing summary with personality, hardware rating, anchoring
comparisons. Render-verified under set -e on this box.
v1.27 (CC): §4.10 §B4 BUILT — every chain script now ENDS on the literal next
command, printed AFTER identity/tips as a bold "▶ NEXT" footer. setup → configure
(open a new terminal), configure → ingest, ingest → "talk to your memory: hermes
chat", remote MAIN → run on each NODE, remote NODE → ends on the mandatory pull-
the-plug test (was buried above "Remote setup done"). setup v8.10 / configure v4.5
/ ingest v2.9 / remote v2.6, package v10. Render-verified on this box; §B5 (more
configure live coverage) still deferred to the macOS round.
v1.26 (CC): §4.10 added from user feedback — §B4: the closing screen must END on
the explicit next action (setup buries the configure pointer under identity/tips,
so a beginner lands at the terminal confused); §B5: configure.sh is the thinnest-
tested script — fold a thorough live-test into the macOS round. UX/clarity
backlog, not yet built.
v1.25 (CC): §2.11 refined — the "self-deciding gateway" decision policy was an
v1.25 (CC): §2.11 refined — the "self-deciding gateway" decision policy was an
open gap (named the chain, never said who/when). Now pinned: Level A = rule-based
fallback (deterministic triggers: backend error / context overflow / rate-limit /
manual tag), user owns the rules + gateway executes them — THE COMMITTED, medium-
effort target. Level B = semantic/quality-aware per-request routing = OUT OF
SCOPE (agent territory, open problem). Delivered reality restated: configure
picks ONE model, no runtime decider yet.
v1.24 (CC): remote.sh R2+R3 CLOSED OUT. Pull-the-plug test PASSED (abrupt
v1.24 (CC): remote.sh R2+R3 CLOSED OUT. Pull-the-plug test PASSED (abrupt
SIGKILL power-cut + cold boot: VM recovered unattended; pwauth=no, linger=yes,
sleep masked, wg-quick@wg0 auto-started — all persisted). F1 proven on BOTH
paths: Path A (drop-in) on Ubuntu + Arch; Path B (no-Include -> main config)
validated on Arch (selector picks B, sed+append, sshd -t VALID, sshd -T flipped
yes->no, key login intact). Findings: (a) modern Arch cloud images now ship the
`Include` line, so the no-Include case is rare (fallback still correct); (b) the
Ollama install step's silence + the autostart [Y/n] prompt are easily mistaken
for a hang (WSL live) — reinforces §2.9 progress-visibility. Two minor items
remain OPEN, low prio: F3 sed-argv ps-exposure; F2 full-live (needs a CF token).
Tooling note: driving the interactive script through a TCG pty (ssh -tt / script)
is flaky — deterministic command-level tests were used to validate Path B.
v1.23 (CC): R3 FIX BUNDLE built + re-tested on the QEMU VM (package v9; remote
v1.23 (CC): R3 FIX BUNDLE built + re-tested on the QEMU VM (package v9; remote
v2.5, setup v8.9). F1 FIXED — hardening now writes `00-ai-memory-hardening.conf`
(beats cloud-init's `50-` under sshd first-match-wins), falls back to the main
config when there is no drop-in Include, runs `sshd -t`, and VERIFIES the
effective setting with `sshd -T` before claiming success (live: sshd -T flipped
yes->no). F5 FIXED — CAN_PROMPT now probes by opening /dev/tty (live: a
non-interactive NODE run completes instead of dying at `>/dev/tty`); same fix in
setup.sh. F6 FIXED — `grep -q "Status: active"` (live: inactive ufw correctly
skipped). F2 FIXED — DDNS JSON built with printf (valid JSON; full live needs a
CF token). F3 cleared earlier; only its minor sed-argv residual remains open.
v1.22 (CC): remote.sh R2 LIVE-TESTED on a local QEMU VM (Ubuntu 24.04 cloud
v1.22 (CC): remote.sh R2 LIVE-TESTED on a local QEMU VM (Ubuntu 24.04 cloud
image). §4.8 "R2 LIVE RESULTS" added. F1 CONFIRMED and worse than predicted —
sshd first-match-wins means cloud-init's 50-cloud-init.conf (PasswordAuth yes)
beats our 99-drop-in even WITH Include present, so hardening silently no-ops on
the most common headless-node OS while reporting success. F6 NEW: `grep -q
active` matches `inactive` (remote.sh:499) -> ufw rule + success message on an
OFF firewall. F3 cleared (on-disk secret separation is correct). F2/F5 stand.
PASSED: key-append, network analysis, WireGuard bring-up, secret separation.
v1.21 (CC): remote.sh live-test round PLANNED (not yet run). §4.8 expanded with
the staging plan (acceptable target = snapshot VM / console-backed sacrificial
node; low-blast-radius-first sequence; machine-checked acceptance; rehearsed
recovery) and four code-review findings F1-F4 (self-attested+possibly-ignored
sshd hardening; broken Cloudflare-DDNS JSON; WG private key in a sed argv;
firewall claim milder than feared). §4.9 added: NAT-friendly fallback ladder
(WireGuard -> Tailscale -> Cloudflare Tunnel; NEVER a hand-rolled relay). §3:
scope guard for the upcoming, unrelated Mac project. Nothing in remote.sh has
been run live or changed this round.
v1.20 (CC): §4.55 `--scan-report` now ALSO live-verified on real WSL2 (Windows-
side export mapped via /mnt/c, decoy=unknown, 0 imported) — closes the
report-mode-on-WSL gap noted in v1.19.
v1.19 (CC): §4.55 `--scan-report` BUILT (ingest v2.8) — first increment of the
§4.5 hybrid decision; maps recognized + unknown candidates to a vault bridge
file, imports nothing, agent prompt in docs/collect-with-agent.md (§4.7).
v1.18 (CC): §4.5 ingest-architecture question RESOLVED — DECIDED hybrid
(deterministic script first, agent fallback), realized via §4.55 `--scan-report`;
agent-prompt kept in docs (§4.7), never embedded. See §4.5 "DECIDED".
v1.17 (CC): §4.1 WSL /mnt/c scan path LIVE-VERIFIED on real WSL2 (was
written-but-unproven) — detection fires, Windows-side export discovered +
imported (102 convs), idempotent. ingest v2.7 fixes BUG-1 (DefaultAppPool
slipped the skip set; now case-insensitive + system profiles added) and hardens
BUG-2 (WSL gate now also checks osrelease + $WSL_DISTRO_NAME). See §4.1.
v1.16 (CC, package v6): §4.1 + §4.05 + §4.35 BUILT. configure v4.4 (local
dual-context ollama_num_ctx + atomic write + read-back verify), setup v8.8
(apt lock-timeout wrapper on every apt call, installs unzip+zstd), ingest v2.6
(WSL detect + offer Windows /mnt/c Downloads), remote v2.4 (apt lock-timeout),
README git-clone-first + Python-unzip fallback + WSL note. Live-verified on the
non-WSL box (dual-context write+verify, dep install via apt_get, WSL no-op);
the WSL /mnt/c scan path is written-but-unproven (no WSL hardware this round).
v1.15 adds: §4.35 local-model dual-context (context_length AND ollama_num_ctx
must both clear 64K) + confirmed configure-never-wrote-config.yaml bug (WSL live,
first capable local model). v1.14 added: §4.05 bootstrap/distribution (git clone primary; Python unzip
fallback; never assume unzip to get scripts out). v1.13 added: §4.1 WSL as first-class scenario (missing deps unzip/zstd, apt-lock
wait, Windows-side /mnt/c data discovery, vault-in-WSL). v1.12 added: §4.2 model-capability floor for memory/tool-use (a too-weak model
guesses filenames instead of searching — warn on weak model choice). v1.11 added: §4.3 CRITICAL import->reachable gap (core-promise bug: ingest
fills the vault but plain `hermes` searches cwd, not the vault — found on X230
live). v1.10 added: §4.55 scan-to-report option (map messy data, agent acts on a
bridge file). v1.9 added: ingest backlog §4.4, GitHub-sync local-first design §4.6,
agent-assisted-ingest coupling tension §4.7. v1.8 added: core design principle §4.5 (deterministic work = script, messy
reality = agent; ingest may need agent/hybrid redesign). v1.7 added: build workflow + pattern-hunt discipline (§5), born from the X230
live run. v1.6 added: LiteLLM self-hosted gateway as sovereign routing option (§2.11),
plus X230 live-run findings (cloud-only path, context_length=model max,
exit-status-1 fix, guided-mode clarity fixes). v1.5 added: reassurance & feedback layer (§2.9) — bandwidth probe (default,
--no-speedtest), data/time estimates, safe-to-interrupt lines, closing summary.
v1.4 added: network-analysis + WireGuard-first remote choice, Cloudflare
DDNS updater, AI-workflow tools in Tips. v1.3 added: machine-role model (MAIN/NODE/SOLO) + key policy in §2.7.
v1.2 added: power-outage recovery chain + pull-the-plug test, manual
power-settings step. v1.1 added: remote-access script (§2.7), family conventions (§2.8),
checklist v3 scope (§2.5), stay-awake + self-install in setup (§2.1).
Everything in this document was settled in design discussion; items marked
**[OPEN]** still need a decision before or during the build.

---

## 1. Vision

A local-first system that consolidates a person's scattered AI conversations
into one vault they own, and runs a persistent local agent (Hermes) on top of
it — installable on a brand-new machine by a non-expert, useful to others, not
just the original author.

Guiding principles (apply to every component):

- **Local-first.** No cloud accounts required. Cloud APIs are optional fallbacks only.
- **Agent-neutral vault.** Plain markdown on disk; survives any single tool's death.
- **Recommend, don't decide.** The system proposes (models, updates, daemons);
  the user approves. Nothing self-modifies.
- **Generic by default.** No author-specific hardware, language, workflow, or
  personal data baked in. English everywhere in built artifacts.
- **Verify against the source.** During the build: clone the repo / read the
  docs before integrating anything; sandbox-test before shipping.

---

## 2. Components

### 2.1 `ai-memory-setup.sh` (installer)

Carry over from v6.0 (already built and tested):
- Zero-prerequisite install: bootstraps Homebrew/apt/dnf, Node 22, python3,
  git, Ollama; bash 3.2 compatible; idempotent step checkpoints; cleanup trap;
  human-in-the-loop checkpoints for macOS popups; TTY/color/non-interactive
  detection; `--help`/`--version`; sudo asked once with plain-language
  explanation; never run as root; log to TMPDIR then vault; time estimates
  per platform shown at start.

Changes for next round:
- **Hermes becomes optional**: prompt (default yes) or `--no-hermes` flag.
  Note in output that the official installer (`curl | bash` from
  NousResearch) can be reviewed before running.
- **Ollama autostart becomes a question** (or `--autostart` / `--no-autostart`):
  do not silently install launchd/systemd services.
- **`resume.sh` defaults to `hermes`**, not Claude Code (which we never install).
- Remove dead `HERMES_DIR` variable and any other remnants of the old
  clone-based Hermes install.
- Add build tools for pacman (currently only apt/dnf get them).
- Final message: one tip line pointing to the Tips & Tricks page (cmux etc.),
  plus this machine's **identity block** (hostname, local IP, SSH line) for
  copying onto the checklist.
- Proxy environments: detect missing connectivity early and print
  HTTP(S)_PROXY guidance instead of a raw curl failure.
- **Stay-awake during install:** wrap long operations in `caffeinate`
  (macOS) / `systemd-inhibit` (Linux) so sleep never kills a model download.
  No permanent power changes in setup.sh.
- **Self-install to the vault:** on first run, copy all family scripts to
  `$VAULT/.tools/` and say so. All later instructions reference
  `~/Documents/ai-memory/.tools/...` — independent of where the user
  downloaded the files.

### 2.2 `ai-memory-configure.sh` (hardware → model → Hermes config)

Carry over from v2.0: hardware analysis (RAM/GPU/Apple Silicon/NVIDIA),
local model scan, model selection table, writes real Hermes config
(`~/.hermes/config.yaml`, provider `custom`, base_url
`http://localhost:11434/v1`, context_length scaled to RAM), optional API keys
to `~/.hermes/.env` (chmod 600), inventory report into the vault.

Changes:
- Soften consolidation advice: present Ollama as *an option*, point to
  `huggingface-cli delete-cache` (interactive) instead of `rm -rf` commands.
- Print a minimum/recommended hardware table when detected hardware is below
  recommended (see §4).

### 2.3 `ai-memory-ingest.sh` (multi-source history import) — major rebuild

Architecture: one parser module per source, shared markdown output format,
output to `05-AI-Sessions/<source>/`, idempotent (skip by conversation ID).
Flags: `--source <name>`, `--all`, `--list-sources`.

Sources (target: 10):

| Source | Access method | Difficulty |
|---|---|---|
| Claude.ai | Export ZIP (`conversations.json`) | done |
| Claude Code | Local JSONL `~/.claude/projects/` | done |
| ChatGPT | Export ZIP (`conversations.json`) | low |
| Codex CLI | Local session files `~/.codex/` | low |
| Gemini CLI | Local logs `~/.gemini/` | low |
| OpenClaw | Local session data `~/.openclaw/` | low–med |
| Cursor | Local SQLite (`state.vscdb`) | medium |
| Aider | `.aider.chat.history.md` per project | low |
| LM Studio / Open WebUI | Local JSON/SQLite | medium |
| Gemini (web) | Google Takeout export | medium |

All local paths above must be **verified against current tool versions during
the build** — do not trust remembered paths.

Discovery — three-tier model:
1. **Default:** registry of known per-source paths, plus a *targeted*
   Downloads scan: pattern-match known export filenames
   (`data-*.zip`, `*chatgpt*`, `takeout-*.zip`), validate contents
   (e.g. contains `conversations.json`), then offer interactively:
   "Found what looks like a Claude.ai export — import it? [Y/n]".
   Top levels only, not recursive trawling.
2. **`--scan <dir>`:** user-specified extra locations. Docs include
   cloud-sync folder examples (iCloud Drive, OneDrive) with a warning that
   scanning them may trigger cloud downloads.
3. **`--deep-scan`:** entire home directory (never whole disk / system areas),
   explicit warning + confirmation; on macOS a checkpoint guiding through the
   Full Disk Access permission if needed.

Export guides: per-service one-pagers describing the *manual* export flow
(none of the consumer services offer history APIs — document this honestly).

Optional final step: distill imported history into a `USER.md` /
`MEMORY.md` seed for `~/.hermes` so Hermes knows the user from day one.

### 2.4 Update Advisor (AGENTS.md section / scheduled Hermes task)

- Read-only by design: inventories installed components (Hermes, Ollama,
  models, these scripts, cmux), checks **primary sources only**
  (GitHub Releases, Ollama releases) for newer versions.
- Writes a short report to `00-Inbox/UPDATES.md` with proposals.
  **Never installs anything.** User approves; agent may then execute.
- Daily version check; optional weekly broader landscape scan (off by default).

### 2.5 Installation checklist PDF v3 (English)

- English master (Swedish translation possible later).
- Mac track: branch for **Apple Silicon and Intel** recovery modes.
- Generic hardware: min/recommended table (§4).
- **Passwords — warn, then respect the user's choice:** prominent warning
  (password manager first; a filled-in sheet is a complete access kit —
  lock it away, shred on disposal) followed by fields labelled
  "Password or hint (your choice — see warning)".
- **Identity block per machine:** hostname, local IP, Tailscale name,
  RustDesk ID, ready-made `ssh user@host` line. The scripts print these
  values at completion so the user copies rather than hunts.
- **Step 2.1–2.2 rewritten for absolute beginners:** files land in
  Downloads — instructions start there (`cd ~/Downloads`), include where to
  download from (repo ZIP / git clone), an `ls ai-memory-*.sh` sanity check
  before running, and the "No such file or directory = wrong folder" fix in
  the trouble box.
- FileVault/disk encryption moves to Tips & Tricks with the honest tradeoff:
  theft protection on portables vs. pre-boot lock on headless nodes.
- **Manual power settings step, early in BOTH tracks** (before scripts
  exist): disable system sleep via the GUI — Mac: System Settings →
  Energy/Lock Screen; Mint: Power Management. Teach the distinction:
  screen blanking is harmless, system sleep kills downloads and remote
  access.
- PC/node track additions: BIOS "Restore on AC Power Loss" (with key
  hints, same style as the boot-menu key), CMOS battery note for older
  PCs (dead CR2032 = BIOS forgets settings + clock drift = certificate
  errors), and a **mandatory pull-the-plug test** as the final node step.
- Tips one-liner: if your router reassigns IPs, set a DHCP reservation
  so the identity block stays true. (No UPS guidance — out of scope.)
- **Headless/SSH appendix:** enable Remote Login on macOS, Ubuntu Server
  (not Mint) for headless PCs, HDMI dummy plug, `pmset -a sleep 0`,
  always two ways in (SSH + screen sharing).
- Windows: "supported via WSL2" with the two-option instructions.
- Last page — Tips & Tricks: cmux (macOS, install *after* base setup),
  Syncthing for vault sync (never sync `~/.ssh` or `~/.hermes`),
  backups (vault + `~/.hermes`), plain WireGuard as the no-cloud
  alternative to Tailscale, troubleshooting box.

### 2.6 Distribution

- Public GitHub repo: the three scripts, checklist PDF (+ source),
  this spec, per-source export guides.
- README: what/why, minimum requirements, quick start, screenshot.
- License: **[OPEN]** MIT proposed.
- Versioned releases; parser architecture documented to invite contributions.
- Repo: `github.com/<your-username>/local-ai-memory` (publisher fills in).

### 2.7 `ai-memory-remote.sh` (remote access — role-aware, standalone)

Opt-in. Never part of setup.sh. First question: machine role.

- **MAIN** (the client you sit at): generates one ed25519 keypair per client
  machine (passphrase, macOS Keychain integration), never copies private
  keys, shows the public key + GitHub upload advice, optional Tailscale
  client. No sshd, no always-on. Prints a client checklist block
  (fingerprint — nothing secret).
- **NODE**: the flow below (SSH server, key install, hardening, optional
  Tailscale/RustDesk host, always-on power, identity block).
- **SOLO** (only computer): explains remote access is unnecessary and exits.
- Key policy: one key per client; private keys never leave their machine;
  public keys distributed via github.com/<user>.keys; revocation = remove
  one line from each node's authorized_keys.

- **SSH:** enable Remote Login (macOS) / openssh-server (Linux); install the
  user's public key (paste, file, or `https://github.com/<user>.keys`);
  offer to disable password login **only after key login is verified**.
- **Remote networking — analysis then choice:** detect public IPv4/IPv6,
  CGNAT (100.64/10), reverse-DNS dynamic-vs-static hint, and resolve a
  user-supplied domain. Present all options with the recommendation marked:
  **WireGuard fully-local is first choice** (flips to Tailscale only under
  CGNAT). WireGuard hub keypair (private key stays on the hub, never in
  wg0.conf), split-tunnel client profile delivered as QR; optional Cloudflare
  DNS updater (grey-cloud warning, Zone:DNS:Edit token in ~/.config chmod
  600). Tailscale offered for convenience/CGNAT with a note that login can be
  GitHub/Apple/Passkey/own OIDC — not only Google. Router UDP-51820 forward
  and a phone-hotspot verification are manual (checklist); port-checker sites
  warned against (WireGuard is silent by design). Full-tunnel profile and
  macOS pf-NAT deferred to backlog.
- **RustDesk:** install automatically; macOS Screen Recording/Accessibility
  approvals as checkpoints; permanent password set in the GUI, never by
  the script.
- **Node power settings (asked, never silent):** disable sleep
  (`pmset -a sleep 0` + `womp 1` on macOS; mask sleep targets on Linux
  servers), optional autologin with stated tradeoff.
- **Power-outage recovery chain (nodes):** set `pmset -a autorestart 1`
  (macOS) and `loginctl enable-linger <user>` (Linux — user services start
  at boot without login). Honest note: Apple Silicon minis are REPORTED to
  sometimes ignore autorestart even fully updated — therefore the checklist
  makes a pull-the-plug test mandatory before trusting a node. BIOS
  "Restore on AC Power" on PCs is firmware-only → checklist, not script.
- **Secrets model (hard rules):** the script creates, moves and protects
  keys but never stores, displays or invents secrets. No secrets as CLI
  arguments (shell history/process list); `read -s` for anything secret;
  the tee log must never capture a secret; the vault never contains
  secrets; warn against syncing `~/.ssh` and `~/.hermes`.
- Prints the machine's identity block (hostname, IPs, Tailscale name,
  RustDesk ID, ssh line) for the checklist.
- First session per node is physical by necessity (enable SSH, approve
  GUI permissions) — the script's job is to make it a 10-minute checklist
  and everything after 100% remote.

### 2.9 Reassurance & feedback layer (PARTIAL — first slice built) — "they thought of everything"

**Status (CC, 2026-06-17, spec v1.28):** the three top-priority items below are
BUILT in setup v8.11 via a `calm()` helper (marked ✅). The rest remain open.

Goal: a user who trusts the script does not Ctrl+C mid-download, so calm IS
stability. All of the following are messaging/feedback, not new behavior:

- **Bandwidth probe (default on, `--no-speedtest` to skip):** a small timed
  download (~5 MB) measures the link. Honest caveat printed: measured now,
  real speed varies.
- **Two-stage download estimate:** setup prints a rough total
  ("~2–3 GB tools + the model you pick later"); configure, AFTER hardware
  analysis, prints the exact figure ("your machine → qwen3:35b, 20 GB;
  at ~50 Mbit ≈ 55 min").
- **✅ Per-step "safe to interrupt" line:** every long step states
  "Safe to Ctrl+C — re-running resumes where it stopped." (We already have
  checkpoints; this just communicates them.) BUILT via `calm()`.
- **✅ "What's happening and why" before slow steps:** e.g. "Apple is
  downloading ~700 MB of developer tools, no progress shown — this is normal."
  BUILT for Ollama/Node/mcpvault (the previously-silent downloads).
- **Surface real progress:** stop hiding Ollama's own download percentage
  behind the spinner; show step counter ("step 3 of 7"). (Step counter already
  exists as `Step N/7` headers; the in-spinner percentage is still hidden.)
- **✅ Optional live log hint:** "want to watch? open another terminal:
  tail -f <log>". BUILT into `calm()`.
- **Closing summary with personality (the fun bit):** time taken, model size
  running locally (zero cloud), conversations imported + approximate word
  count ("≈ 3.2M words — about 40 novels"), all on your own disk.
- **Hardware "rating" in configure (light, honest):** top-tier vs. "works,
  but a RAM upgrade would open a lot."
- **Anchoring comparisons:** "20 GB ≈ 5 HD movies" so the wait has a felt size.

- **Context length = model's real max, not a fixed floor (X230 finding):**
  configure wrote 64000 (Hermes' minimum) but gpt-4o-mini supports 128000.
  Set context_length to the model's actual capability, clamped to Hermes'
  64K floor as the *lower* bound — never below 64K, but go higher when the
  model allows.

Priority order if time is short: safe-to-interrupt line, what/why + time,
then the closing summary (cheap, high delight). Only the bandwidth probe
needs new code (a curl + timing).

### 2.11 LiteLLM self-hosted gateway — the sovereign routing option (next build)

The lower-stack answer to "OpenRouter vs competition": don't depend on a
hosted aggregator as the front door. On capable hardware, offer LiteLLM as a
LOCAL gateway the user owns.

- **Capable hardware (e.g. Mac mini):** primary = local Ollama (open-weight,
  nothing leaves the machine). LiteLLM runs locally as the user's own gateway,
  routing local-first and spilling over to cloud providers (OpenAI / Anthropic
  / OpenRouter) only on demand. Provider keys held by the user; providers paid
  directly at list rate; no third-party proxy in the default path.
- **Weak hardware (e.g. X230):** OpenRouter (or direct provider) stays the
  simple choice — the machine cannot run a useful local model, so a hosted
  cloud path is correct there.
- configure should detect the tier and lean accordingly: sovereign-by-default
  on capable hardware, cloud-by-necessity on weak hardware.
- This is the natural evolution of the existing fallback chain
  (local -> cheap cloud -> premium): LiteLLM is simply that chain run as the
  user's own infrastructure rather than as config pointing at one aggregator.
- LiteLLM already listed in Tips; this promotes it from "nice tool" to
  "the recommended sovereign routing layer."

**Decision policy — WHO decides and WHEN (refinement, was an open gap).**
The earlier text named the gateway and the `local -> cheap cloud -> premium`
chain but never said what TRIGGERS each hop or who owns the decision. Pinning it
down so a build doesn't guess. Two distinct levels:

- **Level A — rule-based fallback. THE COMMITTED TARGET (medium effort).**
  Routing is DETERMINISTIC and the hops fire only on measurable conditions:
    - chosen backend is unavailable / errors out  -> next tier
    - request exceeds the local model's context window  -> a larger cloud model
    - rate-limit / timeout / quota hit  -> spill over
    - an explicit MANUAL tag/alias ("use premium for this one")
  WHO decides: the USER owns the rules; `configure` proposes a default policy and
  the user approves it (recommend-don't-decide, §1). The GATEWAY then EXECUTES
  those rules — it does not judge intent. This stays on the deterministic side of
  §4.5 (rules = script-like), realized via LiteLLM's `fallbacks`/retries/routing.
  Default policy on capable hardware: local Ollama primary -> cheap cloud ->
  premium, hops triggered ONLY by the conditions above. A manual escalation alias
  covers cases rules can't judge.

- **Level B — semantic / quality-aware routing. OUT OF SCOPE (not medium effort).**
  "Read the request, judge whether it's hard enough to need the premium model,
  decide per query." That is interpretation -> agent territory (§4.5): slow,
  token-costing, non-deterministic, and an open problem. Explicitly NOT promised.
  Do not let a build slide Level B in under the "self-deciding gateway" banner.

Build shape (when this round happens): `configure` detects capable hardware,
installs LiteLLM as a LOCAL service, writes a `config.yaml` encoding the Level-A
default policy (keys from `~/.hermes/.env`, never logged), points Hermes'
`base_url` at the gateway, and documents the manual-escalation alias. Its own
build round + live test (per §5). Until then, the delivered reality stands:
`configure` picks ONE model and there is NO runtime decider — the user decides
once, at config time.

### 2.8 Script family conventions (what lets the family grow)

Any number of scripts can join the chain if they follow the shared
conventions:

- Naming: `ai-memory-<role>.sh`; single self-contained file.
- Self-copy to `$VAULT/.tools/` on first run; all docs reference that home.
- Standard flags everywhere: `--help`, `--version`, `--yes`.
- Shared behaviors: idempotent checkpoints, human-in-the-loop checkpoints
  for GUI actions, TTY/non-interactive detection, bash 3.2 compatible,
  secrets never logged.
- Chain: every script ends by pointing to the natural next step
  (setup → configure → ingest → remote → done).
- A future `ai-memory.sh` menu/dispatcher is allowed but not required.

---

## 3. Explicitly out of scope (separate future projects)

- Hermes **claude-import skill** (history into Hermes' native `state.db`
  memory) — pursue as upstream contribution; open a GitHub issue first.
- Vault-backed Hermes **Memory Provider plugin** (vault *as* memory backend).
- Whole-disk scanning, auto-updates, any self-modifying behavior.
- **A separate Mac project (its own machine, unrelated work) is forthcoming.**
  It is NOT part of local-ai-memory — do not let a build round bleed into it.
  (macOS *support inside this product* stays in scope as it always was.)

---

## 4. Minimum / recommended hardware (to document everywhere)

| | Minimum | Recommended |
|---|---|---|
| RAM | 8 GB (3B models — limited) | 32–48 GB (32–35B models) |
| Disk free | 20 GB | 60+ GB |
| Platform | macOS 12.4+/Linux (apt/dnf/pacman) | Apple Silicon or NVIDIA GPU |
| Network | needed for install only | — |

---

## 4.4 Backlog — flagged from the ingest live run (X230)

- **§B1 Re-import / upgrade path (low-med prio).** Idempotency is by output
  filename, so a TOOL UPGRADE does not re-clean already-imported files — a user
  who upgrades keeps old, noisier files unless they wipe 05-AI-Sessions first.
  Fix options: a `--reimport/--force` flag, or embed a parser-version in each
  file and re-emit when it changes. Flagged by CC, not built.
- **§B2 ChatGPT attachment parity (low prio).** The ChatGPT parser drops
  attachment/non-text content the same way the Claude parser did before
  Finding 2. Same CLASS, left untouched because no ChatGPT export was available
  to test. Mirror the Claude fix when a real export exists.
- **§B3 Attachment bloat (low prio).** Large extracted_content is embedded in
  full (faithful but can bloat a file). Not capped — decide later if a cap or
  summary is wanted.

## 4.05 Bootstrap / distribution — getting the scripts OUT before anything runs

Chicken-and-egg the user spotted: setup can install unzip for INGEST's needs,
but it cannot help you UNPACK the scripts themselves — you need them unpacked to
run setup at all. So "how do I get the scripts out" is a docs/distribution
problem that precedes setup, and it must not assume unzip exists (a clean WSL
has neither unzip nor zstd).

README must, BEFORE the first `bash` line, cover acquisition without assuming
tools:
1. **Primary method: `git clone`** — recommend it first. git checks files out
   already-unpacked, so there is NO unzip step at all. This sidesteps the whole
   problem for most users:
     git clone https://github.com/<user>/local-ai-memory && cd local-ai-memory
2. **Fallback: ZIP download** ("Download ZIP" on GitHub). Here the user has a zip
   and needs to unpack BEFORE any script runs — and unzip may be absent. Give a
   dependency-free bootstrap using Python (present on nearly every Linux/WSL):
     python3 -c "import zipfile; zipfile.ZipFile('local-ai-memory.zip').extractall()"
   (This is exactly what unblocked the live WSL run when unzip was missing.)

Two distinct unzip needs, kept separate:
  - unpack the SCRIPTS (before setup) -> docs bootstrap above, never assume unzip.
  - unpack the user's EXPORT (during ingest, after setup) -> setup installs unzip
    in its dep phase (§4.1).

**BUILT (README):** the README now LEADS with `git clone` (no unzip step), gives
the Python `zipfile` fallback for the ZIP-download path, and adds an explicit
"On Windows? Run it in WSL" section — all BEFORE the first `bash` line.

## 4.1 WSL support — a first-class scenario (live finding)

Windows users can run the whole stack inside WSL (Windows Subsystem for Linux)
without leaving Windows — a natural fit for the "give Windows hardware an AI
life" audience. Live run on WSL2 (Ubuntu, 15 GB RAM, systemd present) confirmed
the core path works, with these findings to bake in:

- **Missing base deps on a clean WSL/Ubuntu:** setup assumed `unzip` and `zstd`
  exist; a minimal WSL has neither (zstd is needed by the Ollama installer,
  unzip by ingest). setup MUST install these in its tool-provisioning phase,
  not assume them. (General lesson: audit ALL silently-assumed deps — clean WSL
  is the best test for this, having none of the conveniences older boxes carry.)
- **apt lock contention:** fresh WSL runs `unattended-upgrades` in the
  background, holding the apt lock. setup should wait for the lock gracefully
  (or detect+message) instead of failing.
- **Cross-filesystem data (the key WSL nuance):** a Windows user's AI exports
  almost always live on the WINDOWS side (/mnt/c/Users/<name>/Downloads), NOT in
  the WSL home dir where ingest looks by default. So ingest auto-discovery
  misses them. Fix: detect WSL (presence of /mnt/c + a WSL kernel marker) and,
  when detected, ASK or auto-include the Windows Downloads folder in discovery
  (e.g. "Running under WSL — also scan your Windows Downloads at
  /mnt/c/Users/.../Downloads?"). Ties directly into §4.55 scan-to-report:
  on WSL, a scan that spans the Windows side is especially valuable.
- **Keep the vault in WSL's own filesystem** (~/Documents/ai-memory), not under
  /mnt/c (cross-FS access is slow and has permission quirks — and risks the
  §4.3 working-dir class of problems).
- Document WSL explicitly in README/checklist as a supported path: "On Windows?
  Run it in WSL." Lowers the barrier for the ex-Windows audience enormously.

**BUILT (setup v8.8 / ingest v2.6 / remote v2.4):** every apt call now goes
through an `apt_get` wrapper that passes `-o DPkg::Lock::Timeout=300` (waits for
the unattended-upgrades lock instead of failing) and prints a heads-up when the
lock is held; setup installs `unzip` + `zstd` in its core-tools phase (idempotent
skip if present); ingest detects WSL (/mnt/c + kernel marker) and offers/auto-
includes each `/mnt/c/Users/<name>/Downloads` in discovery (skips Public/Default).
Live-verified on the NON-WSL box: apt_get really installed a missing package,
unzip/zstd skipped as present, WSL detection returned [] (clean no-op), glob/
filter logic proven on a synthetic tree. The real /mnt/c scan on WSL is
written-but-unproven (no WSL hardware this round).

**LIVE-VERIFIED + FIXED (ingest v2.7, 2026-06-16):** the §4.1 /mnt/c path is now
PROVEN end-to-end on real WSL2 (6.18-microsoft-standard-WSL2, Ubuntu). Detection
fired, `/mnt/c/Users/*/Downloads` was discovered, a REAL Claude.ai export staged
on the Windows side was auto-discovered and imported (102 conversations, files
real on disk, re-run idempotent at 0 new/102 skipped), vault stayed in WSL home.
Two bugs found and fixed: **BUG-1** — the skip set
`{Public,Default,Default User,All Users}` let `DefaultAppPool` (IIS system
profile) through on every run; fix = case-insensitive set + `defaultapppool`
and `wdagutilityaccount` added (re-verified live: DefaultAppPool now absent,
real users still included, import still 102). **BUG-2 (latent, hardened)** — the
WSL gate keyed only on `/proc/version`; a custom WSL kernel lacking that string
would false-negative. Fix = also read `/proc/sys/kernel/osrelease` and accept
`$WSL_DISTRO_NAME` (additive; cannot break the working path; live detection
still fires). Pattern-hunt: the Windows-profile denylist is the only such
construct in the four scripts — class is localized.

## 4.55 Scan-to-report option — map messy data, let the agent act (BUILT)

The three discovery tiers (default / --scan DIR / --deep-scan) STAY. This adds a
fourth MODE that maps instead of imports — a clean §4.5 split:

- **`--scan-report`**: scan (optionally deep), import NOTHING, write a neutral
  file (e.g. ai-scan-report.md in the vault) listing what was found:
    - recognized exports ready to import (with the exact import command),
    - UNKNOWN candidates that looked AI-ish but whose format the script doesn't
      recognize (path, size, a hint of why it matched),
    - a docs-pointer: "your agent can read this report and help you decide /
      collect / convert the unknown items."
- **Why this is the right shape (§4.5 + §4.7):** scanning/listing is
  deterministic -> script. Judging what an unknown file is, or whether it's
  worth importing -> interpretation -> agent. The report file is the BRIDGE
  between the durable script and the volatile agent; the agent-facing prompt
  lives in docs (per §4.7), updatable independently. The script never needs to
  understand a format it doesn't recognize — it just reports "found something
  AI-ish here, don't know the format" and delegates judgement.
- **Default = off.** For most users "find Claude export in Downloads -> import"
  is enough. --scan-report is for users with SPRETIG data spread across old
  exports / multiple tools / unknown formats who want a map first. Option, not
  default (user's explicit ask).

**BUILT (ingest v2.8, 2026-06-16):** `--scan-report` scans (`~/Downloads` + any
`--scan`/`--deep-scan`/WSL Windows-Downloads roots), imports NOTHING, and writes
`<vault>/ai-scan-report.md` listing recognized exports (with the exact import
command) and unknown AI-ish candidates (matched a specific stem — data-*/
*chatgpt*/*conversations*/takeout-* — but failed content-sniff; the generic
*.zip catch-all is deliberately NOT treated as AI-ish, so random archives are
not flagged). The agent-facing prompt lives in `docs/collect-with-agent.md`, NOT
in the script (§4.7). This is the first increment of the §4.5 hybrid decision:
the recognized/unknown split IS the script-lane/agent-lane boundary. Sandbox-
verified on the non-WSL box (recognized export + import cmd emitted, decoy listed
unknown, non-AI driver excluded, 0 imported, exit 0). ALSO live-verified on real
WSL2 (2026-06-16): a real export + decoy staged on the Windows side were mapped
via the /mnt/c Windows-Downloads path (recognized: 1 with /mnt/c import cmd,
unknown: 1 decoy, imported: 0); DefaultAppPool correctly absent (BUG-1 fix holds
in v2.8).

## 4.6 GitHub — low-key, opt-in, NOT a daily-flow feature

Correction to earlier over-scoping: GitHub is NOT something the script pushes
into the user's daily workflow. It belongs in the setup moment only because the
user is already sitting there with pen and paper wiring things up, so it's
reasonable to let them OPTIONALLY handle the GitHub bits at the same time —
publishing the tool, or mirroring their vault. If it doesn't fit naturally as a
quiet optional step, it goes in the end-of-checklist TIPS instead.

- GitHub is third-party (Microsoft) cloud: never assumed, never required,
  default = skip, local copy is always the source of truth.
- Keep it SMALL: a quiet "have a GitHub account you'd like to wire up? (optional,
  third-party cloud — skip to stay fully local)" — or just a Tips note. Do NOT
  build it into the core flow or imply it's expected.
- This is about the END-USER product. It is SEPARATE from how WE sync the repo
  during development (that's a build-process concern, not a product feature).

## 4.7 The agent-assisted-ingest tension (IMPORTANT — and self-limiting)

User idea: ingest could warn "if you have valuable conversations on cloud AI
services, I can give you a starter prompt for your Hermes that will help you
collect that data into local Hermes memory." This is attractive — it uses the
agent (Hermes) to gather the messy, hard-to-export stuff a script can't reach,
which is exactly the §4.5 spirit (messy reality -> agent).

BUT the user spotted the trap themselves: **baking a Hermes-specific prompt into
the script couples a deterministic, long-lived script to a fast-moving agent
that may be outdated in months.** If Hermes' interface/skills change, a
hardcoded prompt rots — the same hardcoding-ages-badly problem as the format
parsers (§4.5), one level up.

Resolution (design rule): the script may POINT to agent-assisted collection but
must not EMBED agent-specific instructions. Options that respect §4.5:
  - The script prints a generic pointer ("your agent can help collect cloud
    history — see docs/collect-with-agent.md"), and the actual prompt lives in
    a DOCS file that's easy to update independently of the script.
  - Or the starter prompt ships as a separate, versioned skill/template the
    agent loads — not as a string frozen inside bash.
Keep the durable script and the volatile agent-prompt in SEPARATE artifacts so
each can age on its own schedule. Flagged for the build; the docs-pointer
approach is the low-risk default.

## 4.5 Core design principle — deterministic work is a script, messy reality is an agent

(Surfaced by a sharp user question: is ingest even the right *kind* of thing?)

The parts of the stack that meet **predictable, deterministic** work — install,
configure, back up, set up remote access — should stay **bash scripts**:
fast, free, reviewable, repeatable, no tokens, no surprises.

The parts that meet **messy, unpredictable, changing reality** — parsing the
spretig zoo of AI export formats that each vendor changes on its own schedule —
are a poor fit for a hardcoded script. A script that hardcodes 10 formats is
always behind reality on at least one, and ages badly. That kind of work suits
an **agent**: an LLM can *interpret* an unknown export instead of needing a
fixed schema. Interpretation of messy input is exactly what models are good at.

The dividing line for every future feature:
- Deterministic / stable / must-be-exact  -> script.
- Messy / variable / needs interpretation  -> agent (or a hybrid that scripts
  the known-stable formats fast and falls back to an agent for the unknown).

**Ingest implication (backlog, large):** ingest currently sits on the wrong
side of this line — a deterministic script doing a non-deterministic job
(10 hardcoded format parsers). Reconsider as **agent-driven or hybrid**: keep
the fast script path for known-good formats (e.g. Claude export is
well-structured), fall back to an agent for anything the script doesn't
recognize. Caveats to weigh: agent ingest is slower, costs tokens, and is
non-deterministic (same export may convert slightly differently twice) — which
is exactly why hybrid (script-first, agent-fallback) is likely the right shape,
not pure-agent. Decide AFTER we know whether the current script path works on a
real export (CC is testing that now); this is a next-generation redesign, not a
rush.

**DECIDED (2026-06-16, CC): HYBRID — deterministic script first, agent fallback.**
The gate ("decide after the script path is proven on a real export") is now met:
the §4.1 live run imported 102 real conversations, correctly and idempotently
(0 new / 102 skipped on re-run). That determinism + zero token cost + reviewable
output is a property to KEEP, not discard — so NOT pure-agent (which §4.5 itself
notes is slower, costs tokens, and is non-deterministic). And NOT pure-script
(ages badly — always behind on one vendor format). Chosen shape:
  - Script keeps recognition + import + idempotency for KNOWN-GOOD formats
    (unchanged; the proven path). The recognition seam already exists:
    sniff_zip() returns a source for known signatures and None otherwise, and
    find_export_zips() currently DROPS the None set silently.
  - The hybrid boundary = that dropped set: recognized -> fast script lane;
    unrecognized-but-AI-ish -> agent lane.
  - Realized via §4.55 `--scan-report`: capture (don't drop) unknown candidates
    and write a neutral bridge file (recognized+import-cmd / unknown+why-matched /
    docs pointer); import nothing in report mode.
  - Agent-prompt decoupling (§4.7 hard rule): the script writes the neutral
    bridge file and points to docs/collect-with-agent.md; it NEVER embeds an
    agent-specific prompt. Durable script <-> volatile prompt, separated by the
    bridge artifact.
  Consequence: a new vendor format is useful immediately (surfaces in the report,
  agent handles it) without a code release; a hardcoded parser is added only when
  a format is common enough to deserve the fast lane. #1 (this decision) and
  §4.55 are therefore the SAME work — the spike below is the first increment.

## 4.3 CRITICAL — the import->reachable gap (core-promise bug, X230 live)

The single most important finding so far. ingest faithfully writes 102
conversations into the vault, prints a green "imported!" summary, and points to
`hermes chat` — but a plain `hermes chat` started from $HOME searches its
CURRENT WORKING DIRECTORY, not the vault, so it finds NOTHING. The core promise
("import your history, then your agent draws on it") silently breaks on the last
hop. Our earlier "Hermes can read it" success was luck: that call happened to be
launched from the vault.

Bug class (§5.3): "pipeline writes artifact to X; consumer is launched/configured
to look in Y." A green producer summary masks a broken consumer.

Root cause specifics (verified in Hermes source + /proc, not self-report):
- Hermes' local terminal/file tools root at os.getcwd()/$TERMINAL_CWD, NOT at a
  vault path in config.yaml. So the launch directory decides everything.
- IMPORTANT: config.yaml `terminal.cwd` is NOT honored by the local backend.
  Do not rely on it. What works: TERMINAL_CWD in ~/.hermes/.env, OR a shell
  launcher/alias that cd's into the vault.

Required fixes (next build, HIGH priority — this is the core promise):
1. **configure/setup must pin Hermes' workspace to the vault** so plain
   `hermes` just works. Install a launcher (the proven fix:
   `hermes() { ( cd "$VAULT" && command hermes "$@" ); }` in the shell rc) and/or
   set TERMINAL_CWD in ~/.hermes/.env. NOT config.yaml terminal.cwd (ignored).
2. **ingest must do a post-import reachability check.** After writing files,
   confirm that hermes-as-it-will-run roots at the vault (launcher/TERMINAL_CWD
   present); if not, print a loud explicit instruction instead of a falsely-happy
   summary: "Run hermes from the vault, or the agent won't see what was imported."
3. Document "run from the vault" and lean on the existing resume.sh / AGENTS.md.

Also clarified (not a bug): "list memory returns empty" is expected — the vault
import is plain markdown reached by file search, NOT entries in Hermes' native
state.db memory. Seeding native memory is the optional USER.md/MEMORY.md step
(§2.3), separate from import.

## 4.3.1 ★★★ TOP PRIORITY — reachability must hold from EVERY entry point, not just the shell (macOS dashboard live finding, 2026-06-18)

**This is the heart of the whole project — the user's stated reason for building
it: "I always end up here — I imported my history but the AI can't actually reach
it. Solve it and HARDEN it."** §4.3 fixed exactly ONE door (the shell launcher).
Live use on a real Mac proved that is not a fix — it is a fix that pretends.

**The live finding (real Mac, real dashboard, not synthetic):** after a clean
setup → configure → ingest (8 conversations imported, reachability check GREEN),
the *shell* `hermes chat` reaches the vault — but the *web dashboard* chat
(`hermes dashboard --tui`, the friendliest door, the one a beginner picks) is
memory-BLIND. Evidence: the dashboard launches Hermes from
`~/.hermes/hermes-agent` (the program's OWN dir — visible in the TUI status bar),
so its file/search tools root there, it loads the Hermes *developer's* AGENTS.md
instead of the vault's memory routine, and it cannot see `05-AI-Sessions/`. Asked
"tell me something from your memory," the model itself reasoned (correctly!):
"I don't have access to your memory… the profile is empty," and recited Hermes
source-tree docs instead. The §4.3 shell launcher does NOT apply to the
dashboard/gateway/TUI — they bypass it.

**The generalization (the real bug):** reachability that depends on HOW you launch
hermes is not reachability. EVERY door to the agent must reach the vault — shell
`hermes chat`, `hermes dashboard`/`--tui`, `hermes gateway` + messaging channels
(Telegram/WhatsApp/etc.), `resume.sh`, and any future entry point — or the core
promise breaks precisely when the least-technical user walks through the nicest
door. A reachability check that only tests the shell door is itself the §5.3
producer/consumer anti-pattern (green for one consumer, silently broken for the
rest).

**The deeper principle (user's sharper framing, 2026-06-18) — this is a HANDOVER
problem, not a doors problem.** "All doors" is too narrow to catch every
"imported-but-not-found" edge case. The real cure is the SAME mechanism that lets
a fresh **Claude Code** session resume reliably after `/clear` (the user lives
this pain and named it): a small, ALWAYS-LOADED handover that does two things at
once — (a) **ORIENTS** the agent: "you have a memory vault at /ABSOLUTE/path; it
holds the user's imported history + profile; before you ever say 'I don't
remember,' SEARCH it; here is who the user is; here is the INDEX of what's
imported," and (b) gives it the working **SCAN/search** to act on that
orientation. **Instructions AND file-scan, together — either alone fails**
(instructions with no scan = knows it should look but can't; scan with no
instructions = can look but doesn't know to, or where). This is exactly our own
stack: `CLAUDE.md` (always-loaded rules) + `MEMORY.md` (always-loaded index that
says "read X in full, start here") + the memory files (scanned on demand).
local-ai-memory must hand Hermes the same two layers, so a fresh session — through
ANY door, from ANY directory, after ANY restart — lands ORIENTED, and
"imported-but-not-found" becomes a DETECTABLE mismatch against the index, not a
silent miss.

**Design direction — deliver the HANDOVER (instructions + scan), CWD-INDEPENDENT
(stop fighting Hermes' launch-dir behavior):**
1. **Load the memory routine GLOBALLY, not per-cwd.** Install the vault grep
   recipe into a location Hermes reads for EVERY session regardless of launch dir
   (Hermes' user-level/global instructions), so shell + dashboard + gateway all
   inherit it — not only the per-directory AGENTS.md that the launch dir decides.
2. **Use ABSOLUTE vault paths in the routine** (`grep -rli "X"
   /ABSOLUTE/VAULT/05-AI-Sessions/`), so finding imported history does NOT depend
   on cwd. File tools can read absolute paths from any root.
3. Keep the shell launcher as belt-and-suspenders, but it is no longer the
   primary mechanism.
4. **Per-door reachability VERIFICATION at install time** — prove recall from each
   entry point that exists (shell; and if a dashboard/gateway is set up, those),
   fail loudly per door. Definition of done: ask the SAME memory question through
   the BROWSER dashboard and get a grounded answer citing a real imported file —
   verified, not assumed.
5. Investigate any Hermes "project/workspace pin" the dashboard honors; but since
   `config.yaml terminal.cwd` and `TERMINAL_CWD` are already known to be ignored by
   the local backend (§4.3), assume the global-instructions + absolute-paths
   approach (1+2) is the robust fix that does not depend on Hermes cooperating.
6. **ingest builds & maintains an INDEX/manifest of what was imported** (the
   MEMORY.md analog): source, counts, titles/topics, paths. The handover points
   the agent at it. This is what turns "imported-but-not-found" from a silent gap
   into a catchable mismatch — if it's in the index but a search can't surface it,
   that's a real bug the verification (point 4) must flag, not hide.
7. **The orientation must teach "search, don't guess," robust to messy names.**
   The §4.2 weak-model failure (prints/guesses instead of searching) is the other
   half: the handover instruction must explicitly say to run the search tool with
   keyword variants and read matches — never fabricate filenames — so the routine
   survives a weak local model.
8. **Per-door verification must confirm ACTUAL TOOL USE, not just a plausible
   reply.** Live (2026-06-18, browser dashboard, ABSOLUTE-path prompt): qwen3.5
   FALSELY claimed "I don't have filesystem access" and refused — though `file`
   and `code_execution` tools were registered (28 tools in its own startup
   banner) — then recited wrong generic paths (`~/.hermes/session/`). So even a
   perfect handover + absolute paths fail if the model won't CALL the tool.
   Ground truth at that moment: 8 imported conversations sat in the vault (6
   lmstudio + 2 openclaw, e.g. "OpenClaw på Mac Mini"). Therefore: (a) the fix's
   verification must force and CONFIRM a real tool invocation that returns vault
   content, not accept a worded answer; (b) reliability ultimately needs a
   capable-enough model (§4.2) — when the local model balks, a cloud fallback key
   is what makes recall dependable. The dashboard's wrong cwd AND the model's
   tool-refusal are independent failures; the fix must beat both.

**Status: FIRST SLICE BUILT + PROVEN end-to-end (2026-06-18, configure v4.8).** The
cwd-independent HANDOVER ships: `install_soul_handover()` writes a marker-bounded
orientation block into `~/.hermes/SOUL.md` (always injected, every door, any cwd) —
absolute vault paths, the search-don't-guess recipe, and explicit "actually CALL
the tool, don't just describe it" wording (points 6-8). Idempotent; preserves any
user persona text. Two diagnoses corrected the design's assumptions:
- **`TERMINAL_CWD` is NOT ignored** in the installed Hermes — `system_prompt.py`
  (context discovery) and `tool_executor.py` (file tools) both read
  `os.getenv("TERMINAL_CWD") or os.getcwd()`. The dashboard was blind only because
  it launched from the install dir (loading the dev `AGENTS.md`), not because cwd is
  unfixable. So the three layers are: TERMINAL_CWD (.env) → shell launcher → SOUL.md
  handover (the cwd-independent primary). The old §4.3 "TERMINAL_CWD ineffective"
  note was outdated and is corrected.
- **`tool_use_enforcement` is NOT the refusal lever.** `auto` injects the
  enforcement guidance when the model matches `TOOL_USE_ENFORCEMENT_MODELS =
  ("gpt","codex","gemini","gemma","grok","glm","qwen","deepseek")` — and `qwen` is
  in it, so guidance WAS injected. The refusal traced to the wrong context file +
  the weak model, not enforcement.
**LIVE PROOF (Mac, same wrong cwd `$HOME`, same vault, same handover — only the model
varied):** qwen3.5 made **0** tool calls (hallucinated grep, twice); **claude-
haiku-4.5 via OpenRouter made 6 REAL tool calls**, ran `grep -rli "OpenClaw"
"/Users/kv/Documents/ai-memory/"` (the handover's absolute path), read and CITED the
real imported files (`05-AI-Sessions/openclaw/…`, `…/lmstudio/…openclaw-på-mac-mini…`).
This satisfies the definition of done from the dashboard's failure cwd, and proves
the model floor (§4.2) is required for reliable recall, not optional.
**Still TODO (own bundles): model-floor warning in configure (recommend a capable
cloud fallback for memory), ingest import INDEX (`05-AI-Sessions/INDEX.md`, which the
handover already points at), and a `doctor` per-door verifier (Hermes has a `doctor`
subcommand to build on — it would have caught "0 tool calls").**

## 4.2 Model capability floor for tool-use / memory (X230 live finding)

Discovered by the user: with a weak/cheap cloud model (gpt-4o-mini), Hermes
reached the vault but could NOT use memory well — it GUESSED filenames
(01-Projects/Project Kraftvagn.md) instead of running grep/search_files. The
SAME vault, files, and Hermes worked correctly the moment a more capable model
was selected: the better model reasons "I should SEARCH" and calls the tools.

The lesson: memory/RAG here depends on the model being capable enough to use
tools (search-don't-guess), not just to chat. A model can be cheap enough to
hold a conversation yet too weak to drive the agent's file-search tools — and
then memory silently appears broken though everything is wired correctly.

Implications for the build:
- configure should WARN when a low-capability model is chosen for an agent that
  relies on tool-use/search: "this model may be too weak to search your memory
  reliably; it may guess instead of search. For memory features, prefer a more
  capable model." Especially relevant in cloud-only mode on weak hardware, where
  the cheapest model is the tempting default.
- This is distinct from §4.3 (working-directory reachability). Order of failure:
  (1) agent must be ROOTED at the vault (§4.3), THEN (2) the model must be
  CAPABLE enough to search it (this §4.2). Both must hold for memory to work.
- Note the tension with cloud-only-on-weak-hardware: the machines most likely to
  need cloud are also most likely to reach for the cheapest model — exactly the
  one that may be too weak for memory. Surface the tradeoff honestly.

Architecture note (answers a user question): imported history is currently
reached by LIVE FILE SEARCH of the vault markdown, not a database. Seeding it
into Hermes' native memory (USER.md/MEMORY.md, §2.3) is a separate optional
step that would make memory faster/more integrated — not required for it to
work, but a natural enhancement.

## 4.35 Local-model context: TWO values must clear the floor (WSL live finding)

First time the project ran a CAPABLE LOCAL model through Hermes (qwen3:14b on
WSL, 15 GB). Surfaced what X230 never could (too weak for a local model):

Hermes' 64K context floor requires setting TWO separate values for a local
Ollama model, not one:
  - model.context_length: 65536   — what Hermes BELIEVES the model's window is
  - model.ollama_num_ctx: 65536   — what Ollama actually LOADS the model with
Many local models have a native context BELOW Hermes' floor (qwen3:14b native =
40,960). Setting only context_length passes Hermes' check but Ollama still loads
the model at 40,960 -> Hermes refuses ("Ollama runtime context too small").
BOTH must be >= 64,000.

configure (for local Ollama models) MUST therefore:
  - detect when the chosen model's native context is below the floor, and
  - write BOTH context_length AND ollama_num_ctx >= 64000.
config.yaml terminal.cwd is ignored (per §4.3); these two model.* keys ARE read.

ALSO — a critical configure bug confirmed on WSL: configure showed the model-
selection + Hermes-config steps and downloaded the model, but NEVER WROTE
config.yaml (no .bak existed; Hermes ran on its 64KB default template with model
anthropic/claude-opus-4.6, "No inference provider configured"). So configure's
config-writing silently failed. The working path was to set the model by hand
via `hermes model` -> custom -> http://localhost:11434/v1. configure MUST
reliably write config.yaml (and verify it wrote) — a green run that downloads a
9GB model but writes no config is a bad failure. Likely same root as needing the
dual context values: configure for local models was never exercised live before.

**BUILT (configure v4.4):** local mode writes BOTH context_length and
ollama_num_ctx (both >= floor); config.yaml is written atomically (temp +
os.replace) then VERIFIED by reading it back — a missing/empty config now fails
loudly instead of running green. Live-verified: local run emitted both keys +
"Verified config.yaml on disk"; cloud run wrote only context_length; the verify
path dies non-zero when a key is missing.

RAM caveat: forcing 64K runtime context on a 14B model loads the context window
on top of the ~9GB model — heavy on CPU/WSL. Works on 15GB but is slow; on less,
prefer a 7-8B model or cloud. configure's model suggestion should weigh context
cost, not just model size.

## 4.8 Known untested surface (honest) + remote.sh live-test staging plan

Of the four scripts, **remote.sh is the only one never run on real hardware.**
Its sudo/WireGuard/Cloudflare/RustDesk paths are syntax-checked and
sandbox-reasoned only. setup, configure, and ingest have all had real live
runs (X230). Before remote.sh is relied on, it needs a live test on a real
node — treat its current state as "written carefully, unproven."

**Why this script earns extra ceremony.** Its bad outcomes are silent lockouts
of a possibly-headless box, not red errors: it edits sshd, can disable password
login, brings up a WireGuard hub with IP-forwarding, and touches the firewall
and boot behaviour. §5 ("the sandbox lies") applies hardest here.

**Code-review findings (2026-06-16, CC) — UNVERIFIED LIVE; they set the test
focus and where to snapshot:**
- **F1 (highest risk): sshd hardening is self-attested AND the drop-in may be
  ignored.** §3 disables password auth on the strength of `ask_yn "Did key
  login work?"` (the user's word, not a machine check) and writes
  `/etc/ssh/sshd_config.d/99-ai-memory.conf` + restarts sshd WITHOUT confirming
  `sshd_config` actually `Include`s that dir (Debian/Ubuntu/Fedora do; Arch's
  stock config does NOT) and WITHOUT `sshd -t`. Two opposite failures: (a)
  no-Include box -> green "Password login disabled" that changed nothing
  (false-success, the §5.3 anti-pattern); (b) any box -> a key that doesn't
  really work + a "yes" = permanent SSH lockout. FIX (R3): machine-verify a
  keys-only login (`ssh -o BatchMode=yes -o PasswordAuthentication=no`) BEFORE
  flipping the switch; ensure the drop-in is honored (check/append the Include
  or write the main config); `sshd -t` before restart; confirm via `sshd -T`.
- **F2: the generated Cloudflare-DDNS script has a JSON-quoting bug** (the
  `BODY="{"type":"A",...}"` line in the `<<'DDNS'` heredoc): at runtime bash
  strips the inner quotes and POSTs invalid JSON, so option 2 has never updated
  a record. FIX (R3): single-quote / printf-build the JSON; add a real
  first-update success check.
- **F3: the WireGuard hub private key is passed through a `sudo sed` argv**
  (line ~496) — briefly visible in `ps`, a nick in the secrets model (§2.7).
  FIX (R3): write the key via a shell-owned redirect, not argv.
- **F4 (reassuring): the firewall claim is milder than feared.** The script
  never ENABLES ufw and never sets default-deny — it only adds `allow` rules to
  an already-active ufw. So the firewall path cannot by itself lock you out.
- **F5 (VERIFIED live, R2 STEP 0, 2026-06-16): the CAN_PROMPT probe is
  incomplete.** `CAN_PROMPT=false; [[ -r /dev/tty && -w /dev/tty ]] &&
  CAN_PROMPT=true` (remote.sh:35) passes whenever the device node exists with
  perms, but `open(/dev/tty)` fails with ENXIO when there is no controlling
  terminal. So CAN_PROMPT can be true while the tty is unusable, and MAIN-role
  keypair creation (remote.sh:154, `ssh-keygen ... < /dev/tty ... || die`) DIES
  instead of falling back to the non-interactive `-N ""` branch just below it.
  Same probe in setup.sh:78-79 -> pattern-class (2 of 4 scripts). FIX (R3):
  probe by actually opening /dev/tty (e.g. `{ : >/dev/tty; } 2>/dev/null`), not
  just `-r/-w`; pattern-hunt the class. Found WITHOUT a target (STEP 0 is
  target-free); the rest of R2 (STEPS 1-8) is blocked on an acceptable target.

**R2 LIVE RESULTS (2026-06-16, CC) — ran on a local QEMU VM (Ubuntu 24.04.4,
TCG/no-KVM, host=X230; serial-console + monitor-socket as the second way in;
sshd pre-existed so STEP 1 took the idempotent-skip path).** Drove NODE through
key-install -> harden -> WireGuard via a scripted `ssh -tt` session.

PASSED (verified): key APPEND path (`Key added to authorized_keys`); network
analysis (detected real public IP + reverse-DNS, correctly NOT flagged dynamic
-> recommended WireGuard); WireGuard hub came up (`wg show` interface wg0, key
loaded); secret separation CORRECT (system /etc/wireguard/wg0.conf holds the
private key, the home copy holds only an explanatory comment -> **F3's on-disk
worry is unfounded**; only the transient `sed`-argv ps-exposure remains, minor);
key login survives hardening.

FAILED (the headline):
- **F1 is CONFIRMED and WORSE than predicted — it is the DEFAULT outcome on
  cloud-init Ubuntu, not just no-Include systems.** After hardening, the script
  printed `✓ Password login disabled` and the drop-in existed, yet `sshd -T`
  reported `passwordauthentication yes`. Root cause: sshd is FIRST-MATCH-WINS,
  and `/etc/ssh/sshd_config.d/` loads alphabetically — `50-cloud-init.conf`
  (`PasswordAuthentication yes`, written because ssh_pwauth was set) sorts
  BEFORE our `99-ai-memory.conf` (`no`) and wins. The `Include` line being
  present did not help. So on the most common headless-node OS (any cloud-init
  box) the hardening SILENTLY DOES NOTHING while reporting success — a security
  false-success. FIX (R3): after writing the drop-in, VERIFY the effective value
  with `sshd -T | grep -i passwordauthentication` and only claim success if it
  is actually `no`; if an earlier/lower-numbered drop-in (e.g. cloud-init's)
  overrides it, neutralize or supersede it; `sshd -t` before restart. This is
  the §5.3 assume-without-verify class — the real bug is "wrote config, never
  checked the receiver's effective state."
- **F6 (NEW, found live): `grep -q active` matches `inactive`.** remote.sh:499
  (WireGuard branch) gates the ufw rule on `sudo ufw status | grep -q active`,
  which is TRUE even when ufw is INACTIVE -> it ran `ufw allow 51820/udp` and
  printed `✓ ufw: UDP 51820 opened` on a firewall that is OFF (verified `Status:
  inactive`). The SSH branch at remote.sh:242 does it correctly
  (`grep -q "Status: active"`). FIX (R3): use the precise match in both; pattern-
  hunt loose `grep` substring gates across all four scripts.

STEP 8 power profile: PASSED — `sleep/suspend/hibernate/hybrid-sleep.target`
all `masked`, `loginctl` Linger=yes (linger file present), BIOS warning printed.

**F5 UPGRADED (severe): it also kills every non-interactive NODE run.** A
`</dev/null` run (no controlling terminal) wrongly set CAN_PROMPT=true (the
`[[ -r/-w /dev/tty ]]` node-mode check passes) and then DIED at remote.sh:272
(`echo ... > /dev/tty` -> "No such device or address", ENXIO) under `set -e`.
So F5 breaks not just MAIN keygen but ANY automated/cron/curl|bash-without-tty
NODE run, dying at the STEP 2 key menu. The guarded `read ... < /dev/tty || x=""`
lines survive; the unguarded `> /dev/tty` writes do not. FIX (R3): make
CAN_PROMPT actually open /dev/tty; guard or avoid `> /dev/tty`.

STEP 6 DDNS / F2 confirmed separately (host-side repro of the generated JSON).
The no-Include/Arch case for F1 is still worth a separate VM, but F1 is already
proven by the cloud-init path. Live VM snapshots were unavailable (the raw
cloud-init seed disk is unsnapshottable) -> per-step reverts used instead.
NOT RUN: the actual pull-the-plug reboot (VM reset under TCG is ~10 min) —
recommended as a quick follow-up to confirm linger services return on boot.

**Acceptable target machine (hard gate):**
- BEST — a disposable VM with snapshots + an out-of-band console (hypervisor or
  cloud serial console = the GUARANTEED second way in, independent of sshd/the
  network path being changed). Spin an Arch VM specifically to exercise F1's
  no-Include outcome.
- ACCEPTABLE — a sacrificial, backed-up physical node with a PHYSICAL/serial
  console next to the operator (X230-class qualifies only as throwaway).
- NOT ACCEPTABLE — the dev box itself; any machine whose only access is the SSH
  about to be hardened; anything anyone relies on with no console fallback.
- NON-NEGOTIABLE: do not execute §3 (hardening) or §4 (WireGuard/firewall) until
  an out-of-band console is confirmed and a snapshot taken. Never as root.

**Test sequence (low blast-radius first; snapshot before steps 4-5):**
0 static + read-only (`bash -n`, --help/--version, ROLE=solo exits, ROLE=main
  keypair on a scratch user). 1 NODE network-analysis block (read-only; put one
  VM behind CGNAT-like NAT to confirm IS_CGNAT fires + recommendation flips).
2 SSH server enable (revert: disable service). 3 install pubkey + THE GATE:
machine-verify keys-only login from the client, don't trust the script.
4 HARDENING on Debian/Ubuntu AND Arch; verify with `sshd -T`, not the green
line; rehearse recovery (rm drop-in + restart) every time before trusting.
5 WireGuard option 1; verify handshake from a real external client, home-dir
wg0.conf has no private key, watch `ps` for F3. 6 Cloudflare DDNS only with a
throwaway zone (expect F2). 7 RustDesk (no lockout risk). 8 power profile +
pull-the-plug test. Each step records a machine-checked acceptance + a revert.

**Round sequencing:** R1 plan+capture (this round, no live run); R2 live-test
the CURRENT script through 0-8 on Debian/Ubuntu + Arch to confirm F1/F2/F3 and
catch what review missed (fix nothing yet); R3 pattern-hunt fix bundle (F1/F2/F3
+ the "self-attested / green-but-did-nothing" class across all four scripts) and
re-live-test; R4 add Cloudflare Tunnel (§4.9) as its own later build+test.

## 4.9 NAT-friendly remote fallback ladder (decision)

When the normal local path (WireGuard-direct) cannot be reached — CGNAT, no
public IP, no router control — the fallback must be a MANAGED, NAT-traversing
tunnel, never a hand-rolled relay. The script should recommend in this order:

  1. **WireGuard fully-local** — nothing leaves the user's control (default when
     a reachable public IP + router exist).
  2. **Tailscale** — zero-config, beats CGNAT (already in the script).
  3. **Cloudflare Tunnel (`cloudflared`) [NEW, R4]** — no inbound port at all,
     outbound-only daemon; for users who can't open ports or already live on
     Cloudflare. COMPLEMENTS, does not replace, the existing Cloudflare **DDNS**
     (§2.7), which serves the WireGuard-direct path. Keep them distinct: DDNS =
     keep a name pointed at your IP for direct WG; Tunnel = no inbound port.
  NEVER — a custom SSH relay / reverse-tunnel through our own server.

Why not a relay: the relay used to drive the WSL live test is a DEVELOPMENT
device for a one-off, not a product feature. Baking a hand-rolled relay into the
product would make US run security-sensitive infrastructure and own a hop in the
user's auth path. Managed tunnels (Tailscale / Cloudflare) are the correct
abstraction — NAT-friendly, audited, nothing for us to operate. Adding
cloudflared is a small, self-contained build with its own live test (R4).

## 4.10 End-of-run hand-off + configure live-coverage (user feedback, 2026-06-17)

Three items raised by the user from real runs; flagged for a coming build, NOT
yet built.

- **§B4 The closing screen must END on the NEXT ACTION (beginner clarity). —
  BUILT (CC, 2026-06-17, spec v1.27).** Every chain script now ends on a bold
  green "▶ NEXT" footer whose last line is the literal command, printed AFTER the
  identity/tips blocks: setup → `bash <configure> <vault>` (open a new terminal);
  configure → `bash <ingest> <vault>`; ingest → `hermes chat` ("talk to your
  memory"); remote MAIN → `bash ai-memory-remote.sh` on each node; remote NODE →
  reordered so the mandatory pull-the-plug test is the final block (it had been
  buried above the old "Remote setup done" line). Each footer prints only when the
  script does NOT exec/launch the next stage itself. ORIGINAL FINDING BELOW:
  setup.sh DOES chain to configure (a "Next steps" block ~L1414 and a "continue
  here? [y/N]" offer ~L1433), but the pointer is BURIED: after that prompt the
  script still prints the identity block + Tips, so the LAST thing a beginner
  sees is tips / identity / file-paths (incl. `~/.hermes` key/.env mentions),
  NOT "what to type now." A confused beginner who declines the offer is dropped
  back at the terminal with the next command scrolled off-screen. FIX (next
  build): make the FINAL lines of every chain script the explicit next action —
  restate the literal command as the very last thing on screen, e.g.
  `▶ NEXT: open a new terminal and run:  bash <configure> <vault>`, printed
  AFTER identity/tips. Honor the §2.8 chain convention at the BOTTOM of output,
  not mid-flow. Apply across setup→configure→ingest→remote (the last one ends
  with "you're done"). This is the §2.9 reassurance layer realized at the exit.
- **§B5 configure.sh needs more LIVE coverage.** It is the thinnest-tested of the
  four: exercised only as cloud-only on the X230 (§1.6 findings) and dual-context
  on WSL (§4.35); the full local-model selection table, key-writing, and
  capable-hardware paths are under-exercised. Fold a thorough configure live-test
  into the **macOS live-test round** (capable hardware naturally exercises the
  local-first / future-LiteLLM paths that weak hardware cannot).
- Both sit alongside the existing backlog (§B1–B3, §2.9). §B4 is small and
  high-delight; do it early in the next UX-focused round.

## 4.11 `ai-memory-uninstall.sh` — clean reversal + export-first (BUILT v1.0)

**BUILT (CC, 2026-06-17, uninstall v1.0, pkg v12).** Increment 1 (core stack) ships.
Export-first + dry-run-default as specified below, with these realized details:
the export writes a `tar.gz` to `~/Downloads` (else `~/`) PLUS a secret-free
migration manifest (`ai-memory-export-manifest.json`, §4.12) at the archive root;
the vault is removed LAST and only after a verified export. Flags as spec'd:
`--yes`, `--export-only`, `--no-export` (types `DELETE`), `--remove-ollama`
(opt-in model wipe via `ollama rm`, runtime kept), `--remote` (recognized but
increment 2 — prints a deferral, acts on nothing). Plan and act share ONE set of
detector predicates so the preview can't drift from what's removed (the §5.3
producer/consumer class). Never root, never sudo (the Ollama autostart unit is a
`systemctl --user` / launchd user agent — no sudo needed), path guards on
vault/`~/.hermes`/`~/.paperclip`. **Deviation from the reverse map below, on
purpose:** the Claude-Desktop step SURGICALLY removes only our `obsidian-vault`
server entry (whose args reference this vault), saving a backup first — NOT the
"restore the saved backup" written below, because restoring a stale `.bak` would
clobber any MCP servers the user added since setup ran. **Verification:** `bash -n`
+ `--help/--version` clean; dry-run render-verified; the EXPORT path LIVE-verified
on this box (`--export-only` produced a valid archive with the manifest at root and
the vault dir inside, vault left intact, test archive removed). The DESTRUCTIVE
removal path is render-but-UNPROVEN — deliberately left for a hands-on look-and-feel
run on this backed-up box (the rare round runnable for real here). ORIGINAL SPEC
BELOW (still the requirement; remote layer = increment 2, not yet built):

A 5th family script (§2.8), requested 2026-06-17. Primary near-term purpose: let
the user RUN the real scripts to judge look-and-feel, then RESET between runs
(render-tests don't show the live feel; this is the rare round that can be run
for real on the backed-up test box). Also a real end-user feature.

**Export FIRST — non-negotiable.** The vault holds the user's irreplaceable
imported memory (`05-AI-Sessions/`, notes). Before removing anything, the script
EXPORTS it to a timestamped portable archive (`tar.gz`/`zip`) in a safe dir
(`~/` or `~/Downloads`), and says where. Flags: export default-ON; `--export-only`
backs up WITHOUT removing; `--no-export` skips (with a loud confirm). Never let an
uninstall destroy memory.

**Reverse map (what each installer left):**
- *setup:* vault tree (GUARDED — user data; only after export + explicit confirm),
  `~/.hermes`, `mcpvault` npm global, the Ollama systemd user unit / launchd plist,
  the Claude-Desktop MCP-config merge (restore the saved backup), the
  session-continuity skill, `/tmp` checkpoints + logs, and the `hermes()` launcher
  + `TERMINAL_CWD` lines in the shell rc.
- *configure:* `~/.hermes/config.yaml` + `.env`, same rc launcher lines.
- *ingest:* imported sessions live in the vault (covered by export); `ai-scan-report.md`.
- *Ollama itself + pulled models:* explicit OPT-IN prompt only (shared tool, GB of
  models — never silent). Node.js: do NOT remove (too shared).
- *remote.sh* system changes (sshd drop-in, WireGuard `wg0`, linger, sleep-mask /
  power profile, RustDesk, cloudflare-ddns): security-sensitive — defer to a 2nd
  increment behind a `--remote` flag; first build covers the core stack only.

**Safety (§2.8 + hard rules):** `--help/--version/--yes`, self-contained, idempotent,
bash 3.2, secrets never logged, TTY/non-interactive detection. Default to a DRY-RUN
preview (list exactly what would be exported + removed) and require confirmation to
act; only remove paths WE created (check ownership/markers, never `$HOME` or
unrelated dirs); **NEVER touch `~/.paperclip`**; never `sudo` itself beyond what
reversal genuinely needs (the Ollama unit). Runs from anywhere (no self-copy).
First-build scope: export + core-stack reversal + dry-run; remote layer = increment 2.

## 4.12 Hardware migration / vault portability (RECORDED — restore not yet built)

Surfaced 2026-06-17: the §4.11 export-first archive is, by accident of good
design, the MIGRATION primitive. `--export-only` = "back up my memory without
tearing down the old box yet" — exactly what moving to new hardware needs (keep
the old machine running until the new one works). The architecture already
supports this because the vault is agent-neutral plain markdown (§1) — that is the
unit that moves. What does NOT move VALIDATES the design and must stay out of the
archive:
- **Vault (memory)** → moves. Portable, hardware-independent, cross-OS. ✓
- **`~/.hermes/config.yaml`** → do NOT move. It is tuned to the OLD hardware
  (context_length, model choice, §4.35). The new box must RE-DERIVE it — that is
  configure's job. An upgrade (weak→capable) should flip cloud→local; carrying old
  config across fights that.
- **`~/.hermes/.env` (API keys)** → do NOT auto-bundle. Secrets in a tarball is the
  exact smell §2.7 forbids. Re-enter on the new box, or a separate explicit opt-in.
- **Hermes native `state.db`** → drop. Binary, version-coupled; the markdown vault
  is the durable layer by design. Do not oversell migration as "everything moves".

**BUILT increment (the manifest, §4.11):** every export now carries
`ai-memory-export-manifest.json` at the archive root (schema_version, created_utc,
source os/host/user, vault_dir, exported_by, and explicit includes/excludes +
restore_hint). This is the forward-compat hook so a future restore can recognize
v1 archives — cheap now, awkward to retrofit.

**NOT yet built (next round):**
- **Restore in setup** — auto-detect an `ai-memory-export-*.tar.gz` in Downloads and
  offer "Found an AI-memory export — restore it as your vault? [Y/n]", mirroring
  ingest's existing "found an export, import it?" discovery (consistent idiom, not a
  new one). Prefer auto-detect over a bare `--restore` flag; keep both possible.
- **Discoverability front door** — a user thinking "I got a new Mac, how do I move my
  AI memory?" will never guess `ai-memory-uninstall.sh --export-only`. Document the
  migration narrative (README/Tips) pointing at it; do NOT duplicate the export code
  into a 6th script.
- **configure migration-awareness** — when it detects a restored/populated vault on
  NEW hardware, frame config as a migration ("new machine detected") and actively
  suggest the cloud→local upgrade when the hardware now allows it (ties to §2.11).
Its own design+build round + live test (§5). Keep export (in uninstall) and restore
(in setup) as the two ends; migration is the docs narrative that joins them.

## 4.13 Guided / Expert verbosity mode + the "honest reason" rule (RECORDED — future build)

Revived 2026-06-17 from an earlier suggestion (it was never built — only spec v1.6's
"guided-mode clarity fixes", i.e. rewordings, landed). Today the family has ONE
voice (beginner-leaning, plus the §2.9 reassurance layer) and a SEPARATE
non-interactive axis (`CAN_PROMPT`/`--yes`). The missing piece is an explicit
expert/terse path.

**The rule it carries (this is the point, agreed with the user):** when a script
hands the user a REAL command to type — instead of doing it for them — it must, in
guided mode, state the HONEST REASON, framed as intentional, not as a limitation. The
worked example is the setup→configure boundary: chaining there is NOT forced (correct
— freshly-installed tools aren't on `$PATH` in the current shell; auto-exec would
manufacture an "ollama not found" failure, §4.10/§B4). So setup hands over a real
command — and should say, in guided mode, roughly: "We give you the real command on
purpose: (1) a NEW terminal is how your shell picks up the tools we just installed
(this avoids a real failure), and (2) now you know the actual command, not a magic
button." Honest why + a little dignity for the beginner = trust (§2.9).

**Design (decided with the user; explicit flag only, start narrow):**
- **Guided (DEFAULT)** — audience is beginners. Full "why am I typing this"
  explanations + reassurance + `calm()` lines.
- **Expert (`--expert`, explicit flag ONLY)** — trims the rationale paragraphs but
  KEEPS the `▶ NEXT` command and every safety guard. No auto-detection of skill
  level (guessing annoys both sides — user's call).
- **Auto / non-interactive** — already exists via `CAN_PROMPT`/`--yes` (CI, piped);
  that is the orthogonal third "mode", just not named.
- A family-wide convention (§2.8): one verbosity notion every script reads, so the
  guided explanations live uniformly, not hand-tuned per script.
- **Start narrow:** first pass covers only the "forced real command" hand-off moments
  (setup→configure, new-terminal/PATH cases) — prove the convention, then widen
  (§5.2 "fix what's broken before going broad"). Principle to bake in: guided, never
  TRAPPED — every step keeps the "Ctrl+C anytime, re-run to resume" escape.
Not built; its own round. ASCII-art polish (small, shared motif, TTY-guarded) is
explicitly LOW priority / end polish, parked alongside this.

## 5. Build-round working agreements

Proven by the X230 live run: the sandbox lies. Every serious bug that night
(context floor, exit-status-1, the cloud-only gap, the no-download-check)
passed sandbox testing and only surfaced on real hardware. The workflow below
exists because of that.

### 5.1 Workflow (every build follows this)
1. Raise reasoning level (medium/high to build; high for review rounds).
2. Lock a SMALL, coherent bundle — never the whole backlog at once.
3. Build + sandbox-test (catches syntax, logic, the gross failures).
4. Pattern-hunt (see 5.3) — not just point-fixes.
5. LIVE-test on real hardware before calling it "done" — the only honest bar.
6. User feedback -> next bundle.

Prefer doing build work in Claude Code on a real machine so step 5 is the
normal case, not an afterthought. The machine must be backed up first
(the kraftvagn lesson) and Claude Code's permission prompts left on.

### 5.2 Build order
Fix what's BROKEN before adding what's MISSING. New features (backup, LiteLLM
gateway, mode selection) are built on top of setup/configure — building them
on buggy foundations means building on rot. Bug-fix bundle first, each new
feature as its own later build with its own live test.

### 5.3 Pattern-hunt principle (a bug is rarely alone)
For every bug found, ask "where else does this CLASS of bug live?" before
moving on. Known classes from the X230 run:
- **Assume-without-verify:** configure wrote a model name without checking it
  was downloaded. Audit everywhere: does ingest validate an export zip before
  opening it? Does remote confirm a key works before hardening? Rule:
  verify before you act.
- **Write-blind-don't-preserve:** configure may overwrite ~/.hermes/.env
  instead of reading the existing key first. Audit: does it overwrite
  config.yaml a re-run should preserve? Does setup clobber anything on re-run?
  Rule: read-preserve-ask, don't blind-write.
- **Write-against-unknown-limit:** context_length written below Hermes' 64K
  floor. Audit: other values written without knowing the receiver's required
  range?

### 5.4 Verification & honesty
- Every external integration verified against its current source.
- Sandbox-test every path testable without real hardware; flag honestly what
  could only be tested synthetically.
- Review rounds ("fresh eyes") are mandatory before release.
- **Live-test must RE-RUN — idempotency is part of "done."** A first-install
  `exit 0` hides re-run crashes: the set_env bug (2026-06-18) returned non-zero
  once a key already existed and aborted configure on every re-run, yet the first
  install passed clean. Run each script at least TWICE back-to-back (both must
  exit 0) before recording/shipping. "The sandbox lies" (§5) now extends to
  **"the first run lies."**

## 6. Next-phase plan (2026-06-18) — KEYSTONE-FIRST (decided with the user)

Captured before a /clear. Sequencing decided: keystone first; cross-platform
hardening in parallel; a design review gates the keystone build.

**Track 1 — KEYSTONE (the soul, §4.3.1) — FIRST.** Build the HANDOVER:
always-loaded orientation + ABSOLUTE vault paths + an import INDEX + per-door
verification that forces a REAL tool call returning vault content. Opening
investigation (do these first; the live Mac dashboard is the rig):
  - WHY does the dashboard root at `~/.hermes/hermes-agent`, not the vault? Does
    it chdir, or spawn `hermes --tui` with a fixed cwd? (Decides whether cwd is
    fixable at all, or we must go cwd-independent via global instructions — the
    assumed answer.)
  - Is `agent.tool_use_enforcement` (config.yaml) — or the system prompt the
    dashboard injects — the lever for the tool-REFUSAL? qwen3.5 denied having
    tools in the TUI, yet `-z … --yolo` from the terminal DID call them. Find the
    difference.
  - WHERE does Hermes load GLOBAL/user-level instructions applied to EVERY session
    regardless of cwd/door? That is where the handover must live.
  Done = ask the memory question THROUGH THE BROWSER, get a grounded answer citing
  a real imported file (ground truth: 8 convs, e.g. "OpenClaw på Mac Mini").

**Track 2 — Cross-platform hardening (parallel).** A differential harness: same
script + same fixtures across {macOS-arm64 (Mac), linux-x86 (X230), linux-arm64
(a VM on the Mac — the user's idea, and the real gap)}, capture + DIFF outputs,
auto-flag divergences. Keep it as a repo artifact, not a one-night run. WSL2
already proven. Mac and X230 are both real hardware in hand — diff those before
building the VM.

**Track 3 — OS-abstraction refactor (with Track 2).** The pipefail/platform bugs
are symptoms of scattered `if macos…else…`. Replace with ONE thin layer of
portable helpers (`os_primary_ip` / `os_enable_service` / `os_pkg_install`) so
platform logic lives in one place and the bug class can't keep re-breeding.

**Track 4 — Critical design review (gate BEFORE the Track-1 build).** Fresh eyes
on the keystone design before building it, and on the OS-abstraction boundary.

**Carry-along product decisions:**
  - Ship a `doctor`-style **reachability verifier** ("prove my memory is reachable
    from every door") — it IS the keystone verification AND a standout feature no
    competitor ships.
  - **Model-floor honesty in-product:** qwen3.5 (14B) was too weak — it refused
    tools in the dashboard. Recommend a cloud fallback for memory + document a
    minimum capable model (§4.2 intersection).

**Strategic framing (why keystone leads):** the FRIENDLIEST door — the web
dashboard a beginner reaches for — is the MOST broken for memory (wrong cwd + weak
model refusing tools). So the keystone is not just a bug fix; it is the GATE to a
viable beginner experience and the §1 vision. The components are commodity; the
honestly-verified last hop is the project's actual contribution.

**Operational state at this pause:** the Mac runs a working local AI
(Hermes → Ollama qwen3.5). `hermes dashboard --tui` is UP (Mac pid 12749),
reached via an SSH tunnel `ssh -fNL 9119:localhost:9119 kv@192.168.38.229` →
Brave `http://localhost:9119` — left running on purpose. All code committed +
pushed (origin/main 733021d); v13 bundle in ~/Downloads.
