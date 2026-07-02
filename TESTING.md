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

### `tests/run.sh` — test harness (new, 2026-07-02)

| Check | Level | Evidence |
|---|---|---|
| full harness green in WSL2 | ✅ proven | **33 passed / 0 failed / 1 skipped** (only shellcheck skipped — see below) |
| uninstall gate tested with NO controlling tty | ✅ proven | uses `setsid` + `timeout` so the gate must *refuse*, not prompt/hang |
| `bash -n` on all 8 scripts (LF content) | ✅ proven | WSL: all 8 pass when LF-normalized |
| uninstall `--no-export --yes` safety gate | ✅ proven | WSL: vault survived, exit≠0 — regression locked in |
| mux 2-pane + mouse assertions | ✅ proven | WSL: both pass |
| ingest `--version`/`--help` | ✅ proven | WSL (real python3): pass. git-bash skips (Store-stub python) |
| shellcheck step | 🟡 static | proven clean on git-bash (0.11.0); WSL run skipped it (not installed there); CI installs it |
| CI on Linux **and macOS bash 3.2** | ✅ proven | run [28591657914](https://github.com/jordglob/local-ai-memory/actions/runs/28591657914) @ `1b509a2`: `test (ubuntu-latest)` ✅ + `test (macos-latest)` ✅ (macOS runner's `/bin/bash` is 3.2 — proves the whole family + harness parse & run there) |

### Line endings (CRLF → LF) — finding + fix

- **Finding (proven):** the six existing scripts are **CRLF in the Windows
  working tree** (via `core.autocrlf`) and **fail under Linux/WSL bash**
  (`syntax error near … $'in\r'`) when run from `/mnt/c`. The repo *blobs* are
  LF, so a Linux `git clone` is fine — but a Windows checkout run through WSL is
  not.
- **Fix (proven):** `.gitattributes` (`* text=auto eol=lf`, `*.sh eol=lf`)
  forces LF on every checkout regardless of `autocrlf`. After renormalizing, all
  8 scripts pass `bash -n` **and** the full harness in WSL from `/mnt/c`.

### Hygiene / config files (new, 2026-07-02)

`.gitattributes`, `.shellcheckrc`, `.editorconfig`, `.github/workflows/ci.yml`,
`SECURITY.md`, `CONTRIBUTING.md` — static content; `.gitattributes` effect
proven above; CI workflow validated locally by running the same steps by hand.

### Behavior-neutral lint fixes (2026-07-02)

`configure` (drop dead `SOURCE`), `remote` (drop dead `blank`), `setup` (split
`local bak; bak=…` to unmask `date`'s return). ✅ proven: shellcheck `-S warning`
now clean on all three; `bash -n` OK; no behavior change (dead-var removal +
declare/assign split), so **intentionally left unversioned**.
