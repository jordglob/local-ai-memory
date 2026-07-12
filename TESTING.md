# Testing & provenance

Honest record of **what has been tested, in which environment, and by whom** —
so a green checkmark never has to be taken on faith. This complements the
project's rule that a path you cannot live-test is *written-but-unproven*, never
"done".

Entries are dated and kept verbatim, so script *counts* in older entries
reflect the family's size on that date (the family has grown to nine scripts —
`tests/run.sh`'s `FAMILY` list is authoritative).

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

### First real-Mac live run (2026-07-03) — macOS path upgraded to PROVEN

The full chain ran end-to-end on a physical Apple Silicon Mac mini (macOS 26.4.1)
as the hub of a hub-and-spoke setup (central vault, satellite pushes via sync):

| Path | Level | Evidence |
|---|---|---|
| `setup` v8.16 on real macOS | ✅ proven | fresh run over ssh: Homebrew sudo prompt, npm-prefix install (no sudo), `~/.hermes` created — 0 errors |
| `configure` on real macOS | ✅ proven | detected 48GB + 16 Ollama models, suggested `qwen3.6:35b`, wrote config + vault launcher |
| `doctor` on real macOS | ✅ proven | **7 passed / 0 warnings / 0 failed** — searchability verified from a foreign cwd |
| `sync` v1.0 push (WSL satellite → Mac central) | ✅ proven | scrape → clean secret-scan → add-only → remote reindex → 844=844 verified |
| cross-machine recall | ✅ proven | the Mac's Hermes answered a memory question by reading a session archived on the WSL machine the day before (ingest `hermes` source → sync → central recall) |

(The earlier "bash 3.2 / macOS unproven" rows above describe the state at
2026-07-02 and are kept as history; CI had proven parse/run on the macOS runner,
this run proves real-hardware behavior.)

### Harness self-lint + false-red fixes (2026-07-04) — findings + fix

Two real bugs found *in the harness itself*, both rooted in the same blind
spot: `tests/run.sh` linted every script except itself.

- **Finding 1 (proven):** the comment `# shellcheck: find it on PATH…` is
  parsed by shellcheck as a *directive*, fails with SC1073/SC1072, and makes
  shellcheck bail on the whole file — so `run.sh` was never actually
  lint-checkable. Never caught, because the harness didn't lint itself.
- **Finding 2 (proven):** the secret-scrub regression (§6) lacked the `PY_OK`
  guard the other ingest checks have. On a box without real python3
  (git-bash / Store-stub python) the import can't run, no file is written, and
  the harness reports a **false red** `secret survived into vault` — a spurious
  leak alarm in exactly the test whose job is trust.
- **Fix (proven):** new `LINT_ONLY="bootstrap.sh tests/run.sh"` set — parse- and
  lint-checked like `$SCRIPTS` but exempt from the `--version`/`--help`
  contract; the pseudo-directive comment reworded; the scrub test now skips
  without real python3 (CI's ubuntu leg still runs it for real). Evidence:
  git-bash 5.2.37 + shellcheck 0.11.0 — **45 passed / 0 failed / 4 skipped**
  (was 44/2/3). Meta-proof the gap is closed: the self-lint immediately caught a
  *new* accidental pseudo-directive in the first draft of its own comment.

| Check | Level | Evidence |
|---|---|---|
| harness + bootstrap self-lint (`bash -n` + shellcheck) | ✅ proven | git-bash: both green at `-S warning` after fix |
| scrub false-red eliminated | ✅ proven | git-bash: `skip … (no real python3 here)` instead of FAIL |
| scrub still runs where python3 is real | ✅ proven | run [28697698407](https://github.com/jordglob/local-ai-memory/actions/runs/28697698407) @ `148cc7a`: ubuntu `pasted api key redacted on import` ok — **51 passed / 0 failed / 0 skipped** |
| bash-3.2 safety of the changes | ✅ proven | same run, macOS leg (`/bin/bash` 3.2): self-lint + scrub all ok — **50 passed / 0 failed / 1 skipped** |

### Line endings (CRLF → LF) — finding + fix

- **Finding (proven):** the six existing scripts are **CRLF in the Windows
  working tree** (via `core.autocrlf`) and **fail under Linux/WSL bash**
  (`syntax error near … $'in\r'`) when run from `/mnt/c`. The repo *blobs* are
  LF, so a Linux `git clone` is fine — but a Windows checkout run through WSL is
  not.
- **Fix (proven):** `.gitattributes` (`* text=auto eol=lf`, `*.sh eol=lf`)
  forces LF on every checkout regardless of `autocrlf`. After renormalizing, all
  8 scripts pass `bash -n` **and** the full harness in WSL from `/mnt/c`.

### ingest v2.17 — CRLF inside transcripts (2026-07-06) — finding + fix

- **Finding (proven, cc-session-sync live round):** Claude Code `.jsonl`
  transcripts written on **Windows** carry literal `\r\n` inside message text.
  `clean_text`'s line-anchored regexes (`(?m)^…$`, `\n{3,}`) silently miss CRLF
  text — noise placeholders survived — and raw `\r` landed in the vault's
  markdown. On the macOS central this also made a naive read-back comparison
  see the same conversation as "changed" forever (universal-newline
  translation on read).
- **Fix (proven):** `clean_text` folds `CRLF`/`CR` → `LF` before any cleaning,
  for **every** source (pattern-hunt class fix). New harness section **6d**
  locks it in: no raw `\r` in the vault file, noise stripped despite CRLF,
  text intact.
- **Evidence:** WSL harness run 2026-07-06 → **52 passed, 0 failed, 1
  skipped**; red-check proven — the same fixture against HEAD@v2.16 leaks both
  raw `\r` and the noise placeholder.

### Hygiene / config files (new, 2026-07-02)

`.gitattributes`, `.shellcheckrc`, `.editorconfig`, `.github/workflows/ci.yml`,
`SECURITY.md`, `CONTRIBUTING.md` — static content; `.gitattributes` effect
proven above; CI workflow validated locally by running the same steps by hand.

### Behavior-neutral lint fixes (2026-07-02)

`configure` (drop dead `SOURCE`), `remote` (drop dead `blank`), `setup` (split
`local bak; bak=…` to unmask `date`'s return). ✅ proven: shellcheck `-S warning`
now clean on all three; `bash -n` OK; no behavior change (dead-var removal +
declare/assign split), so **intentionally left unversioned**.
