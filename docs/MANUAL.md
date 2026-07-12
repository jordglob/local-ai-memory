# The AI Memory Stack — User Manual

*Your conversations, your disk, your agent.*

Written from the user's side of the screen: what you do, what happens, what is
guaranteed. This manual describes the system **as built** (July 2026) — where
reality and this document disagree, reality wins and the document gets fixed.

---

## 1 · What this is — and what it is not

The AI Memory Stack turns one folder on your own disk into the permanent memory
of every AI conversation you have ever had — and puts a local AI agent on top of
it that can actually remember them. You export your history from Claude,
ChatGPT, Gemini and a dozen other tools; the stack imports everything into one
**vault** of plain markdown files; a local model (or, on weak hardware, a cloud
model) answers questions *with that history injected into its context*. Nothing
about your past is stored in anyone's cloud account.

**It is:**

- A family of eight self-contained scripts you run in order. No app to install,
  no daemon to babysit, no account to create.
- Local-first: the vault is ordinary `.md` files, readable in any editor (and
  Obsidian-compatible), forever.
- Reversible: the uninstaller exports everything *before* it removes anything,
  and runs as a dry-run until you say otherwise.

**It is not:**

- A consumer product. There is no support line and no GitHub issues — by
  design. You are expected to be able to read bash, or to know someone who can.
- A sync service. Multi-machine use works over plain files (git, Syncthing,
  rsync) precisely because the vault is plain files.
- A remote-access tool. Nothing in this repo can lock you out of a machine; the
  heavier fleet tooling (sshd hardening, WireGuard, netboot) lives in the
  companion repo `local-ai-memory-fleet` and carries its own warnings.

### The one-paragraph mental model

Everything revolves around a single folder: `~/Documents/ai-memory` — **the
vault**. Importers fill it (`ingest`). An agent reads it (wired up by
`configure`). A recall hook makes sure the agent *actually uses* it on every
question (`search`). A doctor proves the whole loop works (`doctor`). And a
tmux cockpit (`mux`) is the standard place you talk to it all.

## 2 · Concepts you will meet

