#!/usr/bin/env bash
# =============================================================================
#  ai-memory-ingest.sh  v3.2
#  Import scattered AI conversations into the vault — 13 sources
#  v3.1:  Vault conversation notes are GENERATED artifacts — ingest always
#         regenerates a changed conversation in place. The v2.27 "never
#         overwrite a hand-edited file" guard is REMOVED: it re-proved the
#         stored hash by round-tripping rendered markdown back to source
#         text, so brittle that v3.0's cleaning changes false-flagged every
#         pre-v3.0 note as `edited` and silently froze it forever (live
#         incident 2026-07-12→14: active CC sessions stopped updating).
#         Manual commentary belongs in separate notes that link to the
#         conversation file. The `edited` summary column is gone; the
#         stored hash remains for what it is FOR — skip-if-unchanged.
#  v3.0:  STRUCTURAL SPLIT — the ~1,550-line embedded python program moved out
#         of the heredoc into lib/aimem_ingest.py (+ shared helpers in
#         lib/aimem_common.py, also used by search). This file is now a thin
#         launcher: same name, same flags, same behavior — it resolves lib/
#         next to itself (repo checkout AND the <vault>/.tools/ install, where
#         setup/configure place lib/ alongside) and execs the engine. The
#         engines are plain importable python (testable, no bash extraction).
#  v3.2:  NEW `--with-cli` flag — hermes sessions tagged source='cli' are
#         skipped by default (v2.24: one-shot `hermes -z` noise), but a
#         state.db SYNCED from a satellite machine tags its interactive
#         sessions 'cli' too, so the default filter silently archived zero
#         of them. --with-cli disables the filter; the satellite watcher
#         passes it. Default behaviour unchanged. Regression: tests 6n.
#  v2.29: the next-steps footer names the mux cockpit (bash ai-memory-mux.sh,
#         back in the family as the standard interface) as the talk-to-your-
#         agent step, `hermes chat` staying the no-tmux path; an interactive
#         run offers to open the cockpit (default yes, tmux present only) —
#         non-interactive/--yes runs still only PRINT the command (the v2.15
#         no-takeover rule is untouched).
#  v2.28: the fleet/remote layer moved to the companion repo
#         local-ai-memory-fleet — the next-steps footer no longer points at
#         the remote node-setup script (it doesn't ship here anymore).
#  v2.27: DATA-SAFETY round. (1) Conversation ids are never truncated — a
#         12-char cut collided every same-day codex session (stems start with
#         the timestamp) and trimmed gemini-cli/openclaw/cursor/lmstudio/
#         open-webui ids too; over-long ids now get a sha1-suffixed filename
#         instead of a lossy cut. (2) A prior import is found by the EXACT
#         `- id:` line embedded in the file — the old `*-{id}.md` suffix-glob
#         could bind to a DIFFERENT conversation whose id merely ended the
#         same way and then overwrite it. MIGRATION: a file written by ≤v2.26
#         under a truncated id is ADOPTED in place on the next run (its id
#         line is upgraded to the full id; the filename never changes), not
#         duplicated. (3) A vault file the USER edited by hand (its content no
#         longer matches its own stored hash) is WARNED about and SKIPPED,
#         never overwritten — new `edited` column in the summary. (4) All
#         vault writes are atomic (tempfile + os.replace): no half-written
#         conversation/INDEX on a crash. (5) Titles are secret-scrubbed before
#         they reach the heading, the slug or the FILENAME (bodies already
#         were). (6) Honest exit code: any failed conversation → exit 1.
#         (7) Non-interactive (no TTY) prompts now default to NO unless --yes
#         — a cron/hook run must not import Downloads zips without consent.
#  v2.26: secret-scrub adds `github_pat_*` (fine-grained PATs) — the `gh[pousr]_`
#         pattern only caught classic/OAuth tokens; modern fine-grained PATs
#         (github_pat_…) slipped through. Closes the exact leak vector where a
#         pasted PAT rode a CC transcript into the synced vault.
#  v2.25: `--local` sweeps every directory/db-based agent store (hermes,
#         claude-code, codex, gemini-cli, cursor, aider, lmstudio, open-webui,
#         openclaw) and SKIPS the zip/Downloads exporters. This is the OS-general,
#         not-CC-specific ingest the configure self-ingest hook fires — one
#         FDA-safe session hook archives ALL local agents, no per-OS scheduler.
#  v2.24: `hermes` source SKIPS source='cli' sessions — self-ingest archives
#         interactive (tui/dashboard) + gateway conversations, not one-shot
#         `hermes -z` automation/scripting. Closes the self-ingest loop (agent
#         remembers its own chats) without polluting the vault with dev/test
#         one-shots. Source-agnostic between direct (tui) and gateway.
#  v2.23: --ai-titles treats ALL models equally — reasoning models included.
#         (1) The qwen-specific /no_think prompt hack is gone (no model gets
#         special prompt text). (2) A blank from the OpenAI endpoint gets a
#         second chance via ollama's NATIVE /api/generate (think:false, then
#         without the key for models that reject it) — the live-verified path
#         qwen3.6:35b answers on while ollama 0.31.1's OpenAI endpoint blanks
#         its replies. Non-ollama servers 404 the fallback and lose nothing.
#         v2.20's "prefer a non-reasoning model" guidance is hereby obsolete.
#  v2.22: --ai-titles: one blank reply no longer kills the whole run. Live
#         evidence (2026-07-07): blanks are CONTENT-dependent — one specific
#         tiny conversation reliably drew an empty completion while its
#         neighbours titled fine, so the v2.20 dead-flag benched titling for
#         every later conversation. Now: warn + fallback for THAT conversation
#         and continue; only 3 consecutive blanks (a real model/endpoint
#         failure) disable titling for the rest of the run.
#  v2.21: --ai-titles retries ONCE on an empty reply — ollama can 200-OK a
#         blank completion; the retry rescues transient blanks. Still-empty
#         after the retry stays loud (v2.20 promise) + fallback titles.
#  v2.20: --ai-titles EMPTY-REPLY fix (live run 2026-07-07): ollama's OpenAI
#         endpoint can 200-OK a BLANK completion for a reasoning model (the
#         reply is generated but arrives as empty content, zero usage —
#         seen with qwen3.6:35b on ollama 0.31.1; the model itself was fine
#         via /api/generate). v2.19 silently fell back for every conversation
#         — a silent zero. Now: one loud warn on the first empty reply, then
#         fallback titles for the rest of the run. Practical guidance: point
#         --ai-titles at a small non-reasoning model (AI_MEMORY_MODEL=gemma…);
#         titling needs speed, not reasoning.
#  v2.19: BETTER TITLES (live round 2026-07-07 — vault listings showed raw
#         first-prompt headings like "Uppgift, svara direkt utan att...").
#         (1) hermes source reads the session's OWN title from state.db
#         (sessions.title — the column was always there, never read); the
#         raw-prompt fallback remains for untitled sessions. (2) Generic
#         RETITLE-IN-PLACE in write_conv: same content + a better title →
#         the heading is rewritten in the SAME file (filenames never change
#         after first import — the add-only sync would duplicate a rename).
#         (3) Opt-in `--ai-titles`: untitled conversations get a short title
#         from the already-configured local model (§4.5 hybrid; env
#         AI_MEMORY_MODEL_URL/AI_MEMORY_MODEL or .mcp/ai-config.json, else
#         localhost ollama). Never a hard dependency: any failure falls back
#         to the raw-prompt title and the import still succeeds. A heading
#         once upgraded (by hermes or the model) is never downgraded back.
#  v2.18: openclaw source filters SCHEDULER NOISE — live run 2026-07-06 found
#         719 of 724 sessions were `[cron:...]` agent runs (car-search jobs
#         etc.) drowning the 5 human conversations. Cron-initiated sessions
#         (first user message starts with `[cron:`) are now SKIPPED by default
#         and reported loudly (never a silent zero); `--with-cron` imports
#         them into a separate `openclaw-cron/` dir so recall on the main
#         `openclaw/` dir stays signal-dense.
#  v2.16: NEW `aistudio` source — Google AI Studio saves its threads to the
#         Drive folder "Google AI Studio" (download it → drive zip). Each
#         extension-less member is one thread: JSON with chunkedPrompt.chunks
#         (text / parts / driveImage / inlineImage). Full threads INCLUDING
#         the model's responses and real createTime timestamps. isThought
#         reasoning chunks are filtered as noise; image chunks become
#         _[attached ...]_ notes (media itself is deliberately not vaulted).
#  v2.15: gemini-takeout parser rebuilt against a real 2026 export (live round
#         2026-07-05, Swedish-locale account): (1) locale-independent — entries
#         are parsed from the My Activity cell STRUCTURE and the verb/prompt
#         NBSP separator, not the English word "Prompted" (a Swedish export
#         silently imported 0); (2) Gemini's RESPONSES are captured — modern
#         Takeout includes them, the old "prompts only" caveat no longer holds;
#         (3) one conversation per DAY instead of one file for the whole
#         history; (4) never a silent zero — activity HTML with 0 parsed
#         entries warns loudly, and an explicit --source always gets its
#         summary row; (5) end-of-run "Start your agent?" defaults to NO and
#         is skipped under --yes — a non-interactive run must never exec an
#         interactive agent (it hijacked a shared tmux pane in the live round).
#  v2.14: (1) NEW `hermes` source — the local agent's own session history
#         (~/.hermes/state.db) is archived into the vault, closing the loop:
#         the agent's short-term memory becomes searchable long-term memory.
#         (2) SECRET-SCRUB on every import — pasted API keys, tokens and
#         private keys are redacted before a conversation is written, so a
#         synced/exported vault upholds "secrets never travel" even when the
#         original chat contained one. Re-running ingest sanitizes files
#         imported by older versions (hash changes → rewritten redacted).
#  v2.13: claude-code source made first-class — under WSL the Windows-side
#         profile (/mnt/<drive>/Users/<name>/.claude/projects) is discovered
#         too; real session titles (aiTitle), stable created-timestamp from
#         the first message, and harness noise (command tags, system
#         reminders, tool outputs, subagent sidechains) is filtered out.
#  v2.12: true idempotency — identity keyed on stable conversation id +
#         content hash (mtime no longer forks duplicates; grown chats refresh);
#         path-safe id/date components; uncompressed-size cap on zip members.
#
#  Sources: claude-web, chatgpt, claude-code, codex, gemini-cli, openclaw,
#           cursor, aider, lmstudio, open-webui, gemini-takeout, hermes,
#           aistudio
#
#  Discovery (three tiers):
#    default      known per-source paths + targeted ~/Downloads export sniffing
#    --scan DIR   also search DIR for exports/history files
#    --deep-scan  search your whole home directory (asks first)
#
#  Usage:
#    bash ai-memory-ingest.sh [vault] [export.zip]      auto-detect zip type
#    bash ai-memory-ingest.sh --list-sources
#    bash ai-memory-ingest.sh --source chatgpt --path ~/Downloads/export.zip
#    bash ai-memory-ingest.sh --all --yes               non-interactive
#    bash ai-memory-ingest.sh --source hermes --ai-titles   model-titled headings
#
#  Idempotent: matched by stable conversation id — identical chats are skipped,
#  grown/edited chats are refreshed in place (content hash), never duplicated.
# =============================================================================
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 1; }

