# Testing & provenance

Honest record of **what has been tested, in which environment, and by whom** —
so a green checkmark never has to be taken on faith. This complements the
project's rule that a path you cannot live-test is *written-but-unproven*, never
"done".

## Legend

| Level | Meaning |
|---|---|
| ✅ **proven** | Actually run and its effect observed in the listed environment. |
| 🟡 **static** | `bash -n` parse + `shellcheck` clean, but the runtime path was **not** executed here. |
| ⚪ **unproven** | Written carefully but never run on the required environment (e.g. real Linux node, macOS, bash 3.2). Needs a live round. |

## Environments used

| Env | Details |
|---|---|
| WSL2 Ubuntu | `bash 5.2.21`, `tmux 3.4` — used for live runtime tests |
| Windows git-bash | `bash 5.2.37 (msys)` — used for `bash -n` + running the harness |
| shellcheck | `0.11.0` (run on LF-normalized copies; the working tree is CRLF via `core.autocrlf`) |

> **Tester:** Claude Code — model **Opus 4.8 (1M)** — driven by the maintainer, on the maintainer's machine.
> Dates are UTC-ish local (`Europe/Stockholm`).

## Status by artifact

### `ai-memory-mux.sh` v1.0  (new, 2026-07-02)

| Path | Level | Evidence |
|---|---|---|
| `--version`, `--help`, arg parsing | ✅ proven | run on git-bash + WSL |
| `start --no-attach` creates a 2-pane split (agent + terminal) | ✅ proven | WSL: `tmux list-panes` → 2 panes |
| session-scoped `mouse on` + history + pane titles | ✅ proven | WSL: `tmux show-options mouse` → `mouse on`; titles `agent`/`terminal` |
| `AI_MEMORY_MUX=1` exported into the session env | ✅ proven | WSL: `tmux show-environment` |
| `install-tmux-conf` (backup + idempotent, marker-blocked) | ✅ proven | WSL: 2nd run is a no-op; one `mouse on` line; backup written |
| shellcheck clean | ✅ proven | `shellcheck 0.11.0 -S style` → 0 findings |
| `bash -n` syntax | ✅ proven | git-bash 5.2 + WSL 5.2 |
| interactive `menu` loop, `attach`, `kill` confirm | 🟡 static | reads `/dev/tty`, not pipe-drivable; parse-clean, mechanics shared with proven paths |
| model-mode switches (`hermes config set …`) | ⚪ unproven | needs a configured local/cloud endpoint; gated behind opt-in config |
| bash 3.2 / macOS | ⚪ unproven | no bash-3.2 interpreter available here |

<!-- New artifacts (tests harness, CI, hygiene files) are appended here as they land. -->
