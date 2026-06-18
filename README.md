# local-ai-memory

*The AI Memory Stack — your conversations, your disk, your agent.*

Consolidate your scattered AI conversations into one local vault you own —
and run a persistent local agent on top of it. No cloud accounts. No lock-in.
Plain markdown on your own disk.

> ## Status — read this first
>
> Source-available, **works-for-me**, *not* a polished consumer product. Built for
> people who are comfortable **reading bash and fixing their own machine**.
>
> - **Unsupported — GitHub issues are off** (on purpose). It's MIT: fork it, adapt
>   it, no expectations either way.
> - **Some paths have run on real hardware** (Linux + WSL2). **Others have not** —
>   in particular **macOS has never run on a real Mac**, and **`ai-memory-remote.sh`
>   has only run in a VM and can silently lock you out of a headless box.**
> - **Read the code before you run it**, especially anything touching SSH, keys, or
>   power settings. See *What's proven vs. unproven* below — it's specific and honest.

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
bash ai-memory-remote.sh       # optional: SSH/WireGuard/Tailscale node setup
bash ai-memory-uninstall.sh    # export-first reversal (dry-run by default)
hermes chat                    # talk to an agent that knows your past
```

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
  agent. The dividing line keeps each part honest. (See `docs/REQUIREMENTS.md` §4.5.)
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
- **Remote/node setup** — `ai-memory-remote.sh` is role-aware (MAIN / NODE /
  SOLO). It sets up SSH + your public key (password login disabled only after
  a verified key login), then analyzes your connection and recommends a
  remote-access path — **WireGuard (fully local) first**, with Tailscale
  offered for convenience or behind CGNAT, and an optional Cloudflare DNS
  updater for dynamic IPs. Plus no-sleep + auto-restart power profile and a
  printed identity block. *(See the maturity note — this script is the least
  proven and the most dangerous to get wrong.)*
- **Ingest** — importers for Claude.ai, ChatGPT, Claude Code, Codex CLI,
  Gemini CLI, OpenClaw, Cursor, Aider, LM Studio, Open WebUI, and Google
  Takeout (Gemini). Idempotent — re-run any time. A `--scan-report` mode maps
  unknown/messy exports to a bridge file your agent can act on.
- **Uninstall / backup** — `ai-memory-uninstall.sh` is **export-first** (it
  archives your vault, with a migration manifest, *before* removing anything)
  and **dry-run by default**. Also the clean way to reset between trial runs.

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

**Run and verified on real hardware:** `setup`; `configure` (cloud-only path);
`ingest` (including real WSL2 importing a real Claude.ai export, idempotently);
and `uninstall`'s **export/backup** path.

**Not yet run on real hardware — treat as unproven:**

- **macOS, all of it.** The code is cross-platform but the macOS branches have
  never executed on a real Mac.
- **`ai-memory-remote.sh`.** Validated only in a local VM. It edits `sshd`, can
  disable password login, and brings up a WireGuard hub — a mistake here is a
  *silent lockout of a possibly-headless box*, not a red error. First-run it with
  a screen/console attached and keep a second way in.
- **`configure`'s local-model selection** on capable hardware, and **`uninstall`'s
  actual removal** (its export path is tested; the teardown is not).
- Several `ingest` parsers (Cursor, LM Studio, Open WebUI, Codex CLI, Gemini CLI,
  Takeout) are written defensively against known on-disk layouts but are unverified
  against current app versions.

Because of the above this is published **as-is, unsupported, issues off**. If you
fork it and prove out the macOS / remote paths, all the better — but nothing here
expects you to, and nothing expects me to answer for it.

`docs/installation-checklist.pdf` is a tick-box walkthrough from blank hardware to
a running agent. It targets non-experts, but its macOS track shares the
unproven-on-real-Mac caveat above — read it as a draft for a technical reader.

## Flags worth knowing

```
setup:      --no-hermes  --no-autostart  --yes
configure:  --yes
ingest:     --list-sources  --source NAME  --scan DIR  --deep-scan  --scan-report  --yes
remote:     --yes
uninstall:  --export-only  --no-export  --remove-ollama  --yes   (dry-run unless --yes)
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
