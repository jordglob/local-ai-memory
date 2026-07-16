#!/usr/bin/env bash
# =============================================================================
#  ai-memory-search.sh  v2.2
#  v2.2: recall also searches the vaults curated entities/ notes, not just the
#        raw session transcripts. The authoritative statement of a fact (who
#        the user is, where Hermes runs) often lives ONLY in a durable note the
#        hook never saw; now it does. Kept small (entities/ only) for speed.
#  v2.1: RECENCY ranking — when the vault holds both an OLD and a NEW statement
#        of a changed fact, run_search now breaks the term-coverage tie by
#        DATE (newer first) instead of raw hit-frequency, which used to let the
#        older, more-repeated fact win and get injected as the answer. Term
#        coverage still dominates; recency only decides between equal hits.
#  v2.0: STRUCTURAL SPLIT — the embedded python program moved out of the
#        mktemp-copied heredoc into lib/aimem_search.py (+ shared helpers in
#        lib/aimem_common.py, also used by ingest). This file is now a thin
#        launcher: same name, same flags, same behavior — it resolves lib/
#        next to itself (repo checkout AND the <vault>/.tools/ install, where
#        setup/configure place lib/ alongside) and execs the engine with stdin
#        intact (--hook still reads its payload; no temp file needed anymore).
#  v1.4: --hook handles TIME/META memory questions ("what did we talk about
#        yesterday / last week / recently"). These have no strong topic term,
#        so the model used to fall back to hermes' own session_search (blind to
#        the vault) and find nothing (live gap 2026-07-08). Now the hook detects
#        the time/meta phrasing and injects a dated list of RECENT conversations
#        from the vault INDEX (windowed to yesterday / last week / etc.).
#  v1.3: --hook also surfaces VALUE/PRICE lines from the top file even when the
#        query word missed them (asked "dollar", file wrote "USD"). Live proof:
#        with v1.2 glm4 read the injection and named the product but said the
#        price was "not specified" — the term-ranked snippet had skipped the
#        "$1,880" line. Now "what did it cost" answers land.
#  v1.2: PORTABILITY FIX — the v1.1 fd-3 source trick (python3 /dev/fd/3 3<<EOF)
#        read stdin on Linux but SILENTLY failed on macOS bash 3.2 (the Mac
#        mini), so --hook produced nothing there (live 2026-07-08). The source
#        is now written to a temp file and run from there — stdin stays free for
#        the hook payload on BOTH platforms.
#  v1.1: NEW --hook mode — a hermes `pre_llm_call` shell hook that reads the
#        turn on stdin, searches the vault for the user's message, and INJECTS
#        the top hits into the turn. This is the MODEL-AGNOSTIC path: live tests
#        proved small models will not CALL a search tool from SOUL (0/9), so we
#        stop relying on the model — the search runs automatically and the model
#        just reads the results. Silent (no injection) on weak/no hits.
#  Deterministic memory retrieval for the AI Memory Stack — ONE command an
#  agent (any model, however small) can call instead of hand-rolling a
#  multi-term grep strategy it may not follow.
#
#  Why this exists (§4.5 — deterministic work is a script, not model reasoning):
#  live tests (2026-07-07) showed small local models FAIL vault recall not
#  because the data is missing but because they give up after one grep, pick a
#  weak keyword, or invoke a "memory" tool that reads the agent's own session
#  db. The persistent, multi-term, INDEX-aware search is DETERMINISTIC — so it
#  belongs in a script. The model supplies a topic; this returns ranked files
#  with the answer-bearing lines already surfaced.
#
#  What it does: tokenizes the query, scores every 05-AI-Sessions/*.md file by
#  how many DISTINCT query terms it contains (coverage dominates) then by hit
#  frequency, and prints the top files with the lines that match the most terms
#  — so the answer is usually visible in the snippet without opening the file.
#
#  Usage:
#    bash ai-memory-search.sh [vault] "your topic in your own words"
#    bash ai-memory-search.sh --query "..." [--top N] [vault]
#  Prints ranked hits to stdout. Exit 0 with hits, 0 with a clear "no match"
#  line (never a silent empty), 1 only on a usage/vault error.
# =============================================================================
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 1; }

# ── thin launcher (v2.0) ──────────────────────────────────────────────────────
# This bash file is the public interface (same name, same flags); the program
# itself is lib/aimem_search.py. exec keeps stdin INTACT, so --hook still reads
# its pre_llm_call payload from stdin (the v1.2 mktemp dance is obsolete — the
# engine is a real file now). Two valid layouts, tried in order:
#   (a) <this script's dir>/lib/aimem_search.py   — repo checkout / bundle,
#       and the installed copy too (<vault>/.tools/ + <vault>/.tools/lib/)
#   (b) <vault>/.tools/lib/aimem_search.py        — a stray copy of this .sh,
#       resolved via a vault given as an argument, else the default vault.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENGINE="aimem_search.py"
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
    echo "ai-memory-search: python engine not found ($ENGINE)."
    echo "This launcher needs the lib/ directory in one of the two valid layouts:"
    echo "  repo/bundle:  <dir>/ai-memory-search.sh  +  <dir>/lib/$ENGINE"
    echo "  installed:    <vault>/.tools/ai-memory-search.sh  +  <vault>/.tools/lib/$ENGINE"
    echo "Fix: re-run setup or configure to (re)install the tools into <vault>/.tools/,"
    echo "or restore the lib/ directory next to this script."
  } >&2
  exit 1
fi
# No __pycache__ droppings in the repo or the vault's .tools/lib (and never a
# stale .pyc shadowing an upgraded engine). Costs nothing at this scale.
export PYTHONDONTWRITEBYTECODE=1
exec python3 "$LIBDIR/$ENGINE" "$@"
