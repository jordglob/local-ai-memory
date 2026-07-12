> **Historical snapshot (moved 2026-07-12).** Superseded by [`TESTING.md`](../../TESTING.md), the provenance ledger — in particular, the "still open" claim at the bottom is stale: the first real-hardware macOS run happened on 2026-07-03 and is recorded there.

# Onboarding notes — live-run lessons

Honest, dated record of what real beginner testing ("naive-user dogfooding") taught
us about getting from a blank machine to a running stack. Kept as history (CLAUDE.md:
the project may keep live-run lessons).

## 2026-07-03 — the "blank machine" onboarding walk

A first-timer tried to install from a fresh/imaged machine and hit three walls in a
row: `git: command not found`, then `curl`/`wget` missing, then apt refusing unsigned
sources (*"…can't be done securely…"*). Peeling each layer showed they were the **same
root cause, not three bugs**.

**Immediate root cause:** the machine wasn't a real, general-purpose Linux install —
it was a live/cloner/minimal environment (Clonezilla-style: runs from RAM, stripped of
tools, minimal/unsigned apt sources). Nothing installs; nothing persists.

**Durable lessons (not machine-specific):**
1. **Start docs at the *true floor*.** The README opened with `git clone`, assuming
   git → curl → working apt. Any minimal environment (minimal server, container, fresh
   WSL, netboot) breaks the same way. Begin where the user actually is: a blank machine.
2. **You can't download the downloader with nothing.** On a fresh machine the only
   universal primitives are a **web browser** (→ "Download ZIP", zero CLI tools) and a
   **package manager** (→ can add curl/git). Everything else is built on those. The
   browser+ZIP path is the only genuinely no-tool route.
3. **One root cause can wear three costumes.** Fix the environment assumption
   underneath, not the surface symptom (don't just swap git→curl→wget).
4. **Dogfooding finds what code review can't.** Five reviewers audited the *code*; none
   audited the step *before* step 1. Walk the pre-install path with a naive user.

**Result:** `GET-STARTED.md` rewritten to begin at **Part 0** (install a real desktop
Linux — not Clonezilla/minimal) and to get files via the **browser ZIP**; the
`curl … | bash` one-liner demoted to a "once you're on a real Linux" shortcut.

**Still open (important):** this exercise tested the *onboarding docs*, **not the
scripts**. The `setup → configure → ingest → doctor` chain (with the v22 hardening)
remains **UNPROVEN on real hardware** — the first real-hardware run is still pending.
