# local-ai-memory

*The AI Memory Stack — your conversations, your disk, your agent.*

Consolidate your scattered AI conversations into one local vault you own —
and run a persistent local agent on top of it. No cloud accounts. No lock-in.
Plain markdown on your own disk.

## Get the scripts (no `unzip` required)

**Recommended — `git clone`.** git checks the files out already unpacked, so
there is no extract step at all:

```
git clone https://github.com/YOUR-USERNAME/local-ai-memory
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
bash ai-memory-setup.sh        # installs everything on a blank machine
bash ai-memory-configure.sh    # picks the best model for YOUR hardware
bash ai-memory-ingest.sh       # imports your history from 11 sources
bash ai-memory-remote.sh       # optional: SSH/Tailscale/RustDesk node setup
hermes chat                    # talk to an agent that knows your past
```

The scripts are a family: same flags everywhere (`--help` `--version` `--yes`),
idempotent re-runs, and on first run they install themselves to
`~/Documents/ai-memory/.tools/` — delete the downloads afterwards.

## Who it's for

Anyone who wants to put **old or new hardware to work** — give a 15-year-old
laptop a second life, or run a serious local stack on a capable machine. The
tool adapts to what you have:

- **Weak/old machine?** It detects low memory and sets up **cloud-only** mode —
  an old laptop talks to a cloud model and works fine, nothing heavy runs
  locally.
- **Capable machine?** It runs a real local model — your conversations and your
  agent stay entirely on your own disk, no cloud, no accounts.

Same tool, same vault format, both ends of the hardware spectrum. It is generic
and machine-agnostic by design — it adapts to the box it finds itself on.

## Design philosophy

- **Local-first.** Your data lives on your disk as plain markdown. Cloud is
  optional spillover, never the source of truth.
- **Deterministic work is a script; messy reality is an agent.** Install,
  configure, back up — predictable, so they're plain bash you can read and
  trust. Interpreting the messy zoo of AI export formats is better suited to an
  agent. The dividing line keeps each part honest. (See docs/REQUIREMENTS.md §4.5.)
- **No lock-in, no BigTech assumptions.** No required cloud accounts; GitHub,
  OpenRouter, etc. are opt-in, never assumed.

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
  printed identity block for the checklist.
- **Ingest** — importers for **10 sources**: Claude.ai, ChatGPT, Claude Code,
  Codex CLI, Gemini CLI, OpenClaw, Cursor, Aider, LM Studio, Open WebUI,
  and Google Takeout (Gemini). Idempotent — re-run any time.

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

## Installing on a brand-new machine

Print **installation-checklist.pdf** (7 pages) — a tick-box walkthrough from
blank hardware (clean macOS reinstall or Linux Mint USB, no cloud accounts)
to a running agent: every security popup the scripts trigger, power settings
that would otherwise kill downloads, a headless-node page with a mandatory
pull-the-plug test, and an identity box per machine.

## Flags worth knowing

```
setup:   --no-hermes  --no-autostart  --yes
ingest:  --list-sources  --source NAME --path FILE  --scan DIR  --deep-scan  --yes
remote:  --yes
all:     --help  --version
```

## Privacy posture

- Default discovery only looks in known per-tool locations plus a targeted
  scan of `~/Downloads` for export ZIPs (it asks before importing anything).
- `--deep-scan` is opt-in, limited to your home directory, and warns first.
- API keys (optional, for cloud fallback) live in `~/.hermes/.env`
  (chmod 600) — never in the vault.
- The vault is yours: plain `.md` files readable by any tool, forever.

## Status & honesty notes

Tested end-to-end with synthetic fixtures for all ten sources and on
Linux + (mocked) macOS paths. `ai-memory-remote.sh` is the least-tested
artifact (it is interactive and touches system services by nature) — run it
while you still have a screen attached the first time. The parsers for Cursor, LM Studio, Open WebUI,
Codex CLI, Gemini CLI and Takeout are written defensively against multiple
known on-disk layouts but have not yet been verified against every current
app version — issues and PRs with real-world samples are very welcome.

## License

MIT — see [LICENSE](LICENSE).
