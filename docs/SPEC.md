# AI Memory Stack — Specification

**This is the living, normative spec.** It says what the system *is* — vault
format, family conventions, design doctrine — in present tense, without the
build history. The full design journal it was extracted from lives at
[`docs/history/REQUIREMENTS.md`](history/REQUIREMENTS.md) (frozen); what has
actually been *proven*, where, is recorded in [`TESTING.md`](../TESTING.md),
the provenance ledger. When code and this spec disagree after a real test,
fix the code **and** correct the spec.

A **section map** at the bottom translates the old `§` numbers (still cited in
script comments and the journal) to sections here.

---

## 1. Vision

A local-first system that consolidates a person's scattered AI conversations
into one vault they own, and runs a persistent local agent (Hermes) on top of
it — installable on a brand-new machine by a non-expert, useful to others, not
just the original author.

Guiding principles (they apply to every component):

- **Local-first.** No cloud accounts required. Cloud APIs are optional
  fallbacks only; the local disk is always the source of truth.
- **Agent-neutral vault.** Plain markdown on disk; survives any single tool's
  death.
- **Recommend, don't decide.** The system proposes (models, updates, daemons);
  the user approves. Nothing self-modifies or auto-updates.
- **Generic by default.** No author-specific hardware, language, workflow, or
  personal data baked into shipped artifacts. English everywhere.
- **Verify against the source; the sandbox lies.** Real behaviour on real
  hardware is the bar. A green log that did nothing is a bug, not a success.

## 2. The vault

The vault is an Obsidian-compatible folder of plain markdown, by default
`~/Documents/ai-memory`. It is the only thing that must survive; everything
else is re-derivable.

- `05-AI-Sessions/<source>/` — imported conversations, one `.md` per
  conversation, named `<date>-<slug>-<id>.md`. The **id is the identity**
  (dedupe key); the slug is cosmetic and never changes after first import.
  The directory is append-only in normal operation.
- `05-AI-Sessions/INDEX.md` — a derived, regenerable manifest of everything
  imported (per-source and by-month counts, grouped listing). It is what turns
  "imported-but-not-found" from a silent gap into a detectable mismatch.
- `00-Inbox/` — notes the agent reads at startup (e.g. the Update Advisor's
  `UPDATES.md` report).
- Entity/profile files — distilled markdown the agent maintains.
- `.tools/` — the family scripts self-install here on first run; all docs
  reference this home so instructions don't depend on where files were
  downloaded.
- `.mcp/ai-config.json` — the machine-readable model endpoint record
  (real `base_url`, model tag) other tools can read.

**Hard rule: the vault never contains secrets.** That is what makes the vault
and its export archive safe to move over USB / scp / cloud / email.

## 3. The script family

Eight self-contained bash scripts, run in this order (the last two optional):

| Script | Role |
|---|---|
| `ai-memory-setup.sh` | zero-prerequisite installer (packages, Node, Ollama, Hermes, vault scaffold; `--restore` merges a vault export) |
| `ai-memory-configure.sh` | hardware analysis → model choice (local / remote-Ollama / cloud) → writes Hermes config, keys, launcher, hooks |
| `ai-memory-ingest.sh` | multi-source history import into the vault; idempotent; rebuilds INDEX.md |
| `ai-memory-doctor.sh` | read-only per-door reachability verifier (opt-in `--live` recall round-trip) |
| `ai-memory-search.sh` | deterministic vault retrieval; also the `pre_llm_call` recall hook |
| `ai-memory-mux.sh` | the standard interface: two-pane tmux cockpit for the agent |
| `ai-memory-uninstall.sh` | export-first reversal, dry-run by default; `--backup` alias |
| `ai-memory-sync.sh` | optional: add-only push of one machine's history to a central vault |

`ai-memory-mux.sh` is the standard way to talk to the agent: a tmux session
with the vault chat pane and a working terminal pane side by side, mouse
support on, applied at session scope (a user's `~/.tmux.conf` is never
touched); plain `hermes chat` remains the supported no-tmux path.

The fleet/remote layer (the `remote` node-setup script, the netboot sketch)
was split into the companion repo **`local-ai-memory-fleet`** in July 2026 so
that nothing in this family can lock you out of a machine; its normative
content lives there.

