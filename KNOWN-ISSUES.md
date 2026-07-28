# KNOWN-ISSUES.md

Findings from a real fresh-install test run (Ubuntu Desktop, physical hardware,
no prior state) on 2026-07-28. Each entry is written so an AI coding agent can
locate the exact line, understand the failure, and apply the fix without
needing the original test session's context. Confirmed items were reproduced
and root-caused against the actual source in this repo; unconfirmed items are
flagged as such — verify before fixing blind.

---

## ISSUE-1 — CRITICAL — `find_export_archive()` crashes every fresh install (Step 1/7)

**Status:** Confirmed, reproduced twice on real hardware, root-caused by
isolating the function in a standalone harness under `set -euo pipefail`.

**File:** `ai-memory-setup.sh`
**Function:** `find_export_archive()`
**Line (as of this test):** 1140

**Current code:**
```bash
find_export_archive() {
  ls -1t "$HOME"/Downloads/ai-memory-export-*.tar.gz "$HOME"/ai-memory-export-*.tar.gz 2>/dev/null | head -1
}
```

**Symptom:** Setup prints the "Step 1/7 Vault structure" header and then
silently dies with `Setup interrupted (exit 2)` — no error text, no
"X directories created" line, nothing. The vault directory (e.g.
`~/Documents/ai-memory`) never gets created.

