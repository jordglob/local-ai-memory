# AI Memory Stack — Requirements Specification v1.2

Status: agreed baseline for the next build round (June 2026).
v1.2 adds: power-outage recovery chain + pull-the-plug test, manual
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
- Repo: `github.com/jordglob/local-ai-memory` (decided).

### 2.7 `ai-memory-remote.sh` (remote access for nodes — new, standalone)

Opt-in, node-side. Never part of setup.sh.

- **SSH:** enable Remote Login (macOS) / openssh-server (Linux); install the
  user's public key (paste, file, or `https://github.com/<user>.keys`);
  offer to disable password login **only after key login is verified**.
- **Tailscale:** install; `tailscale up` auth URL handled as a checkpoint
  (open link → approve → verified via `tailscale status`). Default
  recommendation, with plain WireGuard documented in Tips as the
  no-cloud-control-plane alternative.
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

---

## 4. Minimum / recommended hardware (to document everywhere)

| | Minimum | Recommended |
|---|---|---|
| RAM | 8 GB (3B models — limited) | 32–48 GB (32–35B models) |
| Disk free | 20 GB | 60+ GB |
| Platform | macOS 12.4+/Linux (apt/dnf/pacman) | Apple Silicon or NVIDIA GPU |
| Network | needed for install only | — |

---

## 5. Build-round working agreements

- Reasoning level: medium/high for code and document production; high for
  review rounds; review rounds ("fresh eyes") are mandatory before release.
- Every external integration verified against its current source.
- Sandbox-test every script path that can be tested without real hardware;
  flag honestly what could only be tested synthetically.