# ── thin launcher (v3.0) ──────────────────────────────────────────────────────
# This bash file is the public interface (same name, same flags); the program
# itself is lib/aimem_ingest.py. Two valid layouts, tried in order:
#   (a) <this script's dir>/lib/aimem_ingest.py   — repo checkout / bundle,
#       and the installed copy too (<vault>/.tools/ + <vault>/.tools/lib/)
#   (b) <vault>/.tools/lib/aimem_ingest.py        — a stray copy of this .sh,
#       resolved via a vault given as an argument, else the default vault.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENGINE="aimem_ingest.py"
LIBDIR=""
if [ -f "$SCRIPT_DIR/lib/$ENGINE" ]; then
  LIBDIR="$SCRIPT_DIR/lib"
else
  for arg in "$@"; do
    case "$arg" in -*) continue ;; esac
    if [ -d "$arg" ] && [ -f "$arg/.tools/lib/$ENGINE" ]; then
      LIBDIR="$arg/.tools/lib"; break
    fi
  done
  if [ -z "$LIBDIR" ] && [ -f "$HOME/Documents/ai-memory/.tools/lib/$ENGINE" ]; then
    LIBDIR="$HOME/Documents/ai-memory/.tools/lib"
  fi
fi
if [ -z "$LIBDIR" ]; then
  {
    echo "ai-memory-ingest: python engine not found ($ENGINE)."
    echo "This launcher needs the lib/ directory in one of the two valid layouts:"
    echo "  repo/bundle:  <dir>/ai-memory-ingest.sh  +  <dir>/lib/$ENGINE"
    echo "  installed:    <vault>/.tools/ai-memory-ingest.sh  +  <vault>/.tools/lib/$ENGINE"
    echo "Fix: re-run setup or configure to (re)install the tools into <vault>/.tools/,"
    echo "or restore the lib/ directory next to this script."
  } >&2
  exit 1
fi
# No __pycache__ droppings in the repo or the vault's .tools/lib (and never a
# stale .pyc shadowing an upgraded engine). Costs nothing at this scale.
export PYTHONDONTWRITEBYTECODE=1
exec python3 "$LIBDIR/$ENGINE" "$@"
