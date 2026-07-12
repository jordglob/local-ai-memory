# local-ai-memory

*The AI Memory Stack — your conversations, your disk, your agent.*

Consolidate your scattered AI conversations into one local vault you own —
and run a persistent local agent on top of it. No cloud accounts. No lock-in.
Plain markdown on your own disk.

> 🌱 **New to the terminal?** Start with **[GET-STARTED.md](GET-STARTED.md)** — a
> beginner walkthrough, one copy-paste block at a time (it handles the classic
> *"git: command not found"* wall that trips people on a fresh machine).
> Want the whole picture in one document? **[docs/MANUAL.md](docs/MANUAL.md)** is
> the user manual — what you do, what happens, what is guaranteed.

> ## Status — read this first
>
> Source-available, **works-for-me**, *not* a polished consumer product. Built for
> people who are comfortable **reading bash and fixing their own machine**.
>
> - **Unsupported — GitHub issues are off** (on purpose). It's MIT: fork it, adapt
>   it, no expectations either way.
> - **Most of the chain has now run on real hardware** (Linux, WSL2, and — since
>   2026-07-03 — a physical Apple Silicon Mac). **Some paths still have not** —
>   see *What's proven vs. unproven* below, it's specific and honest.
> - **Read the code before you run it**, especially anything touching keys or
>   your vault. Nothing in this repo touches SSH or can lock you out of a
>   machine — that layer lives in the companion repo (see *Remote access* below).

## Get the scripts (no `unzip` required)

**Recommended — `git clone`.** git checks the files out already unpacked, so
there is no extract step at all:

```
git clone https://github.com/jordglob/local-ai-memory
cd local-ai-memory
```

**Or download the ZIP** ("Code → Download ZIP" on GitHub). A clean machine may
not have `unzip` yet — so unpack with Python, which ships on virtually every
Linux / WSL / macOS, no extra tools needed:

```
python3 -c "import zipfile; zipfile.ZipFile('local-ai-memory-main.zip').extractall()"
cd local-ai-memory-main
```

**On Windows? Run it in WSL** (Windows Subsystem for Linux): `wsl --install`
once, open Ubuntu, then follow the Linux steps below. `setup` installs the few
base tools a fresh WSL lacks (`unzip`, `zstd`), and `ingest` detects WSL and
offers to also scan your **Windows** Downloads (`/mnt/c/Users/<you>/Downloads`),
where your AI exports usually live.

## Quick start

```
bash ai-memory-setup.sh        # installs the stack (Node, Ollama, Hermes, vault)
bash ai-memory-configure.sh    # picks a model for YOUR hardware, writes Hermes config
bash ai-memory-ingest.sh       # imports your AI history from local exports
bash ai-memory-doctor.sh       # verify memory is reachable from every door (read-only)
bash ai-memory-search.sh "topic"   # deterministic vault search — also the recall hook
bash ai-memory-mux.sh          # talk to an agent that knows your past (the standard
                               # mouse-friendly two-pane tmux cockpit; plain
                               # `hermes chat` works too, no tmux needed)
bash ai-memory-uninstall.sh    # export-first reversal (dry-run by default)
bash ai-memory-sync.sh         # optional: push this machine's history to a central vault
```