**Root cause:** When no `ai-memory-export-*.tar.gz` file exists in
`~/Downloads` or `$HOME` (true for essentially every first-time user — this
is not an edge case, it's the default state), the glob patterns don't expand
(bash `nullglob` is off), so `ls` receives literal, non-existent filenames as
arguments. `ls` then exits with status 2 and prints an error to stderr —
which `2>/dev/null` hides, but the exit code survives. The script runs under
`set -euo pipefail`, and this `ls | head` call happens directly inside a
variable assignment: `archive="$(find_export_archive)"` in
`maybe_restore_vault()`. Command substitutions on the right-hand side of an
assignment are NOT exempt from `errexit` (unlike a leading command in a
`&&`/`||` chain), so the moment `find_export_archive` returns non-zero, the
entire script terminates immediately — before any of Step 1's actual work
(directory creation, `write_once` calls) has run.

Even partially matching (e.g. one glob resolves, the other doesn't) still
fails: `ls` reports the whole pipeline as failed under `pipefail` if *any*
of its file arguments doesn't exist, regardless of whether other arguments
matched successfully.

**Fix (minimal, one line):**
```diff
- ls -1t "$HOME"/Downloads/ai-memory-export-*.tar.gz "$HOME"/ai-memory-export-*.tar.gz 2>/dev/null | head -1
+ ls -1t "$HOME"/Downloads/ai-memory-export-*.tar.gz "$HOME"/ai-memory-export-*.tar.gz 2>/dev/null | head -1 || true
```

**Better fix (avoids the underlying glob footgun entirely, recommended):**
```bash
find_export_archive() {
  shopt -s nullglob
  local matches=("$HOME"/Downloads/ai-memory-export-*.tar.gz "$HOME"/ai-memory-export-*.tar.gz)
  shopt -u nullglob
  (( ${#matches[@]} )) || return 0
  printf '%s\n' "${matches[@]}" | xargs -I{} stat -c '%Y %n' {} 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
}
```
(The minimal fix is sufficient and lower-risk; the better fix additionally
avoids relying on `ls -t`'s output format, which is itself fragile.)

**Verification:**
1. Ensure `~/Downloads` and `$HOME` contain no `ai-memory-export-*.tar.gz` files (the default state).
2. Run `bash ai-memory-setup.sh <fresh-vault-path>` on a machine that has
   already passed Step 0 (or run the full install).
3. Confirm Step 1/7 completes and prints "N directories created", and that
   the vault directory now exists with the expected subdirectory structure.
4. Regression-test the restore path too: place a real
   `ai-memory-export-*.tar.gz` in `~/Downloads` and confirm
   `maybe_restore_vault` still finds and offers it correctly.

**Severity justification:** This affects **100% of fresh installs with no
prior export** — i.e., the default, documented, expected first-run path
described in GET-STARTED.md and the README Quick Start. It is not an edge
case.

---

## ISSUE-2 — HIGH — `ai-memory-configure.sh` suggests a non-existent Ollama tag (`qwen3:7b`)

**Status:** Confirmed on real hardware (15.5 GB RAM, no GPU, i7-8565U).
Exact line not located in this test session — needs grep.

**File:** `ai-memory-configure.sh` (model-size-selection logic; search for
`qwen3:7b` or the RAM-tier → model-tag mapping table)

**Symptom:**
```
Suggested model: qwen3:7b — Qwen3 7B — fast
Reason: best fit for 12GB usable
...
⚠  Model 'qwen3:7b' is not downloaded yet.
?  Download it now with 'ollama pull qwen3:7b'? (Y/n)
pulling manifest
Error: pull model manifest: file does not exist
⚠  Download failed — run later: ollama pull qwen3:7b
```

**Root cause:** The official Ollama `qwen3` library does not publish a `7b`
tag. Confirmed available tags (as of this test): `0.6b`, `1.7b`, `4b`, `8b`,
`14b`, `30b`, `32b`, `235b`. Qwen2.5 had a `7b` variant; Qwen3 does not — the
nearest tag is `8b` (5.2 GB). The configure script's RAM-tier → tag mapping
is almost certainly a stale carryover from Qwen2.5-era naming.

**Fix:**
1. `grep -n "qwen3:7b" ai-memory-configure.sh` (and any shared lib file
   under `lib/` that holds the model-tier table) to find every occurrence.
2. Replace every `qwen3:7b` with `qwen3:8b`.
3. Audit the same table for other Qwen3/Qwen3.5/Qwen3.6 tags that might have
   the same stale-name problem (e.g. confirm `qwen3:14b`, `qwen3:4b` etc.
   are all real published tags before trusting them) — cross-check against
   `https://ollama.com/library/qwen3/tags` (and the equivalent tags page for
   any other model family referenced in the same table) at fix time, since
   tag lists change.

**Verification:**
1. Run `ai-memory-configure.sh` on a machine with ~12–16 GB usable RAM and
   no GPU.
2. Confirm the suggested tag is `qwen3:8b`.
3. Accept the download prompt and confirm `ollama pull qwen3:8b` succeeds
   (should, since it's a real published tag: manifest exists).
4. Confirm `config.yaml`'s `default:` field is written as `qwen3:8b`, not
   `qwen3:7b`.

---

## ISSUE-3 — MEDIUM — GET-STARTED.md doesn't say the project folder location is arbitrary

**Status:** Confirmed doc gap, not a functional bug.

**File:** `GET-STARTED.md`, Part 1 ("Get the project")

**Symptom:** A beginner extracted the ZIP directly into `~/` (Home) instead
of leaving it in `~/Downloads`, then asked whether that was correct — the
doc gives no signal either way. Functionally it makes zero difference (the
scripts don't care where they're run from), but the ambiguity costs a
confused user real time and confidence.

**Fix:** Add one line after step 3 in Part 1:
```diff
  3. Open the **Files** app → **Downloads**, right-click the ZIP → **Extract Here**.

  You now have a folder called `local-ai-memory-main`.
+
+ > It doesn't matter where this folder ends up — Downloads is just where the
+ > browser puts the ZIP by default. Feel free to move `local-ai-memory-main`
+ > anywhere you like (Home, Desktop, wherever) before running the scripts.
```

**Verification:** Read-only doc change — no functional test needed, just
proofread for tone consistency with the rest of the file.

---

## ISSUE-4 — LOW — GET-STARTED.md doesn't mention mouse copy-paste for beginners

**Status:** Confirmed doc gap, not a functional bug.

**File:** `GET-STARTED.md`, Part 2 ("Run it") and/or the top-level "What
you'll need" section.

**Symptom:** A beginner unfamiliar with terminal conventions re-typed
commands by hand at least once instead of copy-pasting, and at another point
pasted a command but wasn't sure whether pressing Enter was still required
(paste ≠ execute). Both are classic first-terminal confusion points that a
one-line tip would prevent.

**Fix:** Add a short callout near the start of Part 2:
```diff
  ## Part 2 — Run it
  [#part-2--run-it](#part-2--run-it)
+
+ > 💡 **Don't type these commands by hand — copy-paste them.** Select the
+ > text with your mouse, then paste into the terminal (Ctrl+Shift+V, or
+ > middle-click on Linux). This avoids typos in long commands. And note:
+ > pasting a command does NOT run it — you still need to press **Enter**
+ > afterward.

  1. In **Files**, open the `local-ai-memory-main` folder.
```

**Verification:** Read-only doc change.

---

## ISSUE-5 — LOW / INFORMATIONAL — `ai-memory-mux.sh` menu has no inline explanation of options

**Status:** Confirmed UX gap, not a functional bug.

**File:** `ai-memory-mux.sh` (the menu-printing function — search for the
literal strings `"open / attach"` / `"list sessions"` / `"kill session"`)

**Symptom:** First-time menu:
```
1) open / attach  (agent + terminal, mouse on)
2) list sessions        3) kill session
4) restart agent pane   5) tmux tips
0) plain shell (quit)
choice>
```
Options 2–5 and 0 have no explanation of when/why you'd pick them, unlike
option 1. A first-time user has no way to know these without trial and
error or reading the source.

**Fix:** Add one short parenthetical per option, matching option 1's style:
```diff
- 1) open / attach  (agent + terminal, mouse on)
- 2) list sessions        3) kill session
- 4) restart agent pane   5) tmux tips
- 0) plain shell (quit)
+ 1) open / attach   (agent + terminal, mouse on — start here)
+ 2) list sessions   (see what's already running)
+ 3) kill session    (stop a running session completely)
+ 4) restart agent pane  (just the agent crashed? restart it without touching your terminal pane)
+ 5) tmux tips       (keyboard/mouse shortcuts for this view)
+ 0) plain shell (quit)  (skip mux entirely, drop to a normal shell)
```
Adjust wrapping/column alignment to match the existing box-drawing style in
the file.

**Verification:** Run `ai-memory-mux.sh` fresh, confirm the menu still
renders inside its box-drawing borders without overflowing at 80-column
width.

---

## ISSUE-6 — UNRESOLVED / NOT A SCRIPT BUG — apt subprocess entered stopped (`T`) state during Step 0

**Status:** Observed once, cause unknown, not reproduced deliberately. Do
NOT attempt a code fix for this without further evidence — logging it here
only so a future occurrence can be cross-referenced.

**Symptom:** During Step 0 (`Installing Node.js 22...`), the backgrounded
`apt install -y apt-transport-https ca-certificates curl gnupg` process
(owned by root, launched via the script's `sudo` calls) was observed via
`ps aux` in state `T+` (stopped) for an extended period, with the terminal
showing no progress. `sudo kill -CONT <pid>` released it and installation
continued normally afterward. Killing it as the invoking user (without
`sudo`) failed with `Operation not permitted`, confirming the process ran as
root.

**What is NOT the cause:** Not a Ctrl+Z from the user (confirmed with the
tester). Not the `unattended-upgrades` apt lock (that was a separate,
correctly-handled, unrelated wait visible earlier in the same log — the
script's own "Package manager is busy... Waiting up to 5 min" handling
worked as designed).

**Possible directions if this recurs:**
- Check whether any part of the script's sudo-keepalive loop
  (`SUDO_KEEPALIVE_PID` — see the cleanup trap section) could send a signal
  that stops rather than merely refreshes a child process under specific
  timing.
- Check terminal emulator / desktop environment for anything that could
  send `SIGSTOP` to background job groups (e.g. a power-management or
  focus-follows-mouse quirk) — this looked environment-specific, not
  script-specific, but wasn't isolated enough to be sure.

**Do not "fix" this speculatively** — there isn't enough evidence to know
what to change. If it recurs, capture `ps aux` output at the time and the
parent process tree (`pstree -p <pid>`) before doing anything else.

---

## Summary table

| ID | Severity | Confirmed? | File | Fix complexity |
|----|----------|-----------|------|-----------------|
| ISSUE-1 | Critical | Yes, reproduced | `ai-memory-setup.sh:1140` | 1 line |
| ISSUE-2 | High | Yes | `ai-memory-configure.sh` (line TBD via grep) | Find/replace, ~1-5 lines |
| ISSUE-3 | Medium | Yes (doc) | `GET-STARTED.md` | Doc addition |
| ISSUE-4 | Low | Yes (doc) | `GET-STARTED.md` | Doc addition |
| ISSUE-5 | Low | Yes (UX) | `ai-memory-mux.sh` | Doc/string change |
| ISSUE-6 | Unknown | Observed once | Unknown | Do not fix blind — log only |

**Recommended fix order for an agent working through this file:** ISSUE-1
first (it blocks every fresh install), then ISSUE-2 (blocks the local-model
path for essentially all consumer hardware since `qwen3:7b` never existed),
then ISSUE-3/4/5 (docs/UX, any order), and leave ISSUE-6 alone until more
evidence exists.