### 3.1 Family conventions (what lets the family grow)

Any number of scripts can join the chain if they follow the shared
conventions:

- Naming: `ai-memory-<role>.sh`; a single self-contained file.
- Self-copy to `$VAULT/.tools/` on first run; all docs reference that home.
- Standard flags everywhere: `--help`, `--version`, `--yes`.
- Shared behaviors: idempotent checkpoints, human-in-the-loop checkpoints for
  GUI actions, TTY/non-interactive detection (probe `/dev/tty` by *opening*
  it, not `[[ -r/-w ]]`), bash 3.2 compatible, secrets never logged.
- Chain: every script ends by pointing at the literal next command
  (a `▶ NEXT` footer as the last thing on screen).
- Versioning: a script's version lives in its header, `--version` output, and
  banner, plus a line in `PACKAGE_VERSION.txt`; the test harness fails on
  drift between them.
- A future `ai-memory.sh` menu/dispatcher is allowed but not required.

## 4. The dividing line — deterministic work is a script, messy reality is an agent

The parts of the stack that meet **predictable, deterministic** work —
install, configure, back up, search — are **bash scripts**: fast, free,
reviewable, repeatable, no tokens, no surprises.

The parts that meet **messy, unpredictable, changing reality** — the zoo of AI
export formats each vendor changes on its own schedule — suit an **agent**: an
LLM can *interpret* an unknown export instead of needing a fixed schema.

The dividing line for every feature:

- Deterministic / stable / must-be-exact → script.
- Messy / variable / needs interpretation → agent, or a hybrid.

**Ingest is the decided hybrid:** the script keeps recognition + import +
idempotency for known-good formats (the fast lane); anything AI-ish it does
not recognize goes to the agent lane via `--scan-report`, which imports
nothing and writes a neutral bridge file (recognized exports + exact import
command; unknown candidates + why they matched). The agent-facing prompt lives
in `docs/collect-with-agent.md`, **never embedded in the script** — a durable
script must not be coupled to a fast-moving agent's interface. A new vendor
format is useful immediately (it surfaces in the report; the agent handles
it); a hardcoded parser is added only when a format is common enough to
deserve the fast lane.

The same line governs routing: rule-based fallback between model backends
(deterministic triggers the user approves) is in scope; semantic
"judge-the-request" routing is agent territory and out of scope.

## 5. Reachability — the keystone

The project's core promise: *"I imported my history and the AI can actually
reach it."* Reachability that depends on **how** you launch the agent is not
reachability — every door (shell `hermes chat`, web dashboard, TUI, gateway
and its messaging channels, any future entry point) must reach the vault, or
the promise breaks precisely when the least-technical user walks through the
friendliest door.

The doctrine, in layers:

1. **A cwd-independent handover.** `configure` writes a marker-bounded
   orientation block into `~/.hermes/SOUL.md` — injected into every session
   regardless of launch directory or door. It carries: the **absolute** vault
   path, the search-persistence recipe (don't stop at the first empty grep;
   try synonyms, both languages, acronyms; read INDEX.md; never claim "empty"
   without listing the folder), and explicit "actually CALL the tool, don't
   describe it" wording.
2. **Belt and suspenders for cwd:** the `hermes()` shell launcher `cd`s into
   the vault **and** exports `TERMINAL_CWD`, so doors that ignore cwd (the
   dashboard, the gateway) inherit the vault root via the environment.
3. **A derived INDEX** (see §2) so a generic "what do you remember" question
   has a real manifest to read, and so import-vs-searchable mismatches are
   detectable rather than silent.
4. **The model floor.** A model can be capable enough to chat yet too weak to
   *drive* file-search tools — then memory silently appears broken though
   everything is wired right. `configure` warns when a weak model is chosen
   for memory work and recommends a capable (possibly cloud) model.
5. **Deterministic search — `ai-memory-search.sh`.** Live rounds proved the
   real floor is not model size but a small model's inability to carry out a
   multi-step search strategy. Multi-term, INDEX-aware, persistent search is
   deterministic work, so it is a script: it tokenizes the query (stopword
   lists, keeps domain words), scores every session file by distinct query
   terms covered (coverage dominates) then hit frequency, and prints the top
   files with the best-matching lines already quoted — one tool call instead
   of a strategy.