| Term | Meaning |
|---|---|
| **vault** | The folder of markdown that *is* your memory. Numbered subfolders; imported conversations land in `05-AI-Sessions/`, one file per conversation, append-only. |
| **door** | Any way of reaching the vault: the Hermes agent, Claude Desktop (via MCP), plain grep, Obsidian. The design goal is that every door opens onto the same memory. |
| **INDEX.md** | A generated table of contents over all imported conversations — what the recall hook and "what did we do last week?" questions lean on. |
| **recall hook** | Before every question reaches the model, a fast lexical search runs over the vault and injects the best-matching lines into the prompt. This is the piece that makes small local models remember instead of guess. |
| **hash line** | Every imported file carries its conversation id and a content hash. That is how re-runs stay idempotent — and how the importer notices you edited a file by hand and refuses to overwrite your edits. |
| **local / cloud mode** | Configure measures your RAM and GPU and either picks a local Ollama model that fits, or (below ~6 GB) flips to cloud-only mode through OpenRouter, so an old laptop still works. |
| **export archive** | A timestamped `tar.gz` of the vault (plus the agent's own memory database), produced by uninstall/backup. It contains no secrets — API keys and machine config are deliberately excluded and re-created on a new machine. |

### The script family at a glance

| Script | Run it | What it does |
|---|---|---|
| `ai-memory-setup.sh` | once | Installs the base stack: system packages (incl. tmux), Node, Ollama, the Hermes agent, the vault skeleton. Resumable; safe to re-run. |
| `ai-memory-configure.sh` | once + after changes | Detects hardware, picks a model, writes Hermes config, installs the recall hook and the vault-rooted `hermes` launcher. |
| `ai-memory-ingest.sh` | any time | Imports your AI history from exports and local tool stores. Idempotent; re-run whenever you have new exports. |
| `ai-memory-doctor.sh` | any time | Read-only health check: is memory reachable from every door? |
| `ai-memory-search.sh` | (automatic) | The recall engine behind the hook; also usable by hand. |
| `ai-memory-mux.sh` | daily | **The standard interface**: a mouse-friendly tmux cockpit — agent chat and a working terminal side by side. |
| `ai-memory-sync.sh` | optional | Pushes this machine's vault to a central one (add-only). |
| `ai-memory-uninstall.sh` | if leaving | Export-first, dry-run-by-default reversal. Also the backup tool (`--backup`). |

Remote access / node provisioning (`ai-memory-remote.sh`) lives in the
companion repo **local-ai-memory-fleet** — see §8.

## 3 · Installing on a fresh machine

### What you need

- Linux (apt/dnf/pacman), macOS 12.4+, or Windows via WSL2.
- 8 GB RAM minimum; 32–48 GB recommended for a strong local model. About 20 GB
  free disk (60+ GB recommended).
- Absolute beginner, or a machine with no OS at all? **GET-STARTED.md** is the
  single beginner path — it starts from a blank disk and a USB stick and
  assumes nothing, not even `git`.

### Path A — download and run (recommended the first time)

Get the project (git clone, or GitHub's *Download ZIP* — the README shows a
Python one-liner that unzips without `unzip` installed), open a terminal in the
folder, then:

```
bash ai-memory-setup.sh
```

Setup explains each step, asks for your password only when it must, and prints
the exact next command when it finishes. The chain is always
**setup → configure → ingest → doctor → mux** — each script ends by telling you
the next one, so you are never left guessing.

### Path B — one line (once you trust it)

```
curl -fsSL https://raw.githubusercontent.com/jordglob/local-ai-memory/main/bootstrap.sh | bash
```

### What actually happens

- Package manager bootstrapped (Homebrew on macOS), then git, python3, tmux,
  Node 22, Ollama, and the Hermes agent (asked first).
- The vault skeleton is created at `~/Documents/ai-memory`, and the scripts
  install themselves into the vault's `.tools/` folder — after that you can
  delete the download.
- Every download is saved to disk first, then run — nothing pipes straight from
  the network into a shell with your password.
- Interrupted? Ctrl-C is safe at any point. Re-run the same command: completed
  steps are skipped, the interrupted one resumes.

### The decisions you will be asked to make

The guided run keeps real questions to a handful, and every yes/no default is
the safe choice — when in doubt, press Enter:

1. **Install the Hermes agent?** Yes — it is the "your agent" half of the
   promise.
2. **Where should the model run?** Local / cloud / both — configure recommends
   based on your measured hardware, and shows the download size and required
   disk before pulling anything.
3. **One API key** (only if you chose cloud): an OpenRouter key — see §9 for
   exactly where it lives and why.
4. **Import your history now?** Hands over to ingest (§5).

> **Moving from another machine instead of starting fresh?** Run
> `bash ai-memory-uninstall.sh --backup` on the old machine, copy the archive
> over, and run `bash ai-memory-setup.sh --restore` on the new one. Keys and
> model choice are deliberately *not* in the archive — configure re-derives
> them for the new hardware.

## 4 · Configuration: matching the model to the machine

`configure` measures RAM and GPU and recommends accordingly:

| Hardware | Mode | Model class |
|---|---|---|
| < 6 GB RAM | cloud-only | Nothing heavy runs locally; Hermes talks to OpenRouter. |
| 8–16 GB | local, modest | 3B–14B — works, with honest caveats about recall reliability; the recall hook does the heavy lifting. |
| 32–48 GB | local, strong | 32–35B — the intended experience. |

Configure also installs the two pieces that make memory *actually* work rather
than theoretically work:

- **The vault launcher.** Typing `hermes` anywhere opens the agent rooted at
  the vault, so its file tools land in your memory instead of whatever folder
  you happened to be in.
- **The recall hook.** Registered in Hermes' config: every user question first
  passes through the lexical search; strong matches are injected as context.
  Live testing drove this design — without injection, models below ~30B
  routinely *pretended* to have searched.

Re-run configure any time — it keeps working custom settings unless you
explicitly replace them, and it is the right tool after a RAM upgrade, a new
GPU, or switching between local and cloud.

## 5 · Importing your history (ingest)

Ingest reads exports and local tool stores, normalizes everything into one file
per conversation, and is safe to re-run forever: unchanged conversations are
skipped, grown ones are extended, and **files you have edited by hand are
detected and left alone** — a warning tells you which ones.

### Where it looks

- **Export files** in `~/Downloads` (it asks before importing anything found):
  Claude.ai, ChatGPT, Google Takeout (Gemini), AI Studio.
- **Local tool stores**, found automatically: Claude Code, Codex CLI, Gemini
  CLI, OpenClaw, Cursor, Aider, LM Studio, Open WebUI, and Hermes' own history.
- On WSL it offers to scan your **Windows** Downloads too — where browser
  exports actually land.

### Safety properties

- **Secrets are scrubbed** from message bodies, titles and filenames before
  anything is written: API keys (OpenAI, Anthropic, Google, GitHub incl.
  fine-grained PATs, AWS, Slack, Stripe), JWTs, private-key blocks.
- **Writes are atomic** — a crash or Ctrl-C mid-import can never leave a
  half-written conversation.
- **A failed source is loud**: the summary table shows imported / skipped /
  edited / failed per source, and the script exits non-zero if anything failed.
- Messy pile of unknown exports? `--scan-report` maps a folder into a bridge
  file your agent can read and act on with you.

## 6 · Daily use

```
bash ai-memory-mux.sh
```

The standard way in: a tmux cockpit with the agent chat in one pane and a
working terminal beside it, mouse on — click between panes, scroll with the
wheel. (No tmux, or prefer plain? `hermes chat` does the same conversation
without the cockpit.)

Ask it what you worked on last month; the recall hook pulls the evidence lines
out of the vault before the model answers. New conversations you have with the
agent are themselves swept into the vault at session end (self-ingest), so the
memory keeps itself current without you doing anything.

- **Search by hand:** `bash ai-memory-search.sh "wireguard port"` — the same
  engine the hook uses.
- **Browse:** open the vault in Obsidian or any editor. It is just markdown;
  edit freely — ingest will not overwrite your edits.
- **New exports?** Download them, re-run `bash ai-memory-ingest.sh`.

## 7 · Health check, backup, leaving

### Doctor — trust, but verify

`ai-memory-doctor.sh` is read-only and answers one question: *is your memory
actually reachable from every door?* It checks the vault, the index, the
launcher, the hook wiring, and (with `--live`) provokes a real agent search.
Run it after any change; a green doctor is the project's definition of
"working".

### Backup

```
bash ai-memory-uninstall.sh --backup
```

Produces a timestamped, secret-free archive in `~/Downloads`. That archive plus
a fresh `setup --restore` on any machine *is* the disaster-recovery story — the
vault is the only thing that cannot be re-derived.

### Uninstalling

The uninstaller is built so the dangerous thing is hard and the safe thing is
easy:

- **Dry-run by default** — a plain run only prints the plan.
- **Export-first, enforced in code** — removal cannot proceed unless the export
  succeeded and was verified. The agent's own memory database (`state.db`)
  is included in the archive.
- Skipping the export requires typing the word `DELETE` — `--yes` alone is
  never enough.

## 8 · The optional layer

### sync — several machines, one memory

`ai-memory-sync.sh` pushes this machine's imported history to a central vault
over SSH, add-only (it never deletes or overwrites on the central), with a
secret-scan gate on outgoing files. An alternative that also just works: put
the vault under git or Syncthing.

### Remote access — deliberately not in this repo

For reaching a memory machine from elsewhere, the low-risk path is
**Tailscale plus your OS's built-in Remote Login (SSH)** — near-zero lockout
surface. The heavier tooling (sshd hardening, WireGuard hub, netboot
provisioning) lives in the companion repo **local-ai-memory-fleet**, was split
out on purpose so that *nothing in this repo can lock you out of a machine*,
and has never run on real hardware — read its README's warnings before
touching it.

## 9 · Keys and the safety model

### Where your API key lives (and who controls that)

Exactly **one** script writes keys: `configure`. The design in one breath:

- **The place is a project convention, not an OS decision:**
  `~/.hermes/.env` — one file, in your home directory, so the *path* is the
  same on Linux, macOS and WSL (`$HOME` differs; the location inside it never
  does).
- **The OS's only job is the lock on the door:** configure sets the file to
  mode `600` (readable and writable by your user account only) and replaces it
  atomically, so a crash can never leave a half-written key file. It edits only
  its own entries and preserves anything else you put there.
- **The agent reads it at startup:** Hermes loads `.env` when a session starts;
  nothing else needs the key, so nothing else stores it.
- **Everything else is built to keep keys OUT:** ingest scrubs key-shaped
  strings from imported conversations (bodies, titles, filenames); sync scans
  outgoing files and refuses to push anything key-shaped; uninstall's export
  archive excludes `.env` by construction. Losing the archive can never mean
  losing a secret.

(SSH keys are a different animal and belong to the fleet repo — in this repo,
no script creates or moves SSH keys.)

### The guarantees in one place

| Guarantee | Mechanism |
|---|---|
| Your edits survive | ingest hash-checks every existing file; edited files are warned about and skipped, never overwritten. |
| No half-written memory | Atomic writes (temp file + rename) for conversations, the index, reports — and the key file. |
| No secrets in vault or exports | Scrub on import; keys live only in `~/.hermes/.env` (mode 600); exports exclude them by construction. |
| Nothing destructive by accident | Uninstall dry-runs by default; export verified before removal; `DELETE` must be typed to skip it. |
| Re-running is always safe | Every script is idempotent; interrupted runs resume where they stopped. |
| Honest failure | Scripts exit non-zero when something failed and say what. "A green log that did nothing is a bug" is a project rule. |
| You can always leave | Plain markdown plus a secret-free archive; no lock-in anywhere. |

## 10 · Reference

### Flags shared by the whole family

`--help` · `--version` · `--yes` (accept safe defaults; never enough for
destructive steps)

### Per-script flags worth knowing

| Script | Flags |
|---|---|
| setup | `--restore` · `--no-hermes` · `--no-autostart` · `--yes` |
| configure | `--yes` |
| ingest | `--list-sources` · `--source NAME` · `--scan DIR` · `--deep-scan` · `--scan-report` · `--local` · `--yes` |
| uninstall | `--backup` / `--export-only` · `--no-export` (asks for typed DELETE) · `--remove-ollama` · `--yes` |
| doctor | `--live` |

### Troubleshooting

| Symptom | Meaning / fix |
|---|---|
| `git`/`curl: command not found`; apt: "can't be done securely" | You are on a cloner or minimal image, not a real OS. GET-STARTED Part 0: install Ubuntu Desktop first. |
| Password prompt shows nothing while typing | Normal. Type it, press Enter. |
| A question you don't understand | Press Enter — every default is the safe one. You can re-run later. |
| Agent says it found nothing, but the files exist | You are probably running hermes outside the launcher. Run `doctor`; check the hook and launcher lines. |
| Import says "failed" for one source | The other sources still imported. Re-run with `--source NAME` and read its error; exports from newer app versions may need the `--scan-report` bridge. |
| "edited — skipped" warnings during ingest | Working as intended: you changed those files by hand, and ingest refuses to overwrite them. |
| Something looks stuck during setup | Read the log path printed at the start (`tail -f` works for the whole run). Ctrl-C and re-run is always safe. |

### Where things live

| Path | What |
|---|---|
| `~/Documents/ai-memory/` | the vault — your memory (back this up) |
| `~/Documents/ai-memory/.tools/` | the scripts' installed home |
| `~/Documents/ai-memory/05-AI-Sessions/` | imported conversations, one file each |
| `~/.hermes/config.yaml` + `.env` | per-machine agent config and keys — never synced, never exported |
| `~/Downloads/ai-memory-export-*.tar.gz` | your backups |

---

**Provenance** — "proven" in this manual means a live run on real hardware,
recorded in [TESTING.md](../TESTING.md). The core chain (setup, configure,
ingest, doctor, uninstall's export path) is proven on Linux, WSL2 and Apple
Silicon; some rarely-used import parsers are not, and everything in the fleet
companion repo is not. The [README](../README.md) keeps the current list.

*local-ai-memory · MIT · published unsupported*
