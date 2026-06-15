# AI Memory Stack — Requirements Specification v1.13

Status: agreed baseline for the next build round (June 2026).
v1.13 (CC, package v4): §4.3 + §4.2 fixes BUILT and live-verified on real
hardware — vault launcher baked into configure (writes a `hermes()` shell
launcher + TERMINAL_CWD), ingest gained a post-import reachability check,
setup's generated AGENTS.md now carries an explicit search recipe, and
configure warns on a weak model. LIVE FINDING (corrects §4.3): TERMINAL_CWD is
INEFFECTIVE for Hermes' local terminal/file tools — the shell launcher is the
proven fix (kept TERMINAL_CWD as harmless belt-and-suspenders). v1.12 adds: §4.2 model-capability floor for memory/tool-use (a too-weak model
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

### 2.9 Reassurance & feedback layer (next build) — "they thought of everything"

Goal: a user who trusts the script does not Ctrl+C mid-download, so calm IS
stability. All of the following are messaging/feedback, not new behavior:

- **Bandwidth probe (default on, `--no-speedtest` to skip):** a small timed
  download (~5 MB) measures the link. Honest caveat printed: measured now,
  real speed varies.
- **Two-stage download estimate:** setup prints a rough total
  ("~2–3 GB tools + the model you pick later"); configure, AFTER hardware
  analysis, prints the exact figure ("your machine → qwen3:35b, 20 GB;
  at ~50 Mbit ≈ 55 min").
- **Per-step "safe to interrupt" line:** every long step states
  "Safe to Ctrl+C — re-running resumes where it stopped." (We already have
  checkpoints; this just communicates them.)
- **"What's happening and why" before slow steps:** e.g. "Apple is
  downloading ~700 MB of developer tools, no progress shown — this is normal."
- **Surface real progress:** stop hiding Ollama's own download percentage
  behind the spinner; show step counter ("step 3 of 7").
- **Optional live log hint:** "want to watch? open another terminal:
  tail -f <log>".
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

## 4.55 Scan-to-report option — map messy data, let the agent act (next build)

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

**BUILT + live-verified (package v4, CC) — configure v4.3 / ingest v2.5 / setup v8.7:**
- configure now installs a `hermes()` launcher (`( cd "$VAULT" && command hermes "$@" )`)
  into the user's shell rc (.bashrc/.zshrc, idempotent marker block) and sets
  TERMINAL_CWD in ~/.hermes/.env. Closing message tells the user to open a new
  terminal so it takes effect.
- ingest does a post-import reachability check (launcher/TERMINAL_CWD present?);
  if not, it prints a loud "a plain hermes may NOT see this" instruction instead
  of a falsely-happy summary.
- setup's generated AGENTS.md step 3 upgraded from soft "consult it" to an
  explicit recipe: `grep -rli "KEYWORD" 05-AI-Sessions/` then read matches.
- LIVE PROOF (real hardware, /proc-verified): BEFORE (no launcher, from /tmp) →
  worker cwd=/tmp, "NONE FOUND, 05-AI-Sessions does not exist". AFTER (launcher
  active, even launched from /tmp) → worker cwd=vault, found 19 claude-web files
  for "outlander". TERMINAL_CWD alone (launched from /tmp) did NOT fix it — the
  launcher is what works.

Also clarified (not a bug): "list memory returns empty" is expected — the vault
import is plain markdown reached by file search, NOT entries in Hermes' native
state.db memory. Seeding native memory is the optional USER.md/MEMORY.md step
(§2.3), separate from import.

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
  **BUILT (configure v4.3):** `warn_weak_model` fires on small/cheap tags
  (*mini*, *:0.5b/:1b/:2b/:3b*, gpt-3.5, gemma:2b, tinyllama, phi-2, ...) right
  after the model is chosen. Live-verified: choosing openai/gpt-4o-mini prints
  the warning. It warns, does not block (recommend-don't-decide).
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

## 4.8 Known untested surface (honest)

Of the four scripts, **remote.sh is the only one never run on real hardware.**
Its sudo/WireGuard/Cloudflare/RustDesk paths are syntax-checked and
sandbox-reasoned only. setup, configure, and ingest have all had real live
runs (X230). Before remote.sh is relied on, it needs a live test on a real
node — treat its current state as "written carefully, unproven."

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