6. **The recall hook — the keystone's last hop.** Even with the tool
   installed, small models won't reliably *decide* to call it. So recall must
   not depend on the model deciding anything: `ai-memory-search.sh --hook` is
   a Hermes `pre_llm_call` hook — Hermes passes each user turn as JSON on
   stdin, the hook searches the vault and returns `{"context": ...}`, which is
   appended to the user message. Any model, however small, simply reads the
   hits. It stays silent on weak/no hits, chit-chat, and non-user turns.
   `configure` registers it (with `hooks_auto_accept: true` so a headless
   agent fires it without a TTY prompt).
7. **Verification, not assumption — `ai-memory-doctor.sh`.** Read-only,
   deterministic checks: vault present; INDEX in sync with disk; handover
   present with absolute paths; door wiring (launcher + `TERMINAL_CWD`); model
   floor; and a model-free **searchability proof** run from a foreign cwd.
   Opt-in `--live` does one real recall round-trip and must confirm **actual
   tool calls returning vault content** — a plausible worded answer does not
   count. A missing interpreter is a warn/fail, never a silent pass.

Closing the loop, the agent's own sessions flow back into the vault: Hermes
session hooks run a local-sources ingest sweep on session start/end —
OS-general (no per-OS scheduler), idempotent, and running inside the agent's
own process (which on macOS holds the Full Disk Access the vault needs).

## 6. Hardware and models

| | Minimum | Recommended |
|---|---|---|
| RAM | 8 GB (3B models — limited) | 32–48 GB (32–35B models) |
| Disk free | 20 GB | 60+ GB |
| Platform | macOS 12.4+ · Linux (apt/dnf/pacman) · Windows via WSL2 | Apple Silicon or NVIDIA GPU |
| Network | needed for install only | — |

- Below ~6 GB usable RAM, `configure` switches to **cloud-only** mode
  (Hermes via OpenRouter) — an old machine still works; nothing heavy runs
  locally.
- Model sources are **three**: local Ollama, a *remote* Ollama on another LAN
  machine (`--remote-ollama=HOST[:PORT]`), and cloud (OpenRouter).
- Local models must clear Hermes' 64K context floor with **two** values:
  `context_length` (what Hermes believes) *and* `ollama_num_ctx` (what Ollama
  actually loads). Both ≥ 64K; context_length is the model's real max when
  higher, never below the floor.
- A working existing config **survives a re-run**: if the configured endpoint
  answers a probe, keeping it is the default, and under `--yes` it is never
  overwritten. An existing fallback chain is the user's own.
- With the search recipe and hook in place, the practical local floor is a
  ~5 GB model; the real limiter on a big-RAM box is the KV-cache of the
  configured context, not the weights.

## 7. Privacy and secrets

- Default discovery only looks in known per-tool locations plus a targeted
  scan of `~/Downloads` for export ZIPs, and asks before importing.
  `--scan DIR` adds locations; `--deep-scan` (opt-in, warned) is limited to
  the home directory — never whole-disk.
- **Secrets never travel in an export**, never appear as CLI arguments (shell
  history / `ps`), never land in the tee log, and never enter the vault.
  Anything secret is read with `read -s`; keyfiles are `chmod 600`
  (`~/.hermes/.env`, `~/.config`). Ingest scrubs known key patterns from
  imported conversation text.
- Private keys never leave the machine they were generated on; public keys
  are distributed (e.g. via `github.com/<user>.keys`); revocation is removing
  one line from `authorized_keys`.
- Nothing self-modifies or auto-updates; the Update Advisor is read-only and
  only *reports*.
- GitHub and any other third-party cloud are opt-in, never assumed; the local
  copy is always the source of truth.

## 8. Migration and multi-machine

The vault is the unit that moves; config is re-derived on purpose.

