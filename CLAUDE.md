# CLAUDE.md — working agreement for local-ai-memory

**`docs/REQUIREMENTS.md` is the source of truth.** It holds the design, the
backlog, and the build discipline (§5). If anything in *this* file conflicts
with the spec, the spec wins — and say so, don't silently follow this file.
This file is habits, not a second spec; don't duplicate the spec here (it drifts
and starts to contradict).

## Hard rules (non-negotiable)
- **Never touch `~/.paperclip`** — irreplaceable, unrelated to this project.
- **Never run as root / `sudo` yourself** — the scripts call `sudo` where they
  need it; that's by design.
- This is a **backed-up test machine**: work freely, run things, and don't ask
  permission for routine steps. Confirm only genuinely destructive or
  outward-facing actions (e.g. pushing a remote, deleting data you didn't make).

## The repo in one breath
Four self-contained bash scripts — `setup` → `configure` → `ingest` → `remote`
— plus the spec. Bash-portable, idempotent, secrets never logged. Read §2.8 for
the family conventions before adding to any of them; match the surrounding code.

## How to work here (habits that have paid off, not a checklist to perform)
- **Read the spec before a build/design round** — fully, not skimmed — and
  before touching any behavior it describes. For a genuinely trivial one-off,
  use judgement; don't ritualize it.
- **Live-test on this machine before calling anything done.** The sandbox lies
  (§5): `bash -n` + a clean run is the floor; real behavior is the bar. If a
  path can't be tested here (e.g. a WSL path on this non-WSL box), label it
  **written-but-unproven** — never "done".
- **Pattern-hunt every real bug (§5.3):** fix the *class* across all four
  scripts, not the one instance.
- **Verify before you claim:** read a file back after writing it; check a tool
  exists before assuming it; report what actually happened — including failures
  and skipped steps. A green log that did nothing is a bug, not a success.
- **Real bug vs noise:** an absent optional source/tool, or a "no Anthropic key"
  when only OpenRouter is used, is fine — don't chase it. Don't rewrite working
  code for style.

## Shipping conventions (match what's there; don't reinvent)
- **Versioning:** bump the changed script's version (header + `--version` +
  banner) *and* `PACKAGE_VERSION.txt`. Package zips are
  `local-ai-memory-repo_v<N>_<WEB|CC>_<date>_<main-build-event>.zip` (from v12 on,
  the kebab-case `<main-build-event>` suffix names the headline change so the
  filename alone says what shipped). When you (Claude Code) ship a bundle, you are
  **CC**. Bundle = `zip -r` the clean working tree (no `.git`) from the parent dir,
  then set the archive comment to the HEAD commit hash (`zip -z`).
- **Keep shipped scripts + README generic** — no machine names, personal paths,
  or one-box specifics. `REQUIREMENTS.md` may keep live-run lessons as history.
- **When a live test contradicts the spec, fix the code AND correct the spec**
  (note the finding). The spec is "truth" only because we keep it true.
- **Git:** commit only what the task asks; one commit per logical change in the
  existing history's style. Solo repo, linear mainline — no branch/PR ceremony.

## Keep your judgement
Do the round's scope and then stop; don't wander into backlog items unprompted.
If a rule here or a line in the spec looks wrong for the situation in front of
you, say so rather than following it off a cliff. This file exists to remove
re-discovery and re-litigation, not to replace thinking.
