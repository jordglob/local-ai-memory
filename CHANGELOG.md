# Changelog

One entry per tagged release; per-script versions move independently and live
in each script's header. History before v50 is in
`docs/history/PACKAGE_VERSION.txt` (the zip-bundle era, frozen).

## v53 — 2026-07-16

- **Recency ranking in memory search** (search v2.1). When the vault holds both
  an OLD and a NEW statement of a fact that changed (a job renamed, an agent
  that moved host), the two match a query equally on terms — and the older,
  more-repeated one used to win on hit-frequency and get injected as "the
  answer". `run_search` now breaks the term-coverage tie by **freshness**
  (a note's last-write mtime, days since 2020) instead of raw frequency; term
  coverage still dominates, so a richer canonical note is unaffected and
  recency only decides between equally-relevant hits. mtime (not the filename's
  YYYY-MM-DD start-date prefix) is the signal, so a long-running session that
  keeps appending today's facts ranks fresh. Motivated by a 16-question live
  recall eval (2026-07-16): both nex-n2-mini and qwen3.6 failed mainly on
  recently-changed facts, confidently retrieving the stale version. Two tests
  lock it (newer-wins ordering + coverage-still-dominates guard).
- KNOWN GAP (not yet fixed): the recall hook only indexes `05-AI-Sessions/`,
  not the durable memory notes — so a fact that lives only in a memory file is
  invisible to search regardless of recency.

## v52 — 2026-07-14

- **sync push never downgrades the central's tools** (sync v1.3). The
  unconditional "keep the toolbox current" rsync let any stale clone revert
  the central's newer tools on every push — live incident 2026-07-14→15: a
  v2.26 clone's nightly autosync overwrote the central's fresh v3.1 at 21:00
  each evening, with preserved old mtimes masking the write. Now the install
  is gated on `_tool_newer` (strictly newer by `sort -V`; missing remote =
  first install; unparsable local installs nothing), and `lib/` ships with
  the launcher — a v3.0+ launcher is thin and dead without its engine.
  Locked by tests (semantics incl. `3.10 > 3.9`, and that push actually
  gates on it).
- **Conversation notes are generated artifacts — the edited-by-hand freeze is
  gone** (ingest v3.1). The v2.27 "never overwrite a hand-edited file" guard
  re-proved a note's stored hash by round-tripping its rendered markdown back
  to source text (including trying every role-label combination). Any version
  change to cleaning/rendering broke that round-trip, false-flagging every
  older note as `edited` and silently freezing it forever — live incident
  2026-07-12→14: v3.0's cleaning changes froze the active Claude Code sessions'
  notes while sync and ingest both reported green. Ingest now always
  regenerates a changed conversation in place; the stored hash keeps doing its
  functional job (skip-if-unchanged idempotence); the `edited` summary column
  and warning are removed, `_disk_hash_ok` and the label→role table deleted.
  Manual commentary belongs in separate notes that link to the conversation
  file — MANUAL.md updated accordingly.

## v51 — 2026-07-12

- **Fleet split.** The remote + netboot layer moved to the companion repo
  `local-ai-memory-fleet` — nothing left in this repo can lock you out of a
  machine.
- **mux returns as the standard interface** (mux v1.3): a side-by-side tmux
  cockpit (agent pane + vault pane), wired into the setup → configure → ingest
  chain (setup v8.20, configure v5.12, ingest v2.29 point at it).
- **Python engines extracted to `lib/`** (`aimem_common` / `aimem_ingest` /
  `aimem_search`): ingest v3.0 and search v2.0 are now thin launchers — same
  names, same flags — and the parsers are unit-testable, with the
  secret-pattern set in one shared module. setup v8.21 / configure v5.13
  install `lib/` into `<vault>/.tools/lib` alongside the tools.
- **User manual added:** `docs/MANUAL.md`, written from the user's side of the
  screen — passwords vs API keys vs SSH, what leaves your machine, how recall
  works and its honest limits.
- **Versioning collapsed to git tags + this file.** The zip-bundle ledger is
  frozen at `docs/history/PACKAGE_VERSION.txt`; each script keeps exactly one
  `VERSION` constant that `--version` and the banner derive from (uninstall
  v1.5 fixes the last stragglers, including an export manifest that had
  drifted to a stale number).

## v50 — 2026-07-12

Hardening round from a four-angle external review (onboarding, data path,
dangerous surface, docs/process):

- **Ingest identity + atomicity** (ingest v2.27, sync v1.1): conversation ids
  are never truncated (kills a same-day-collision overwrite class), exact
  embedded-id binding with legacy adoption, atomic writes, user-edited vault
  files detected and never clobbered, titles/filenames secret-scrubbed, exit 1
  on failures; sync's outgoing secret gate rebuilt to match ingest's full
  pattern set (parity locked by a test).
- **Remote lockout-proofing** (remote v2.10, uninstall v1.3): `--yes` can
  never disable password auth, root-owned revert sentinel (no /tmp forgery),
  sshd_config backup + auto-restore, working macOS revert fallback; uninstall
  exports Hermes' own state.db before removal.
- **Onboarding decision-load cut** (setup v8.18, configure v5.11, bootstrap):
  exec handoffs stop orphaning the sudo keepalive / leaking tmpdirs, live log
  path for the whole run, Anthropic prompt cut, autostart default with a
  stated opt-out, one atomic config.yaml editor replaces three regex editors.
- **Docs truth-sync + SPEC extraction:** README proven/unproven matches
  TESTING.md, `docs/SPEC.md` extracted as the normative spec, the design
  journals frozen under `docs/history/`.
- Also in this release span: validated MoA presets for `/moa` (configure
  v5.10) and a fine-grained GitHub PAT pattern in the secret scrub (ingest
  v2.26).