- **One-time move:** `uninstall --backup` (alias for `--export-only`) writes a
  timestamped `tar.gz` with a secret-free migration manifest at the archive
  root → `setup --restore` on the new box merges it (and auto-offers when it
  finds an export in `~/Downloads`) → `configure` re-derives config for the
  new hardware (and detects the migration: populated vault, no prior config)
  → `doctor` verifies.
- **Not in the archive, by design:** `config.yaml` (tuned to the old
  hardware), API keys (secrets never travel), Hermes' internal `state.db`
  (binary, version-coupled — the markdown vault is the durable layer).
- **Two machines, one vault:** plain files sync with git / Syncthing / etc.;
  keep `config.yaml` and `.env` out of the sync (per-machine + secrets).
- **Hub-and-spoke:** `sync` pushes a satellite's sessions to a central vault
  **add-only** (`--ignore-existing`) — no clobber risk on the central, which
  is why filenames never change after first import (a rename would become a
  duplicate on the central).

## 9. Dangerous surfaces

One script can do irreversible things; it is isolated and gated (details and
current rails in `SECURITY.md`):

- `ai-memory-uninstall.sh` — export-first, dry-run by default; deleting
  without an export demands an un-skippable typed confirm even under `--yes`.

The lock-you-out surface (the `remote` node-setup script: sshd hardening,
WireGuard, and its rails) lives in the companion repo `local-ai-memory-fleet`
since July 2026 — nothing left in this repo can lock you out of a machine.

## 10. Out of scope

- Whole-disk scanning, auto-updates, any self-modifying behavior.
- Semantic per-request model routing (Level B) — agent territory.
- Hermes-native memory backends (state.db import skill, Memory Provider
  plugin) — separate upstream projects.
- Remote/fleet access (sshd hardening, WireGuard/Tailscale node setup, NAT
  traversal, netboot) — moved to the companion repo
  `local-ai-memory-fleet` (July 2026).

## 11. Build discipline

- **The sandbox lies, and the first run lies.** `bash -n` + a clean run is
  the floor; real behavior on real hardware is the bar. Run each changed
  script at least twice back-to-back (idempotency is part of "done"). A path
  that could only be parse-checked or sandbox-run is **written-but-unproven**
  — never "done". Record what actually ran, where, in `TESTING.md`.
- **Pattern-hunt every real bug:** fix the *class* across the whole family,
  not the instance. Known classes: assume-without-verify;
  write-blind-don't-preserve (read-preserve-ask instead);
  write-against-unknown-limit.
- **Small coherent bundles**; fix what's broken before adding what's missing.
- **When a live test contradicts the spec, fix the code and correct the
  spec.** The spec is "truth" only because we keep it true.

---

## Section map (old journal `§` → this spec)

Script comments and `docs/history/REQUIREMENTS.md` cite the journal's section
numbers. They resolve here as follows:

| Old § (journal) | Topic | Here |
|---|---|---|
| §1 | Vision & principles | §1 |
| §2, §2.1–2.7, §2.9–2.11 | Per-script requirements, reassurance layer, gateway | §3 (family), §4 (routing), history for details |
| §2.3.1 | search + `--hook` | §5 (items 5–6) |
| §2.3.2 | self-ingest hooks | §5 (closing paragraph) |
| §2.8 | family conventions | §3.1 |
| §3 | out of scope | §10 |
| §4 | hardware table | §6 |
| §4.1 | WSL support | §6, history |
| §4.2 | model capability floor | §5 (item 4) |
| §4.3 / §4.3.1 | import→reachable gap; keystone/every-door doctrine | §5 |
| §4.35 | dual context values | §6 |
| §4.5 | script-vs-agent dividing line | §4 |
| §4.55 | `--scan-report` bridge | §4 |
| §4.6 / §4.7 | GitHub opt-in; agent-prompt decoupling | §7, §4 |
| §4.8 / §4.9 | remote-node risk + fallback ladder | §9, §10 (content now in the companion repo `local-ai-memory-fleet`) |
| §4.10 / §4.13 | NEXT footers; guided/expert modes | §3.1, history |
| §4.11 / §4.12 | uninstall; migration/portability | §9, §8 |
| §5 (journal) | build workflow & pattern-hunt | §11 |
| §6 (journal) | 2026-06 phase plan | history |
