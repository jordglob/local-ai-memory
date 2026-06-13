# local-ai-memory

*The AI Memory Stack — your conversations, your disk, your agent.*

Consolidate your scattered AI conversations into one local vault you own —
and run a persistent local agent on top of it. No cloud accounts. No lock-in.
Plain markdown on your own disk.

```
bash ai-memory-setup.sh        # installs everything on a blank machine
bash ai-memory-configure.sh    # picks the best model for YOUR hardware
bash ai-memory-ingest.sh       # imports your history from 10 sources
bash ai-memory-remote.sh       # optional: SSH/Tailscale/RustDesk node setup
hermes chat                    # talk to an agent that knows your past
```

The scripts are a family: same flags everywhere (`--help` `--version` `--yes`),
idempotent re-runs, and on first run they install themselves to
`~/Documents/ai-memory/.tools/` — delete the downloads afterwards.

```
git clone https://github.com/jordglob/local-ai-memory
```

## What it does

- **Vault** — an Obsidian-compatible folder of plain markdown: your imported
  history, distilled entity files, and an inbox the agent reads at startup.
- **Local model** — [Ollama](https://ollama.com) with a model matched to your
  RAM/GPU (3B on 8 GB up to 35B on 48 GB).
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