`search` is more than a CLI: `configure` wires it into Hermes as a
`pre_llm_call` hook, so matching vault excerpts are injected into every
question you ask the agent — recall never depends on the model *deciding* to
search (small local models reliably don't). `doctor` then proves the whole
wiring per entry point, instead of asking you to take a green log on faith.

The scripts are a family: same flags everywhere (`--help` `--version` `--yes`),
idempotent re-runs, and on first run they install themselves to
`~/Documents/ai-memory/.tools/` — delete the downloads afterwards. Each script
ends by pointing at the next one, so you're never left guessing what to type.

## Moving to a new machine (or backing up)

Your memory is **plain markdown in the vault** — that's the only thing that needs
to move. Everything else (which model, API keys) is re-derived for the new machine
on purpose: hardware differs, and **secrets never travel in an export**.

**One-time move (old machine → new machine):**

```
# on the OLD machine — back up the vault to a timestamped archive in ~/Downloads
bash ai-memory-uninstall.sh --backup

# copy that ai-memory-export-*.tar.gz to the NEW machine (USB, scp, cloud — it
# has no secrets), then on the NEW machine:
bash ai-memory-setup.sh --restore     # finds the archive in ~/Downloads and restores it
bash ai-memory-configure.sh           # picks a model for the NEW hardware, re-enter keys
bash ai-memory-doctor.sh              # verify recall works from every door
```

`setup` also **auto-detects** an export sitting in `~/Downloads` and offers to restore
it, so a plain `bash ai-memory-setup.sh` on a fresh box will ask. `--backup` is just a
friendly alias for `ai-memory-uninstall.sh --export-only` (it exports and stops —
removes nothing).

**Two machines at once (a shared, evolving vault):** because the vault is plain
files, put `~/Documents/ai-memory` under **git** (or Syncthing/Dropbox/iCloud) and run
`configure` on each machine pointed at the synced vault. Keep `~/.hermes/config.yaml`
and `~/.hermes/.env` **out** of the sync (per-machine + secrets). Markdown diffs and
merges cleanly; `05-AI-Sessions/` is append-only, so conflicts are rare.

**What moves vs. what you redo:** the vault (all your imported history, notes, and
profile) moves; `config.yaml`, API keys, and Hermes' internal state are re-created on
the new machine by `configure`.

## Who it's for

People who want to **own their AI memory** and are happy to read and adapt bash to
do it. This is not a click-to-install consumer app: there is no support line, and
you are expected to understand what each script does before running it.

The engine adapts to the hardware it finds itself on:

- **Weak/old machine** → it detects low memory and sets up **cloud-only** mode (an
  old laptop talks to a cloud model; nothing heavy runs locally).
- **Capable machine** → it runs a real local model; your conversations and your
  agent stay entirely on your own disk, no cloud, no accounts.

Same tool, same vault format, both ends of the hardware spectrum.

## Design philosophy

- **Local-first.** Your data lives on your disk as plain markdown. Cloud is
  optional spillover, never the source of truth.
- **Deterministic work is a script; messy reality is an agent.** Install,
  configure, back up — predictable, so they're plain bash you can read and
  trust. Interpreting the messy zoo of AI export formats is better suited to an
  agent. The dividing line keeps each part honest. (See `docs/SPEC.md` §4.)
- **No lock-in, no BigTech assumptions.** No required cloud accounts; GitHub,
  OpenRouter, etc. are opt-in, never assumed.
- **Verify against the source; the sandbox lies.** Real behaviour on real hardware
  is the bar — and where that bar hasn't been cleared, it's said plainly (below).

## What it does

- **Vault** — an Obsidian-compatible folder of plain markdown: your imported
  history, distilled entity files, and an inbox the agent reads at startup.
- **Local model** — [Ollama](https://ollama.com) with a model matched to your
  RAM/GPU — roughly a 3B model at 8 GB up to a 35B model at 48 GB. Below
  ~6 GB RAM, configure automatically switches to **cloud-only** mode (Hermes
  via OpenRouter) instead of a local model, so an old or low-memory machine
  still works — nothing heavy runs locally.
- **Agent** — [Hermes Agent](https://github.com/NousResearch/hermes-agent)
  (optional), auto-configured for your local Ollama, with workspace
  instructions that make it actively maintain the vault — including a
  read-only Update Advisor that reports available upgrades but never
  installs them itself.
- **Recall** — `ai-memory-search.sh` scores every imported session against
  your question and quotes the best-matching lines; wired in as a Hermes
  `pre_llm_call` hook so even a small local model answers from your real
  history in one step. `ai-memory-doctor.sh` verifies the whole chain,
  read-only.
- **Ingest** — importers for Claude.ai, ChatGPT, Claude Code, Codex CLI,
  Gemini CLI, OpenClaw, Cursor, Aider, LM Studio, Open WebUI, and Google
  Takeout (Gemini). Idempotent — re-run any time. A `--scan-report` mode maps
  unknown/messy exports to a bridge file your agent can act on.
- **Cockpit** — `ai-memory-mux.sh` is the default way to talk to your agent:
  a mouse-friendly two-pane tmux cockpit (agent chat and a working terminal
  side by side; click, scroll, drag borders, detach and re-attach). Plain
  `hermes chat` works too if you'd rather skip tmux.
- **Uninstall / backup** — `ai-memory-uninstall.sh` is **export-first** (it
  archives your vault, with a migration manifest, *before* removing anything)
  and **dry-run by default**. Also the clean way to reset between trial runs.

## Remote access

Want to reach a memory machine from elsewhere? Use **Tailscale** plus your
OS's **built-in Remote Login (SSH)** — both are mature, well-documented, and
have near-zero lockout surface. The heavier fleet tooling (WireGuard hub,
sshd hardening, netboot provisioning) was split out of this
repo in July 2026 into the companion repo **`local-ai-memory-fleet`**
(a sibling folder/repo, same MIT-unsupported posture), so nothing in *this*
repo can lock you out of a machine.

## Requirements

| | Minimum | Recommended |
|---|---|---|
| RAM | 8 GB (3B models, limited) | 32–48 GB (32–35B models) |
| Disk free | 20 GB | 60+ GB |
| OS | macOS 12.4+ · Linux (apt/dnf/pacman) · Windows via WSL2 | Apple Silicon or NVIDIA GPU |

Nothing else. The installer bootstraps Homebrew/system packages, Node 22,
python3, git and Ollama itself, asks before anything opinionated
(Hermes install, login autostart), and is safe to re-run — completed steps
are skipped, interrupted ones resume.

## What's proven vs. unproven (honest)

[TESTING.md](TESTING.md) is the provenance ledger — what actually ran, where,
with the evidence. The short version:

**Run and verified on real hardware:**

- **Linux / WSL2:** `setup`; `configure` (cloud-only and local paths, including
  the dual-context fix a capable local model needs); `ingest` importing a real
  Claude.ai export idempotently (the Claude Code, Hermes, OpenClaw and
  LM Studio sources have also run in live use); `uninstall`'s
  **export/backup** path; and the full test harness.
- **macOS — proven on a physical Apple Silicon Mac since 2026-07-03:** the
  chain ran end-to-end as the hub of a hub-and-spoke setup — `setup`,
  `configure` **including local-model selection on capable hardware**,
  `doctor` (all checks green, searchability verified from a foreign cwd),
  `sync` pushing a satellite's history to the Mac's central vault, and
  cross-machine recall (the Mac's agent answered from a session archived on
  the WSL machine the day before).
- CI runs the harness on Linux **and** macOS (whose `/bin/bash` is 3.2) for
  every push.

**Not yet run on real hardware — treat as unproven:**

- **`uninstall`'s actual removal** (its export path is tested; the teardown is
  not).
- Several `ingest` parsers (ChatGPT, Cursor, Codex CLI, Gemini CLI, Aider,
  Open WebUI, Takeout) are written defensively against known on-disk layouts
  but are unverified against real, current exports.

*(The most dangerous unproven surface used to live here too: the `remote`
node-setup script — VM-validated only, able to lock you out of a headless
box. In July 2026 it moved — with the netboot sketch — to the companion repo
`local-ai-memory-fleet`, precisely so this repo carries no lockout risk;
`mux` made the trip too but came straight back as the standard interface —
it can't lock you out of anything. The ledger entries stay in
[TESTING.md](TESTING.md).)*

Because of the above this is published **as-is, unsupported, issues off**. If you
fork it and prove out the unproven paths, all the better — but nothing here
expects you to, and nothing expects me to answer for it.

**[GET-STARTED.md](GET-STARTED.md) is the single beginner path** — from a blank
machine to a running agent, one copy-paste block at a time. (An older tick-box
PDF now lives in `docs/history/`; it predates the real-hardware runs and the
current script family — don't follow it.)

## Flags worth knowing

```
setup:      --no-hermes  --no-autostart  --yes
configure:  --yes
ingest:     --list-sources  --source NAME  --scan DIR  --deep-scan  --scan-report  --yes
uninstall:  --export-only  --no-export  --remove-ollama  --yes   (dry-run unless --yes)
mux:        start | attach | menu | ls | kill | tips  --no-attach  --yes
all:        --help  --version
```

## Privacy posture

- Default discovery only looks in known per-tool locations plus a targeted
  scan of `~/Downloads` for export ZIPs (it asks before importing anything).
- `--deep-scan` is opt-in, limited to your home directory, and warns first.
- API keys (optional, for cloud fallback) live in `~/.hermes/.env`
  (chmod 600) — never in the vault, never in an export.
- The vault is yours: plain `.md` files readable by any tool, forever.

## License

MIT — see [LICENSE](LICENSE). Published unsupported; fork freely.
