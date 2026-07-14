#!/usr/bin/env bash
# =============================================================================
#  tests/run.sh — the AI Memory Stack's first automated safety net.
#
#  Fast, dependency-light checks that a machine (or CI) can run in seconds:
#    • bash -n parse of every script
#    • shellcheck of every script        (skipped with a note if not installed)
#    • --version / --help smoke tests     (exit 0, prints a version)
#    • version consistency                (one VERSION constant per script;
#      --version, banner and header comment all agree with it)
#    • regression: uninstall --no-export --yes must NOT delete without the
#      loud DELETE confirm / --force-no-export  (locks in the v1.2 fix)
#    • mux: a real tmux session has 2 SIDE-BY-SIDE panes + mouse on — the
#      standard-interface default (skipped if no tmux)
#
#  Kept bash-3.2 / macOS safe on purpose (the scripts target bash 3.2, and the
#  macOS CI runner's /bin/bash IS 3.2): no associative arrays, no mapfile, no
#  ${x,,}. Portable enough to run under git-bash, WSL, Linux and macOS.
#
#  Usage:  bash tests/run.sh
#  Exit:   0 = all checks passed (skips allowed) · 1 = a check failed
# =============================================================================
set -uo pipefail

# ── locate repo root (this file lives in <root>/tests/) ──────────────────────
here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/.." && pwd)
cd "$ROOT" || exit 1

if [ -t 1 ]; then
  R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[1m'; D='\033[2m'; N='\033[0m'
else
  R=''; G=''; Y=''; B=''; D=''; N=''
fi

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); printf "  ${G}ok${N}   %s\n" "$1"; }
fail() { FAIL=$((FAIL+1)); printf "  ${R}FAIL${N} %s\n" "$1"; [ -n "${2:-}" ] && printf "       ${D}%s${N}\n" "$2"; }
skip() { SKIP=$((SKIP+1)); printf "  ${Y}skip${N} %s\n" "$1"; }
hdr()  { printf "\n${B}── %s ──${N}\n" "$1"; }

# Family scripts must carry --help/--version/--yes and a consistent version
# (§2.8). publish-to-github.sh is an internal helper: syntax + shellcheck only.
FAMILY="ai-memory-setup.sh ai-memory-configure.sh ai-memory-ingest.sh ai-memory-doctor.sh ai-memory-uninstall.sh ai-memory-mux.sh ai-memory-sync.sh ai-memory-search.sh"
HELPERS="publish-to-github.sh"
SCRIPTS="$FAMILY $HELPERS"

# Hygiene-only targets: linted + parse-checked like everything else, but they
# carry no --version/--help/version-consistency contract, so they stay out of
# $FAMILY. Includes this harness itself — otherwise the one file that lints all
# the others is the one file the linter never sees (that blind spot is exactly
# how a stray pseudo-directive comment once slipped into this very file).
LINT_ONLY="bootstrap.sh tests/run.sh"

# Real python3? The Windows Store alias is a stub that fails imports; ingest is
# a python script, so its runtime smokes are skipped where python3 isn't real.
PY_OK=0
python3 -c 'import sys' >/dev/null 2>&1 && PY_OK=1

# Locate the shellcheck binary on PATH, or the winget install path on Windows.
SHELLCHECK=""
if command -v shellcheck >/dev/null 2>&1; then
  SHELLCHECK=shellcheck
else
  for c in "${LOCALAPPDATA:-/nonexistent}/Microsoft/WinGet/Packages"/koalaman.shellcheck_*/shellcheck.exe; do
    [ -f "$c" ] && { SHELLCHECK="$c"; break; }
  done
fi

TMP=$(mktemp -d 2>/dev/null || echo "/tmp/aimtest.$$")
mkdir -p "$TMP"
cleanup() { rm -rf "$TMP" 2>/dev/null; [ -n "${STUB_PID:-}" ] && kill "$STUB_PID" 2>/dev/null; command -v tmux >/dev/null 2>&1 && tmux kill-session -t aimtest_mux 2>/dev/null; return 0; }
trap cleanup EXIT

# ── 1. bash -n parse ─────────────────────────────────────────────────────────
hdr "bash -n (syntax)"
for s in $SCRIPTS $LINT_ONLY; do
  [ -f "$s" ] || { skip "$s (absent)"; continue; }
  if out=$(bash -n "$s" 2>&1); then pass "$s"; else fail "$s" "$out"; fi
done

# ── 2. shellcheck (LF-normalized so CRLF working trees don't false-positive) ──
hdr "shellcheck"
if [ -z "$SHELLCHECK" ]; then
  skip "shellcheck not installed (install: apt-get install shellcheck)"
else
  for s in $SCRIPTS $LINT_ONLY; do
    [ -f "$s" ] || continue
    mkdir -p "$TMP/$(dirname "$s")"          # $s may be nested (e.g. tests/run.sh)
    tr -d '\r' < "$s" > "$TMP/$s"
    if out=$("$SHELLCHECK" -S warning "$TMP/$s" 2>&1); then pass "$s"; else fail "$s" "$out"; fi
  done
fi

# ── 2b. python engine (lib/) — syntax + import smoke (ingest v3.0/search v2.0) ─
# The ingest/search entrypoints are thin launchers over lib/aimem_*.py. Compile
# and import them from a TMP copy so the check never litters the working tree
# with __pycache__/.
hdr "python engine (lib/aimem_*.py)"
if [ "$PY_OK" = 0 ]; then
  skip "no real python3 here"
elif [ ! -f lib/aimem_common.py ]; then
  fail "lib/aimem_common.py missing (ingest/search launchers cannot run)"
else
  mkdir -p "$TMP/libcheck"
  cp lib/aimem_common.py lib/aimem_ingest.py lib/aimem_search.py "$TMP/libcheck/" 2>/dev/null
  for p in aimem_common.py aimem_ingest.py aimem_search.py; do
    if [ ! -f "$TMP/libcheck/$p" ]; then fail "lib/$p missing"; continue; fi
    if out=$(python3 -m py_compile "$TMP/libcheck/$p" 2>&1); then
      pass "lib/$p compiles (py_compile)"
    else
      fail "lib/$p does not compile" "$out"
    fi
  done
  if out=$(cd "$TMP/libcheck" && python3 -c 'import aimem_common, aimem_ingest, aimem_search' 2>&1); then
    pass "import smoke: all three modules import (no top-level side effects)"
  else
    fail "lib import smoke" "$out"
  fi
fi

# ── 3. --version / --help smoke ──────────────────────────────────────────────
hdr "--version / --help"
for s in $FAMILY; do
  [ -f "$s" ] || continue
  if [ "$s" = ai-memory-ingest.sh ] && [ "$PY_OK" = 0 ]; then skip "$s (no real python3 here)"; continue; fi
  v=$(bash "$s" --version 2>/dev/null)
  if [ $? -eq 0 ] && printf '%s' "$v" | grep -qE 'v[0-9]+\.[0-9]+'; then
    pass "$s --version  ($v)"
  else
    fail "$s --version" "expected exit 0 + a vX.Y, got: $v"
  fi
  if bash "$s" --help >/dev/null 2>&1; then pass "$s --help"; else fail "$s --help" "non-zero exit"; fi
done

# ── 4. version consistency (one VERSION constant per script) ─────────────────
# Each script has exactly ONE authoritative version: the VERSION="x.y" constant
# near the top of the .sh — or, for the thin launchers (ingest/search), the
# VERSION in the lib/ engine. Everything else must DERIVE from it:
#   (a) --version prints it (runtime proof the flag reads the constant),
#   (b) any banner (║ box line) references $VERSION / {VERSION}, never a
#       hardcoded number that can drift,
#   (c) the header comment (documentation) states the same number.
hdr "version consistency"
for s in $FAMILY; do
  [ -f "$s" ] || continue
  case "$s" in
    ai-memory-ingest.sh) src=lib/aimem_ingest.py ;;
    ai-memory-search.sh) src=lib/aimem_search.py ;;
    *)                   src=$s ;;
  esac
  const=$(grep -m1 -E '^VERSION *= *"[0-9]+\.[0-9]+"' "$src" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+')
  if [ -z "$const" ]; then fail "$s: no VERSION constant" "expected VERSION=\"x.y\" in $src"; continue; fi
  if [ "$src" != "$s" ] && [ "$PY_OK" = 0 ]; then skip "$s (no real python3 here)"; continue; fi
  # (a) --version output carries exactly the constant
  vflag=$(bash "$s" --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+' | head -1)
  if [ "$vflag" = "v$const" ]; then flag_ok=1; else flag_ok=0; fi
  # (b) banner box lines never hardcode a version — they must read the constant
  if grep -E '║' "$src" | grep -qE 'v[0-9]+\.[0-9]+'; then ban_ok=0
  elif grep -E '║' "$src" | grep -q 'VERSION'; then ban_ok=1   # derives from the constant
  else ban_ok=2; fi                                            # no version banner — fine
  # (c) header comment (first lines of the .sh) states the same number
  if head -6 "$s" | grep -qF " v$const"; then hdr_ok=1; else hdr_ok=0; fi
  if [ "$flag_ok" = 1 ] && [ "$ban_ok" != 0 ] && [ "$hdr_ok" = 1 ]; then
    pass "$s  VERSION=$const drives --version/banner/header"
  else
    fail "$s version drift" "const=$const flag=$vflag flag_ok=$flag_ok banner=$ban_ok header=$hdr_ok"
  fi
done

# ── 5. regression: uninstall refuses silent vault deletion ───────────────────
hdr "regression: uninstall --no-export --yes safety gate"
if [ -f ai-memory-uninstall.sh ]; then
  SBOX="$TMP/home"; VAULT="$SBOX/Documents/ai-memory"
  mkdir -p "$VAULT/00-inbox"
  echo "keepme" > "$VAULT/00-inbox/marker.md"
  # Non-interactive with NO usable controlling tty (setsid, where available) so
  # the gate must REFUSE rather than prompt. timeout guards against a regression
  # that blocks on a prompt instead of refusing. No --force-no-export → must NOT
  # delete.
  runner=""
  command -v setsid >/dev/null 2>&1 && runner="setsid"
  out=$(HOME="$SBOX" timeout 20 $runner bash ai-memory-uninstall.sh "$VAULT" --no-export --yes </dev/null 2>&1)
  rc=$?
  [ "$rc" = 124 ] && fail "uninstall blocked on a prompt (should refuse non-interactively)"
  if [ -f "$VAULT/00-inbox/marker.md" ]; then
    pass "vault survived (no silent delete); exit=$rc"
  else
    fail "vault was DELETED without confirm" "$out"
  fi
  if printf '%s' "$out" | grep -qiE 'confirm|force-no-export|refus|abort|DELETE'; then
    pass "refusal/confirm message shown"
  else
    skip "no explicit refusal string matched (vault survival is the hard assertion)"
  fi
else
  skip "ai-memory-uninstall.sh absent"
fi

# ── 6. regression: ingest secret-scrub (locks in the v2.14 promise) ──────────
hdr "regression: ingest secret-scrub"
if [ ! -f ai-memory-ingest.sh ]; then
  skip "ai-memory-ingest.sh absent"
elif [ "$PY_OK" = 0 ]; then
  # ingest is a python script; without a real python3 the import can't run and
  # this would report a spurious secret-leak FAIL. Skip, like the other ingest
  # checks above (§2 --version / §3 consistency), so a false red never lands.
  skip "ai-memory-ingest.sh (no real python3 here)"
else
  mkdir -p "$TMP/ccfake/proj" "$TMP/scrubvault/05-AI-Sessions"
  printf '%s\n' \
    '{"type":"ai-title","aiTitle":"Leak test"}' \
    '{"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"keys: sk-or-v1-0123456789abcdef0123456789abcdef and github_pat_11ABCDE0000aaaaBBBBcc_ZZ9zz9zz9zz9zz9zz9zz9"}}' \
    '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"noted"}]}}' \
    > "$TMP/ccfake/proj/11111111-1111-1111-1111-111111111111.jsonl"
  bash ai-memory-ingest.sh "$TMP/scrubvault" --source claude-code --path "$TMP/ccfake" --yes >/dev/null 2>&1
  scrubfile=$(ls "$TMP/scrubvault/05-AI-Sessions/claude-code/"*.md 2>/dev/null | head -1)
  if [ -n "$scrubfile" ] && grep -q "REDACTED:api-key" "$scrubfile" \
     && grep -q "REDACTED:github-token" "$scrubfile" \
     && ! grep -q "sk-or-v1-0123456789" "$scrubfile" \
     && ! grep -q "github_pat_11ABCDE" "$scrubfile"; then
    pass "pasted api key + fine-grained github PAT redacted on import"
  else
    fail "secret survived into vault (or import failed)" "${scrubfile:-no file written}"
  fi
fi

# ── 6a2. regression: `--local` sweeps local agent stores, skips zip sources (v2.25) ──
# The self-ingest hook fires `ingest --local`: it must discover directory/db-based
# agent stores via their DEFAULT HOME paths (no --source/--path) and must NOT run
# the zip/Downloads exporters. Fake a Claude Code store under an isolated HOME and
# assert --local finds it and writes no zip-source folder.
hdr "regression: ingest --local (OS-general local sweep)"
if [ "$PY_OK" = 0 ]; then
  skip "no real python3 here"
elif [ ! -f ai-memory-ingest.sh ]; then
  skip "ai-memory-ingest.sh absent"
else
  lh="$TMP/localhome"
  mkdir -p "$lh/.claude/projects/proj" "$TMP/localvault/05-AI-Sessions"
  printf '%s\n' \
    '{"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"local sweep hej"}}' \
    '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"noterat"}]}}' \
    > "$lh/.claude/projects/proj/22222222-2222-2222-2222-222222222222.jsonl"
  HOME="$lh" bash ai-memory-ingest.sh "$TMP/localvault" --local --yes > "$TMP/local.out" 2>&1
  if ls "$TMP/localvault/05-AI-Sessions/claude-code/"*.md >/dev/null 2>&1; then
    pass "--local discovered the Claude Code store via its default HOME path"
  else
    fail "--local did not ingest the local claude-code store" "$(tail -3 "$TMP/local.out")"
  fi
  # zip exporters (claude-web/chatgpt) must not be run by --local
  if [ ! -d "$TMP/localvault/05-AI-Sessions/claude-web" ] \
     && grep -qi "LOCAL agent sources" "$TMP/local.out" 2>/dev/null; then
    pass "--local skipped the zip/Downloads exporters"
  else
    fail "--local touched a zip source or missed the local header" "$(grep -iE 'discover|claude-web' "$TMP/local.out" | head -3)"
  fi
fi

# ── 6b. regression: gemini-takeout parses a localized export (v2.15) ─────────
# Locks in the 2026-07-05 live findings: a Swedish "Min aktivitet" register must
# import (structure-keyed, not the English verb), Gemini's response must be
# captured, the gems/settings decoy must not shadow the register, and a re-run
# must not duplicate ("the first run lies").
hdr "regression: gemini-takeout localized export"
if [ "$PY_OK" = 0 ]; then
  skip "no real python3 here"
elif [ ! -f ai-memory-ingest.sh ]; then
  skip "ai-memory-ingest.sh absent"
else
  mkdir -p "$TMP/tovault/05-AI-Sessions"
  python3 - "$TMP/mini-takeout.zip" << 'PYFIX'
import sys, zipfile
entry = ('<div class="outer-cell mdl-cell"><div class="mdl-grid">'
         '<div class="header-cell mdl-cell"><p>Gemini-appar<br></p></div>'
         '<div class="content-cell mdl-cell mdl-cell--6-col mdl-typography--body-1">'
         '%s<br>%s<br>%s</div>'
         '<div class="content-cell mdl-cell mdl-typography--text-right"></div>'
         '<div class="content-cell mdl-cell mdl-typography--caption">'
         '<b>Produkter:</b><br>Gemini-appar</div>'
         '</div></div>')
doc = ("<html><body>"
       + entry % ("Gav instruktionen&nbsp;vilken växelriktare ska jag köpa?",
                  "4 juli 2026 09:15:00 CEST",
                  "<p>Jag rekommenderar <strong>Deye SUN-12K-TEST</strong>.</p>")
       + entry % ("Prompted&nbsp;english day-two entry",
                  "Jul 3, 2026, 9:15:00 AM CEST",
                  "<p>Second day reply.</p>")
       + "</body></html>")
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("Takeout/Gemini/gemini_gems_data.html", "<div></div>")   # decoy
    z.writestr("Takeout/Min aktivitet/Gemini-appar/MinAktivitet.html", doc)
PYFIX
  bash ai-memory-ingest.sh "$TMP/tovault" --source gemini-takeout \
       --path "$TMP/mini-takeout.zip" --yes >/dev/null 2>&1
  gcount=0
  for f in "$TMP/tovault/05-AI-Sessions/gemini-takeout/"*.md; do
    [ -e "$f" ] && gcount=$((gcount+1))
  done
  if [ "$gcount" = 2 ]; then
    pass "2 day-files from 2 days (sv + en entries)"
  else
    fail "expected 2 day-files, got $gcount"
  fi
  if grep -q "Deye SUN-12K-TEST" "$TMP/tovault/05-AI-Sessions/gemini-takeout/"*.md 2>/dev/null; then
    pass "Gemini's response captured (not prompts-only)"
  else
    fail "response text missing from vault file"
  fi
  if grep -q "Gav instruktionen" "$TMP/tovault/05-AI-Sessions/gemini-takeout/"*.md 2>/dev/null; then
    fail "localized action verb leaked into the prompt"
  else
    pass "action verb stripped from prompt"
  fi
  bash ai-memory-ingest.sh "$TMP/tovault" --source gemini-takeout \
       --path "$TMP/mini-takeout.zip" --yes >/dev/null 2>&1
  gcount2=0
  for f in "$TMP/tovault/05-AI-Sessions/gemini-takeout/"*.md; do
    [ -e "$f" ] && gcount2=$((gcount2+1))
  done
  if [ "$gcount2" = 2 ]; then
    pass "re-run idempotent (still 2 files, no duplicates)"
  else
    fail "re-run changed file count: $gcount2"
  fi
fi

# ── 6c. regression: aistudio Drive export (v2.16) ────────────────────────────
# Locks in the 2026-07-05 live findings: extension-less chunkedPrompt threads
# import with the model's responses, isThought reasoning is filtered as noise,
# image chunks become _[attached ...]_ notes, and a re-run must not duplicate.
hdr "regression: aistudio Drive export"
if [ "$PY_OK" = 0 ]; then
  skip "no real python3 here"
elif [ ! -f ai-memory-ingest.sh ]; then
  skip "ai-memory-ingest.sh absent"
else
  mkdir -p "$TMP/asvault/05-AI-Sessions"
  python3 - "$TMP/mini-aistudio.zip" << 'PYFIX'
import sys, json, zipfile
thread = {
    "runSettings": {"model": "models/gemini-test"},
    "systemInstruction": {},
    "chunkedPrompt": {"chunks": [
        {"text": "vilken enhjuling ska jag köpa?", "role": "user",
         "createTime": "2026-06-01T10:00:00.000Z"},
        {"driveImage": {"id": "DRIVEID123"}, "role": "user"},
        {"text": "**Reasoning about unicycles**", "role": "model", "isThought": True},
        {"text": "Jag rekommenderar Begode Falcon-TEST.", "role": "model"},
    ], "pendingInputs": [{"text": "", "role": "user"}]},
}
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("Google AI Studio/applet_access_history.json", "[]")   # decoy (.json)
    z.writestr("Google AI Studio/image(1).png", b"\x89PNG fake")       # decoy (media)
    z.writestr("Google AI Studio/Tråd om enhjulingar åäö",
               json.dumps(thread))
PYFIX
  bash ai-memory-ingest.sh "$TMP/asvault" --source aistudio \
       --path "$TMP/mini-aistudio.zip" --yes >/dev/null 2>&1
  ascount=0
  for f in "$TMP/asvault/05-AI-Sessions/aistudio/"*.md; do
    [ -e "$f" ] && ascount=$((ascount+1))
  done
  if [ "$ascount" = 1 ]; then
    pass "1 thread imported (decoys ignored)"
  else
    fail "expected 1 thread file, got $ascount"
  fi
  if grep -q "Begode Falcon-TEST" "$TMP/asvault/05-AI-Sessions/aistudio/"*.md 2>/dev/null; then
    pass "model response captured"
  else
    fail "response text missing from vault file"
  fi
  if grep -q "Reasoning about unicycles" "$TMP/asvault/05-AI-Sessions/aistudio/"*.md 2>/dev/null; then
    fail "isThought reasoning leaked into the archive"
  else
    pass "isThought reasoning filtered"
  fi
  if grep -q "DRIVEID123" "$TMP/asvault/05-AI-Sessions/aistudio/"*.md 2>/dev/null; then
    pass "image chunk noted as attachment"
  else
    fail "driveImage attachment note missing"
  fi
  bash ai-memory-ingest.sh "$TMP/asvault" --source aistudio \
       --path "$TMP/mini-aistudio.zip" --yes >/dev/null 2>&1
  ascount2=0
  for f in "$TMP/asvault/05-AI-Sessions/aistudio/"*.md; do
    [ -e "$f" ] && ascount2=$((ascount2+1))
  done
  if [ "$ascount2" = 1 ]; then
    pass "re-run idempotent (still 1 file, no duplicates)"
  else
    fail "re-run changed file count: $ascount2"
  fi
fi

# ── 6d. regression: CRLF transcripts normalized (v2.17) ──────────────────────
# Locks in the 2026-07-06 cc-session-sync live finding: Claude Code .jsonl
# written on Windows carries literal \r\n inside message text. Un-normalized,
# every line-anchored regex in clean_text misses (noise placeholder survives),
# and raw \r lands in the vault's markdown.
hdr "regression: CRLF transcript normalized"
if [ "$PY_OK" = 0 ]; then
  skip "no real python3 here"
elif [ ! -f ai-memory-ingest.sh ]; then
  skip "ai-memory-ingest.sh absent"
else
  mkdir -p "$TMP/crlffake/proj" "$TMP/crlfvault/05-AI-Sessions"
  printf '%s\n' \
    '{"type":"ai-title","aiTitle":"CRLF test"}' \
    '{"type":"user","timestamp":"2026-01-02T00:00:00Z","message":{"role":"user","content":"first line\r\nsecond line\r\n\r\n\r\n\r\nafter big gap"}}' \
    '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"reply\r\nThis block is not supported on your current device yet.\r\ndone"}]}}' \
    > "$TMP/crlffake/proj/22222222-2222-2222-2222-222222222222.jsonl"
  bash ai-memory-ingest.sh "$TMP/crlfvault" --source claude-code --path "$TMP/crlffake" --yes >/dev/null 2>&1
  crlffile=$(ls "$TMP/crlfvault/05-AI-Sessions/claude-code/"*.md 2>/dev/null | head -1)
  if [ -z "$crlffile" ]; then
    fail "import produced no vault file"
  else
    if LC_ALL=C grep -q "$(printf '\r')" "$crlffile"; then
      fail "raw \\r survived into the vault markdown" "$crlffile"
    else
      pass "no raw \\r in vault file"
    fi
    if grep -q "not supported on your current device" "$crlffile"; then
      fail "noise placeholder survived CRLF text (line-anchor miss)" "$crlffile"
    else
      pass "noise placeholder stripped despite CRLF endings"
    fi
    if grep -q "after big gap" "$crlffile"; then
      pass "message text intact after normalization"
    else
      fail "message text lost" "$crlffile"
    fi
  fi
fi

# ── 6e. regression: openclaw cron sessions filtered (v2.18) ──────────────────
# Locks in the 2026-07-06 central-node live finding: 719 of 724 openclaw
# sessions were `[cron:...]` agent runs drowning the 5 human conversations.
# Default: cron sessions skipped + reported loudly. --with-cron: vaulted into
# a separate openclaw-cron/ dir, never into openclaw/.
hdr "regression: openclaw cron filter"
if [ "$PY_OK" = 0 ]; then
  skip "no real python3 here"
elif [ ! -f ai-memory-ingest.sh ]; then
  skip "ai-memory-ingest.sh absent"
else
  mkdir -p "$TMP/ocfake/agents/main/sessions" "$TMP/ocvault/05-AI-Sessions"
  printf '%s\n' \
    '{"message":{"role":"user","content":"[cron:aaaa-bbbb daily job] search the market"}}' \
    '{"message":{"role":"assistant","content":"searched"}}' \
    > "$TMP/ocfake/agents/main/sessions/33333333-3333-3333-3333-333333333333.jsonl"
  printf '%s\n' \
    '{"message":{"role":"user","content":"hello, are you alive?"}}' \
    '{"message":{"role":"assistant","content":"very much so"}}' \
    > "$TMP/ocfake/agents/main/sessions/44444444-4444-4444-4444-444444444444.jsonl"
  bash ai-memory-ingest.sh "$TMP/ocvault" --source openclaw --path "$TMP/ocfake" --yes > "$TMP/oc.out" 2>&1
  oc_human=$(ls "$TMP/ocvault/05-AI-Sessions/openclaw/"*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$oc_human" = 1 ] && grep -q "are you alive" "$TMP/ocvault/05-AI-Sessions/openclaw/"*.md; then
    pass "human conversation vaulted, cron session not (default)"
  else
    fail "expected exactly 1 human conversation in openclaw/" "got $oc_human"
  fi
  if [ -d "$TMP/ocvault/05-AI-Sessions/openclaw-cron" ]; then
    fail "openclaw-cron/ created without --with-cron"
  else
    pass "no openclaw-cron/ dir on default run"
  fi
  if grep -q "cron-initiated sessions skipped" "$TMP/oc.out"; then
    pass "skip reported loudly (never a silent zero)"
  else
    fail "cron skip happened silently" "$TMP/oc.out"
  fi
  bash ai-memory-ingest.sh "$TMP/ocvault" --source openclaw --path "$TMP/ocfake" --with-cron --yes >/dev/null 2>&1
  oc_cron=$(ls "$TMP/ocvault/05-AI-Sessions/openclaw-cron/"*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$oc_cron" = 1 ]; then
    pass "--with-cron vaults cron session into openclaw-cron/"
  else
    fail "expected exactly 1 cron conversation in openclaw-cron/" "got $oc_cron"
  fi
fi

# ── 6f. regression: hermes titles — db title, retitle-in-place, --ai-titles (v2.19)
# Locks in the 2026-07-07 live finding: vault listings showed raw first-prompt
# headings ("Uppgift, svara direkt utan att...") because parse_hermes never read
# sessions.title. Also locks the two structural rules: a heading upgrade rewrites
# the SAME file (a rename would duplicate through the add-only sync), and a
# heading once upgraded is never downgraded back to the raw-prompt fallback.
hdr "regression: hermes titles (v2.19)"
if [ "$PY_OK" = 0 ]; then
  skip "no real python3 here"
elif [ ! -f ai-memory-ingest.sh ]; then
  skip "ai-memory-ingest.sh absent"
else
  mkdir -p "$TMP/hvault/05-AI-Sessions"
  cat > "$TMP/mkhermdb.py" <<'PYEOF'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE sessions (id TEXT PRIMARY KEY, model TEXT,"
            " started_at REAL, title TEXT)")
con.execute("CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT,"
            " session_id TEXT, role TEXT, content TEXT, timestamp REAL)")
con.executemany("INSERT INTO sessions VALUES (?,?,?,?)", [
    ("hermtest1", "qwen", 1751700000.0, "Riktig titel fran hermes"),
    ("hermtest2", "qwen", 1751700100.0, None),
])
con.executemany("INSERT INTO messages (session_id, role, content, timestamp)"
                " VALUES (?,?,?,?)", [
    ("hermtest1", "user", "hej dar", 1.0),
    ("hermtest1", "assistant", "hej sjalv", 2.0),
    ("hermtest2", "user",
     "Uppgift, svara direkt utan verktyg: Skriv en dikt om enhjulingar", 3.0),
    ("hermtest2", "assistant", "En dikt kommer har", 4.0),
])
con.commit(); con.close()
PYEOF
  python3 "$TMP/mkhermdb.py" "$TMP/state.db"
  bash ai-memory-ingest.sh "$TMP/hvault" --source hermes --path "$TMP/state.db" --yes >/dev/null 2>&1
  if grep -q "^# Riktig titel fran hermes" "$TMP/hvault/05-AI-Sessions/hermes/"*-hermtest1.md 2>/dev/null; then
    pass "session's own db title used as heading"
  else
    fail "db title not used as heading"
  fi
  if grep -q "^# Uppgift, svara direkt" "$TMP/hvault/05-AI-Sessions/hermes/"*-hermtest2.md 2>/dev/null; then
    pass "untitled session falls back to raw first prompt"
  else
    fail "raw-prompt fallback heading missing"
  fi
  # hermes titles the session AFTER first import → heading updates, SAME file
  f2_before=$(ls "$TMP/hvault/05-AI-Sessions/hermes/"*-hermtest2.md 2>/dev/null)
  python3 -c "import sqlite3; c = sqlite3.connect('$TMP/state.db'); c.execute(\"UPDATE sessions SET title='Dikt om enhjulingar' WHERE id='hermtest2'\"); c.commit()"
  bash ai-memory-ingest.sh "$TMP/hvault" --source hermes --path "$TMP/state.db" --yes > "$TMP/h2.out" 2>&1
  f2_after=$(ls "$TMP/hvault/05-AI-Sessions/hermes/"*-hermtest2.md 2>/dev/null)
  if grep -q "^# Dikt om enhjulingar" "$f2_after" 2>/dev/null && [ "$f2_before" = "$f2_after" ]; then
    pass "late db title retitles IN PLACE (same filename)"
  else
    fail "retitle-in-place failed" "before=$f2_before after=$f2_after"
  fi
  if grep -q "retitle:" "$TMP/h2.out"; then
    pass "retitle reported loudly"
  else
    fail "retitle happened silently" "$TMP/h2.out"
  fi
  bash ai-memory-ingest.sh "$TMP/hvault" --source hermes --path "$TMP/state.db" --yes > "$TMP/h3.out" 2>&1
  if grep -q "Nothing new" "$TMP/h3.out"; then
    pass "third run is a no-op (idempotent)"
  else
    fail "re-run not idempotent" "$(tail -3 "$TMP/h3.out")"
  fi

  # --ai-titles: a local stub endpoint plays the model — no network leaves 127.0.0.1
  python3 -c "import sqlite3; c = sqlite3.connect('$TMP/state.db'); c.execute(\"INSERT INTO sessions VALUES ('hermtest3','qwen',1751700200.0,NULL)\"); c.execute(\"INSERT INTO messages (session_id, role, content, timestamp) VALUES ('hermtest3','user','Uppgift: svara med en halsning',5.0)\"); c.commit()"
  cat > "$TMP/stub.py" <<'PYEOF'
import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        body = json.dumps({"choices": [{"message": {"content":
            "<think>resonemang</think>\n\"Stubbtitel fran modellen\"."}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
PYEOF
  python3 "$TMP/stub.py" > "$TMP/stub.port" 2>/dev/null &
  STUB_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/stub.port" ] && break; sleep 0.3; done
  port=$(cat "$TMP/stub.port" 2>/dev/null)
  if [ -z "$port" ]; then
    skip "stub model server did not start"
  else
    mkdir -p "$TMP/hvault2/05-AI-Sessions"
    AI_MEMORY_MODEL_URL="http://127.0.0.1:$port/v1" AI_MEMORY_MODEL=stub \
      bash ai-memory-ingest.sh "$TMP/hvault2" --source hermes --path "$TMP/state.db" --ai-titles --yes >/dev/null 2>&1
    # think-block, quotes and trailing period must all be stripped
    if grep -q "^# Stubbtitel fran modellen$" "$TMP/hvault2/05-AI-Sessions/hermes/"*-hermtest3.md 2>/dev/null; then
      pass "--ai-titles: untitled session got a model-written heading"
    else
      fail "--ai-titles heading missing/unclean" "$(head -1 "$TMP/hvault2/05-AI-Sessions/hermes/"*-hermtest3.md 2>/dev/null)"
    fi
    AI_MEMORY_MODEL_URL="http://127.0.0.1:$port/v1" AI_MEMORY_MODEL=stub \
      bash ai-memory-ingest.sh "$TMP/hvault2" --source hermes --path "$TMP/state.db" --ai-titles --yes > "$TMP/h5.out" 2>&1
    if grep -q "Nothing new" "$TMP/h5.out"; then
      pass "--ai-titles re-run is a no-op (no churn)"
    else
      fail "--ai-titles re-run rewrote files" "$(tail -3 "$TMP/h5.out")"
    fi
    bash ai-memory-ingest.sh "$TMP/hvault2" --source hermes --path "$TMP/state.db" --yes > "$TMP/h6.out" 2>&1
    if grep -q "Nothing new" "$TMP/h6.out"; then
      pass "plain re-run never downgrades an upgraded heading"
    else
      fail "plain re-run downgraded the AI heading" "$(tail -3 "$TMP/h6.out")"
    fi
  fi
  kill "$STUB_PID" 2>/dev/null
  # empty/all-<think> replies must be LOUD (never a silent zero) + fall back
  # per conversation; a 3-streak disables titling for the rest of the run
  python3 -c "import sqlite3; c = sqlite3.connect('$TMP/state.db'); c.execute(\"INSERT INTO sessions VALUES ('hermtest4','qwen',1751700300.0,NULL)\"); c.execute(\"INSERT INTO messages (session_id, role, content, timestamp) VALUES ('hermtest4','user','Fraga fyra',6.0)\"); c.execute(\"INSERT INTO sessions VALUES ('hermtest5','qwen',1751700400.0,NULL)\"); c.execute(\"INSERT INTO messages (session_id, role, content, timestamp) VALUES ('hermtest5','user','Fraga fem',7.0)\"); c.commit()"
  cat > "$TMP/stub2.py" <<'PYEOF'
import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        body = json.dumps({"choices": [{"message": {"content":
            "<think>bara resonemang som aldrig avslutas"}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
PYEOF
  python3 "$TMP/stub2.py" > "$TMP/stub2.port" 2>/dev/null &
  STUB_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/stub2.port" ] && break; sleep 0.3; done
  port2=$(cat "$TMP/stub2.port" 2>/dev/null)
  if [ -z "$port2" ]; then
    skip "empty-reply stub did not start"
  else
    mkdir -p "$TMP/hvault4/05-AI-Sessions"
    AI_MEMORY_MODEL_URL="http://127.0.0.1:$port2/v1" AI_MEMORY_MODEL=stub \
      bash ai-memory-ingest.sh "$TMP/hvault4" --source hermes --path "$TMP/state.db" --ai-titles --yes > "$TMP/h8.out" 2>&1
    if grep -q "empty reply for this conversation" "$TMP/h8.out" \
       && grep -q "^# Uppgift: svara med en halsning" "$TMP/hvault4/05-AI-Sessions/hermes/"*-hermtest3.md 2>/dev/null; then
      pass "empty model reply is loud + falls back for that conversation"
    else
      fail "empty model reply was silent or heading wrong" "$(tail -3 "$TMP/h8.out")"
    fi
    if grep -q "3 consecutive empty replies" "$TMP/h8.out"; then
      pass "3-streak of empty replies disables titling loudly"
    else
      fail "3-streak did not trip the circuit breaker" "$(tail -3 "$TMP/h8.out")"
    fi
  fi
  kill "$STUB_PID" 2>/dev/null
  # blank-then-good: ollama's blank-first-completion-after-load pattern —
  # the single retry must rescue the title with no warn
  cat > "$TMP/stub3.py" <<'PYEOF'
import http.server, json
CALLS = {"n": 0}
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        CALLS["n"] += 1
        content = "" if CALLS["n"] == 1 else "Raddad av omforsoket"
        body = json.dumps({"choices": [{"message": {"content": content}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
PYEOF
  python3 "$TMP/stub3.py" > "$TMP/stub3.port" 2>/dev/null &
  STUB_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/stub3.port" ] && break; sleep 0.3; done
  port3=$(cat "$TMP/stub3.port" 2>/dev/null)
  if [ -z "$port3" ]; then
    skip "blank-then-good stub did not start"
  else
    mkdir -p "$TMP/hvault5/05-AI-Sessions"
    AI_MEMORY_MODEL_URL="http://127.0.0.1:$port3/v1" AI_MEMORY_MODEL=stub \
      bash ai-memory-ingest.sh "$TMP/hvault5" --source hermes --path "$TMP/state.db" --ai-titles --yes > "$TMP/h9.out" 2>&1
    if grep -q "^# Raddad av omforsoket" "$TMP/hvault5/05-AI-Sessions/hermes/"*.md 2>/dev/null \
       && ! grep -q "empty reply" "$TMP/h9.out"; then
      pass "single blank reply is retried and rescued (no warn)"
    else
      fail "retry did not rescue a single blank reply" "$(tail -3 "$TMP/h9.out")"
    fi
  fi
  kill "$STUB_PID" 2>/dev/null
  # reasoning-model equality: OpenAI endpoint blanks, native /api/generate
  # answers (the live qwen3.6:35b-on-ollama shape) → title must come through
  cat > "$TMP/stub4.py" <<'PYEOF'
import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path.endswith("/chat/completions"):
            body = json.dumps({"choices": [{"message": {"content": ""}}]}).encode()
        else:
            body = json.dumps({"response":
                "<think>resonemang</think>\nTitel via nativa vagen."}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
PYEOF
  python3 "$TMP/stub4.py" > "$TMP/stub4.port" 2>/dev/null &
  STUB_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/stub4.port" ] && break; sleep 0.3; done
  port4=$(cat "$TMP/stub4.port" 2>/dev/null)
  if [ -z "$port4" ]; then
    skip "reasoning-shape stub did not start"
  else
    mkdir -p "$TMP/hvault6/05-AI-Sessions"
    AI_MEMORY_MODEL_URL="http://127.0.0.1:$port4/v1" AI_MEMORY_MODEL=stub \
      bash ai-memory-ingest.sh "$TMP/hvault6" --source hermes --path "$TMP/state.db" --ai-titles --yes > "$TMP/h10.out" 2>&1
    if grep -q "^# Titel via nativa vagen$" "$TMP/hvault6/05-AI-Sessions/hermes/"*-hermtest3.md 2>/dev/null \
       && ! grep -q "empty reply" "$TMP/h10.out"; then
      pass "blank OpenAI reply is rescued via the native generate API (model equality)"
    else
      fail "native-API rescue for reasoning models failed" "$(tail -3 "$TMP/h10.out")"
    fi
  fi
  kill "$STUB_PID" 2>/dev/null
  # graceful degrade: dead endpoint → warn, fall back, import still succeeds
  mkdir -p "$TMP/hvault3/05-AI-Sessions"
  if AI_MEMORY_MODEL_URL="http://127.0.0.1:1/v1" AI_MEMORY_MODEL=stub \
      bash ai-memory-ingest.sh "$TMP/hvault3" --source hermes --path "$TMP/state.db" --ai-titles --yes > "$TMP/h7.out" 2>&1; then
    if grep -q "fallback titles" "$TMP/h7.out" \
       && grep -q "^# Uppgift: svara med en halsning" "$TMP/hvault3/05-AI-Sessions/hermes/"*-hermtest3.md 2>/dev/null; then
      pass "--ai-titles degrades gracefully when the model is unreachable"
    else
      fail "degrade path silent or heading wrong" "$(tail -3 "$TMP/h7.out")"
    fi
  else
    fail "--ai-titles with dead endpoint broke the import (non-zero exit)"
  fi
fi

# ── 6g. regression: configure v5.0 — remote ollama, keep-check, fallback ─────
# Locks in the 2026-07-06 live wound: a WSL machine wired to a LAN ollama ran
# configure and had its WORKING model block silently rewritten to localhost.
# Also: the fallback chain is now WRITTEN (was only printed), ai-config.json
# carries the real base_url, and a non-TTY run must never exec ingest.
hdr "regression: configure v5.0 (remote/keep/fallback)"
if [ "$PY_OK" = 0 ]; then
  skip "no real python3 here"
elif [ ! -f ai-memory-configure.sh ]; then
  skip "ai-memory-configure.sh absent"
elif ! command -v curl >/dev/null 2>&1; then
  skip "curl not installed"
else
  cat > "$TMP/stub-ollama.py" <<'PYEOF'
import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def _send(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        if self.path.endswith("/models"):
            self._send({"object": "list", "data": [
                {"id": "nomic-embed-text:latest"}, {"id": "testmodell:7b"}]})
        else:
            self.send_response(404); self.end_headers()
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path.endswith("/api/show"):
            self._send({"model_info": {"qwen3.context_length": 40960}})
        else:
            self.send_response(404); self.end_headers()
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
PYEOF
  python3 "$TMP/stub-ollama.py" > "$TMP/stub-ollama.port" 2>/dev/null &
  STUB_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/stub-ollama.port" ] && break; sleep 0.3; done
  oport=$(cat "$TMP/stub-ollama.port" 2>/dev/null)
  if [ -z "$oport" ]; then
    skip "stub ollama server did not start"
  else
    mkdir -p "$TMP/cfgvault/entities" "$TMP/cfgvault/05-AI-Sessions" "$TMP/cfghome"
    CFGYAML="$TMP/hh1/config.yaml"
    # t1: --remote-ollama writes the probed endpoint + a non-embedding model
    HOME="$TMP/cfghome" HERMES_HOME="$TMP/hh1" \
      bash ai-memory-configure.sh "$TMP/cfgvault" --yes --remote-ollama=127.0.0.1:$oport > "$TMP/cfg1.out" 2>&1
    if grep -qF "base_url: \"http://127.0.0.1:$oport/v1\"" "$CFGYAML" 2>/dev/null \
       && grep -qF 'default: "testmodell:7b"' "$CFGYAML" \
       && grep -q "ollama_num_ctx: 64000" "$CFGYAML"; then
      pass "--remote-ollama: probed endpoint + non-embed model + floor ctx written"
    else
      fail "--remote-ollama config wrong" "$(grep -E 'base_url|default|num_ctx' "$CFGYAML" 2>/dev/null | head -4)"
    fi
    if grep -qF "\"base_url\": \"http://127.0.0.1:$oport/v1\"" "$TMP/cfgvault/.mcp/ai-config.json" 2>/dev/null; then
      pass "ai-config.json carries the real base_url"
    else
      fail "ai-config.json base_url wrong" "$(cat "$TMP/cfgvault/.mcp/ai-config.json" 2>/dev/null | head -3)"
    fi
    # v5.2: SOUL handover carries the search-persistence recipe (target-picture
    # round: the recall floor is search strategy, not model size)
    # persistence now lives in the tool ("never stops at the first empty word")
    # + the grep fallback ("do not give up after one empty result"); either way
    # the handover must not tell the agent to quit on the first miss, and must
    # still name INDEX.md.
    if grep -qi "empty" "$TMP/hh1/SOUL.md" 2>/dev/null \
       && grep -q "INDEX.md" "$TMP/hh1/SOUL.md" 2>/dev/null; then
      pass "SOUL.md carries search persistence (don't-quit-on-first-empty + INDEX)"
    else
      fail "SOUL.md missing the search-persistence guidance"
    fi
    # v5.3: SOUL steers to filesystem tools, away from session_search/memory tool
    if grep -q "NOT use session_search" "$TMP/hh1/SOUL.md" 2>/dev/null \
       && grep -qi "markdown FILES" "$TMP/hh1/SOUL.md" 2>/dev/null; then
      pass "SOUL.md steers to filesystem tools, away from session_search/memory tool"
    else
      fail "SOUL.md missing the tool-steering guidance" "$(grep -c session_search "$TMP/hh1/SOUL.md" 2>/dev/null)"
    fi
    # v5.4: SOUL points at the memory-search tool, and configure installs it
    if grep -q "ai-memory-search.sh" "$TMP/hh1/SOUL.md" 2>/dev/null; then
      pass "SOUL.md points the agent at ai-memory-search.sh"
    else
      fail "SOUL.md does not reference the memory-search tool"
    fi
    if [ -x "$TMP/cfgvault/.tools/ai-memory-search.sh" ]; then
      pass "configure installed ai-memory-search.sh into .tools/"
    else
      fail "configure did not install the memory-search tool"
    fi
    # v5.9: configure must also install ai-memory-ingest.sh into .tools/ — the
    # self-ingest hook runs that copy (a stale one without --local exits 2 live).
    if [ -x "$TMP/cfgvault/.tools/ai-memory-ingest.sh" ] \
       && grep -q -- "--local" "$TMP/cfgvault/.tools/ai-memory-ingest.sh" 2>/dev/null; then
      pass "configure installed ai-memory-ingest.sh (with --local) into .tools/"
    else
      fail "configure did not install a --local-capable ingest tool into .tools/"
    fi
    # v5.13: the launchers need their python engine NEXT TO the .tools copies —
    # configure must install lib/ too, and the installed ingest must actually run.
    if [ -f "$TMP/cfgvault/.tools/lib/aimem_common.py" ] \
       && [ -f "$TMP/cfgvault/.tools/lib/aimem_ingest.py" ] \
       && [ -f "$TMP/cfgvault/.tools/lib/aimem_search.py" ] \
       && HOME="$TMP/cfghome" bash "$TMP/cfgvault/.tools/ai-memory-ingest.sh" --version >/dev/null 2>&1; then
      pass "configure installed lib/ into .tools/lib (installed ingest launcher runs)"
    else
      fail "configure did not install a working .tools/lib python engine"
    fi
    # v5.5: configure registers the pre_llm_call hook + flips hooks_auto_accept
    if grep -q "pre_llm_call:" "$TMP/hh1/config.yaml" 2>/dev/null \
       && grep -q "ai-memory-search.sh --hook" "$TMP/hh1/config.yaml" 2>/dev/null \
       && grep -q "hooks_auto_accept: true" "$TMP/hh1/config.yaml" 2>/dev/null; then
      pass "configure registers the memory hook (pre_llm_call + auto_accept)"
    else
      fail "configure did not register the memory hook" "$(grep -nE 'hooks|auto_accept' "$TMP/hh1/config.yaml" 2>/dev/null | head -4)"
    fi
    # v5.6/v5.7: configure registers the self-ingest hooks (on_session_end +
    # on_session_start → ingest), and both must survive alongside pre_llm_call.
    if grep -q "on_session_end:" "$TMP/hh1/config.yaml" 2>/dev/null \
       && grep -q "on_session_start:" "$TMP/hh1/config.yaml" 2>/dev/null \
       && grep -q "ai-memory-ingest.sh .* --local" "$TMP/hh1/config.yaml" 2>/dev/null \
       && grep -q "pre_llm_call:" "$TMP/hh1/config.yaml" 2>/dev/null; then
      pass "configure registers the self-ingest hooks (on_session_end + on_session_start → ingest --local), pre_llm_call intact"
    else
      fail "configure did not register both self-ingest hooks" "$(grep -nE 'hooks|on_session|ingest|pre_llm' "$TMP/hh1/config.yaml" 2>/dev/null | head -8)"
    fi
    # v5.10: configure ships the MoA presets (balanced + lokal) for /moa
    if grep -q "balanced:" "$TMP/hh1/config.yaml" 2>/dev/null \
       && grep -q "lokal:" "$TMP/hh1/config.yaml" 2>/dev/null \
       && grep -q "nex-agi/nex-n2-mini" "$TMP/hh1/config.yaml" 2>/dev/null \
       && grep -q "default_preset: balanced" "$TMP/hh1/config.yaml" 2>/dev/null; then
      pass "configure ships the MoA presets (balanced + lokal, default_preset=balanced)"
    else
      fail "configure did not install the MoA presets" "$(grep -nE 'moa:|preset|balanced|lokal' "$TMP/hh1/config.yaml" 2>/dev/null | head -8)"
    fi
    # t2: rerun WITHOUT the flag — the working (stub-answering) block is KEPT
    HOME="$TMP/cfghome" HERMES_HOME="$TMP/hh1" \
      bash ai-memory-configure.sh "$TMP/cfgvault" --yes > "$TMP/cfg2.out" 2>&1
    if grep -qF 'default: "testmodell:7b"' "$CFGYAML" \
       && grep -qF "base_url: \"http://127.0.0.1:$oport/v1\"" "$CFGYAML" \
       && grep -qi "kept as-is" "$TMP/cfg2.out"; then
      pass "keep-check: a working model block survives a --yes rerun"
    else
      fail "working block was clobbered or keep not reported" "$(grep -E 'base_url|default' "$CFGYAML" | head -3)"
    fi
    # v5.9: hook registration is idempotent — a --yes rerun must not DUPLICATE a
    # hook key. Regression for the 2026-07-10 live bug: Hermes re-dumps config.yaml
    # with the long pre_llm_call command FOLDED across two lines, so the old
    # `cmd in text` check missed it and re-added a second pre_llm_call.
    npre=$(grep -c "pre_llm_call:" "$CFGYAML" 2>/dev/null)
    nend=$(grep -c "on_session_end:" "$CFGYAML" 2>/dev/null)
    if [ "$npre" = 1 ] && [ "$nend" = 1 ]; then
      pass "hook re-registration is idempotent (no duplicate keys on rerun)"
    else
      fail "rerun duplicated a hook key" "pre_llm_call=$npre on_session_end=$nend"
    fi
    # fold the search command across two lines (as Hermes' YAML dumper does), then
    # rerun configure — the fold-normalized check must still see it as present.
    python3 - "$CFGYAML" << 'PYFOLD'
import sys, re
p = sys.argv[1]; t = open(p).read()
t = re.sub(r"(- command: bash \S+ai-memory-search\.sh) (--hook)", r"\1 \n        \2", t)
open(p, "w").write(t)
PYFOLD
    HOME="$TMP/cfghome" HERMES_HOME="$TMP/hh1" \
      bash ai-memory-configure.sh "$TMP/cfgvault" --yes > "$TMP/cfg2b.out" 2>&1
    if [ "$(grep -c 'pre_llm_call:' "$CFGYAML" 2>/dev/null)" = 1 ]; then
      pass "folded pre_llm_call command is recognized as present (no duplicate)"
    else
      fail "folded command duplicated the pre_llm_call key" "$(grep -c 'pre_llm_call:' "$CFGYAML")"
    fi
    # t3: --yes NEVER replaces an existing block — even with a DEAD endpoint
    # (v5.1: the v5.0 probe rule clobbered a live moa block on the central)
    mkdir -p "$TMP/hh3"
    printf 'model:\n  default: gammal:7b\n  provider: custom\n  base_url: "http://127.0.0.1:1/v1"\n  context_length: 64000\n' > "$TMP/hh3/config.yaml"
    HOME="$TMP/cfghome" HERMES_HOME="$TMP/hh3" \
      bash ai-memory-configure.sh "$TMP/cfgvault" --yes > "$TMP/cfg3.out" 2>&1
    if grep -q "127.0.0.1:1/v1" "$TMP/hh3/config.yaml" \
       && grep -q "never replaces an existing model block" "$TMP/cfg3.out"; then
      pass "--yes keeps even a dead-endpoint block (replace needs intent)"
    else
      fail "--yes replaced an existing block or kept silently" "$(grep base_url "$TMP/hh3/config.yaml")"
    fi
    # t3b: an explicit --remote-ollama flag IS the intent — replaces (with backup)
    HOME="$TMP/cfghome" HERMES_HOME="$TMP/hh3" \
      bash ai-memory-configure.sh "$TMP/cfgvault" --yes --remote-ollama=127.0.0.1:$oport > "$TMP/cfg3b.out" 2>&1
    if grep -qF "base_url: \"http://127.0.0.1:$oport/v1\"" "$TMP/hh3/config.yaml" \
       && ls "$TMP/hh3/config.yaml.bak."* >/dev/null 2>&1; then
      pass "--remote-ollama replaces the block (explicit intent), original backed up"
    else
      fail "--remote-ollama did not replace / no backup" "$(grep base_url "$TMP/hh3/config.yaml")"
    fi
    # t3c: a non-probeable provider block (moa, empty base_url) survives --yes
    mkdir -p "$TMP/hh3c"
    printf "model:\n  default: default\n  provider: moa\n  base_url: ''\n  ollama_num_ctx: 128000\n  max_tokens: 32000\n" > "$TMP/hh3c/config.yaml"
    HOME="$TMP/cfghome" HERMES_HOME="$TMP/hh3c" \
      bash ai-memory-configure.sh "$TMP/cfgvault" --yes > "$TMP/cfg3c.out" 2>&1
    if grep -q "provider: moa" "$TMP/hh3c/config.yaml" \
       && grep -q "max_tokens: 32000" "$TMP/hh3c/config.yaml"; then
      pass "moa-provider block (no base_url) survives --yes untouched"
    else
      fail "moa block was clobbered" "$(head -6 "$TMP/hh3c/config.yaml")"
    fi
    # t4: with an OpenRouter key the fallback chain is WRITTEN — exactly once
    mkdir -p "$TMP/hh4"
    printf 'OPENROUTER_API_KEY=dummy-testnyckel\n' > "$TMP/hh4/.env"; chmod 600 "$TMP/hh4/.env"
    HOME="$TMP/cfghome" HERMES_HOME="$TMP/hh4" \
      bash ai-memory-configure.sh "$TMP/cfgvault" --yes --remote-ollama=127.0.0.1:$oport > "$TMP/cfg4.out" 2>&1
    HOME="$TMP/cfghome" HERMES_HOME="$TMP/hh4" \
      bash ai-memory-configure.sh "$TMP/cfgvault" --yes > "$TMP/cfg4b.out" 2>&1
    fb_count=$(grep -c "^fallback_providers:" "$TMP/hh4/config.yaml" 2>/dev/null)
    if [ "$fb_count" = 1 ] && grep -q "provider: openrouter" "$TMP/hh4/config.yaml"; then
      pass "fallback chain written once, idempotent on rerun"
    else
      fail "fallback chain missing or duplicated" "count=$fb_count"
    fi
    # t5: non-TTY run without --yes must NOT exec ingest
    mkdir -p "$TMP/cfgvault/.tools" "$TMP/hh5"
    printf '#!/usr/bin/env bash\necho INGEST-EXECD\n' > "$TMP/cfgvault/.tools/ai-memory-ingest.sh"
    HOME="$TMP/cfghome" HERMES_HOME="$TMP/hh5" \
      bash ai-memory-configure.sh "$TMP/cfgvault" < /dev/null > "$TMP/cfg5.out" 2>&1
    cfg5_rc=$?
    if [ "$cfg5_rc" = 0 ] && ! grep -q "INGEST-EXECD" "$TMP/cfg5.out"; then
      pass "non-TTY run never execs ingest (and exits 0)"
    else
      fail "non-TTY run exec'd ingest or failed" "rc=$cfg5_rc $(tail -2 "$TMP/cfg5.out")"
    fi
  fi
  kill "$STUB_PID" 2>/dev/null
fi

# ── 6h. regression: ai-memory-search ranks the right file (v1.0) ─────────────
# The deterministic memory-search tool must surface the file that covers the
# MOST distinct query terms as the #1 hit — the property that lets a weak model
# answer in one tool call (§4.5). Fixture: a target file rich in the query's
# terms + decoys that share only one, incl. an åäö filename (python3 path-safe).
hdr "regression: memory-search ranking (v1.0)"
if [ "$PY_OK" = 0 ]; then
  skip "no real python3 here"
elif [ ! -f ai-memory-search.sh ]; then
  skip "ai-memory-search.sh absent"
else
  SV="$TMP/searchvault/05-AI-Sessions/aistudio"
  mkdir -p "$SV" "$TMP/searchvault/05-AI-Sessions/decoys"
  # target: covers enhjuling + EUC + Begode + Falcon + december + 2025 + 1,880 + USD
  cat > "$SV/2026-03-11-köp-av-enhjuling-åäö.md" <<'MD'
# Köpbeslut enhjuling
Du beställde en Begode Falcon Pro (en elektrisk enhjuling, EUC) i december 2025.
Priset var 1,880 USD. Levereras från Kina.
MD
  # decoy 1: only "EUC" (shares one term)
  printf '# Allmänt om EUC\nEUC är kul att åka.\n' > "$TMP/searchvault/05-AI-Sessions/decoys/euc-only.md"
  # decoy 2: only "december 2025" (a date, shares one/two)
  printf '# Kalender\nMöte i december 2025 om annat.\n' > "$TMP/searchvault/05-AI-Sessions/decoys/kalender.md"
  out=$(bash ai-memory-search.sh "$TMP/searchvault" "vilken elektrisk enhjuling EUC beställde jag i december 2025 pris USD" --top 3 2>&1)
  top=$(printf '%s\n' "$out" | grep -E '^1\. ' | head -1)
  case "$top" in
    *"köp-av-enhjuling"*) pass "target file ranked #1 (most distinct terms)" ;;
    *) fail "wrong #1 hit" "$top" ;;
  esac
  if printf '%s\n' "$out" | grep -q "1,880 USD"; then
    pass "answer-bearing line surfaced in the snippet"
  else
    fail "snippet did not surface the answer line" "$out"
  fi
  # no-match query must say so clearly, never a silent empty
  out2=$(bash ai-memory-search.sh "$TMP/searchvault" "kärnkraftverk fusion plasma" 2>&1)
  if printf '%s\n' "$out2" | grep -qi "no file"; then
    pass "no-match query reports clearly (never a silent empty)"
  else
    fail "no-match query was silent/unclear" "$out2"
  fi
fi

# ── 6i. regression: ai-memory-search --hook (pre_llm_call injection) (v1.1) ──
# The model-agnostic path: a hermes pre_llm_call hook reads the turn on stdin
# and INJECTS vault hits into the user message so even a model that never calls
# a tool gets memory recall. Must: inject {"context":...} on a STRONG hit, stay
# SILENT on weak/chit-chat and on non-user turns, and — the load-bearing fix —
# read the payload on STDIN even though the python source rides on fd 3.
hdr "regression: memory-search --hook injection (v1.1)"
if [ "$PY_OK" = 0 ]; then
  skip "no real python3 here"
elif [ ! -f ai-memory-search.sh ]; then
  skip "ai-memory-search.sh absent"
else
  HV="$TMP/hookvault/05-AI-Sessions/aistudio"
  mkdir -p "$HV"
  # price on its OWN line, written "USD" — the query below says "dollar", so the
  # term-ranked snippet skips it and only the VALUE-line rule can surface it.
  printf '# Kop\nDu bestallde en Begode Falcon Pro (elektrisk enhjuling, EUC) i december 2025.\nEn massa ovidkommande text pa den har raden helt utan siffror.\nPris: 1,880 USD\n' > "$HV/kop.md"
  # strong hit → injects context; the value-line rule pulls in the price even
  # though the query said "dollar" and the file wrote "USD".
  strong=$(printf '%s' '{"hook_event_name":"pre_llm_call","extra":{"turn_type":"user","user_message":"vilken elektrisk enhjuling EUC bestallde jag i december 2025 och vad kostade den i dollar"}}' | bash ai-memory-search.sh --hook "$TMP/hookvault" 2>/dev/null)
  if printf '%s' "$strong" | grep -q '"context"' && printf '%s' "$strong" | grep -q "1,880 USD"; then
    pass "strong hit injects {context}, incl. the price via the value-line rule (query 'dollar' vs file 'USD')"
  else
    fail "hook did not inject the answer/price on a strong hit" "$strong"
  fi
  # chit-chat → silent (no injection)
  weak=$(printf '%s' '{"extra":{"turn_type":"user","user_message":"hej"}}' | bash ai-memory-search.sh --hook "$TMP/hookvault" 2>/dev/null)
  if [ -z "$weak" ]; then pass "chit-chat injects nothing (no turn inflation)"; else fail "hook injected on chit-chat" "$weak"; fi
  # non-user (tool) turn → silent even with strong content
  toolturn=$(printf '%s' '{"extra":{"turn_type":"tool","user_message":"Begode Falcon enhjuling EUC december 2025 USD"}}' | bash ai-memory-search.sh --hook "$TMP/hookvault" 2>/dev/null)
  if [ -z "$toolturn" ]; then pass "non-user turn injects nothing"; else fail "hook injected on a tool turn" "$toolturn"; fi
  # conversation_history fallback (no user_message key) → still finds the message
  hist=$(printf '%s' '{"extra":{"turn_type":"user","conversation_history":[{"role":"assistant","content":"hi"},{"role":"user","content":"vilken enhjuling EUC Begode december 2025 USD"}]}}' | bash ai-memory-search.sh --hook "$TMP/hookvault" 2>/dev/null)
  if printf '%s' "$hist" | grep -q '"context"'; then pass "conversation_history fallback extracts the last user turn"; else fail "hook missed conversation_history" "$hist"; fi
  # malformed/empty stdin → silent, exit 0 (never breaks the turn)
  if printf '' | bash ai-memory-search.sh --hook "$TMP/hookvault" >/dev/null 2>&1; then
    pass "empty payload is a silent no-op (exit 0)"
  else
    fail "empty payload broke the hook (non-zero exit)"
  fi
  # v1.4: TIME/META questions ("what did we talk about recently") inject a dated
  # recent-conversations list from INDEX.md instead of a topic search.
  {
    printf '# Memory Index\n### claude-code\n'
    printf -- '- `2099-01-02` — Built the auto-inject hook  ·  `05-AI-Sessions/claude-code/a.md`\n'
    printf -- '- `2099-01-01` — Fixed the dashboard  ·  `05-AI-Sessions/claude-code/b.md`\n'
  } > "$TMP/hookvault/05-AI-Sessions/INDEX.md"
  meta=$(printf '%s' '{"extra":{"turn_type":"user","user_message":"vad pratade vi om senaste dagarna"}}' | bash ai-memory-search.sh --hook "$TMP/hookvault" 2>/dev/null)
  if printf '%s' "$meta" | grep -q '"context"' && printf '%s' "$meta" | grep -q "Built the auto-inject hook"; then
    pass "time/meta question injects recent conversations from INDEX (the vague-recall gap)"
  else
    fail "meta question did not inject recent conversations" "$meta"
  fi
fi

# ── 6j. regression: ingest data-safety round (v2.27) ─────────────────────────
# Locks in the v2.27 fixes: (a) two same-day codex sessions no longer collide
# on a truncated 12-char id, and a ≤v2.26 legacy file (truncated id) is ADOPTED
# in place, never duplicated; (b) notes are GENERATED artifacts (v3.1) — a
# grown conversation is regenerated in place even if the vault file was
# touched by hand (the v2.27 never-overwrite guard false-flagged whole vaults
# on any cleaning change and silently froze them — live incident 2026-07-12);
# (c) a secret pasted into a conversation TITLE never reaches the heading or
# the FILENAME; (d) a failed source makes ingest exit nonzero (a hook/cron
# caller only sees the code).
hdr "regression: ingest data-safety (v2.27)"
if [ "$PY_OK" = 0 ]; then
  skip "no real python3 here"
elif [ ! -f ai-memory-ingest.sh ]; then
  skip "ai-memory-ingest.sh absent"
else
  # (a) two same-day codex sessions → two distinct vault files
  mkdir -p "$TMP/cxfake" "$TMP/cxvault/05-AI-Sessions"
  printf '%s\n' \
    '{"payload":{"role":"user","content":"morning session unique-alpha"}}' \
    '{"payload":{"role":"assistant","content":"alpha noted"}}' \
    > "$TMP/cxfake/rollout-2026-07-12T09-00-00-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl"
  printf '%s\n' \
    '{"payload":{"role":"user","content":"afternoon session unique-beta"}}' \
    '{"payload":{"role":"assistant","content":"beta noted"}}' \
    > "$TMP/cxfake/rollout-2026-07-12T15-00-00-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jsonl"
  bash ai-memory-ingest.sh "$TMP/cxvault" --source codex --path "$TMP/cxfake" --yes >/dev/null 2>&1
  cxn=$(ls "$TMP/cxvault/05-AI-Sessions/codex/"*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$cxn" = 2 ] \
     && grep -rq "unique-alpha" "$TMP/cxvault/05-AI-Sessions/codex/" \
     && grep -rq "unique-beta" "$TMP/cxvault/05-AI-Sessions/codex/"; then
    pass "two same-day codex sessions → two distinct files (no id collision)"
  else
    fail "same-day codex sessions collided" "count=$cxn"
  fi
  bash ai-memory-ingest.sh "$TMP/cxvault" --source codex --path "$TMP/cxfake" --yes >/dev/null 2>&1
  cxn2=$(ls "$TMP/cxvault/05-AI-Sessions/codex/"*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$cxn2" = 2 ]; then
    pass "re-run idempotent under full ids (still 2 files)"
  else
    fail "full-id re-run changed file count: $cxn2"
  fi
  # a ≤v2.26 legacy file (12-char truncated id, self-consistent hash) must be
  # ADOPTED in place — id line upgraded, same filename, no duplicate file
  python3 - "$TMP/cxvault/05-AI-Sessions/codex" <<'PYFIX'
import hashlib, os, sys
role, text = "user", "gammalt innehall fran v2.26"
h = hashlib.sha256(); h.update((role + "\x00" + text + "\x00").encode("utf-8"))
L = ["# Codex — legacy", "",
     "- source: codex-cli", "- created: 2026-08-01T10:30:45",
     "- id: 2026-08-01T1", "- hash: " + h.hexdigest()[:16],
     "", "---", "", "**You:**", "", text, ""]
open(os.path.join(sys.argv[1], "2026-08-01-codex-legacy-2026-08-01T1.md"),
     "w", encoding="utf-8").write("\n".join(L))
PYFIX
  printf '%s\n' \
    '{"payload":{"role":"user","content":"nytt innehall efter uppgradering"}}' \
    > "$TMP/cxfake/rollout-2026-08-01T10-30-45-cccccccc-cccc-cccc-cccc-cccccccccccc.jsonl"
  bash ai-memory-ingest.sh "$TMP/cxvault" --source codex --path "$TMP/cxfake" --yes > "$TMP/cx.out" 2>&1
  cxn3=$(ls "$TMP/cxvault/05-AI-Sessions/codex/"*.md 2>/dev/null | wc -l | tr -d ' ')
  legacyf="$TMP/cxvault/05-AI-Sessions/codex/2026-08-01-codex-legacy-2026-08-01T1.md"
  if [ "$cxn3" = 3 ] \
     && grep -q "id: 2026-08-01T10-30-45-cccccccc" "$legacyf" 2>/dev/null \
     && grep -q "nytt innehall efter uppgradering" "$legacyf" 2>/dev/null; then
    pass "legacy truncated-id file adopted in place (id upgraded, no duplicate)"
  else
    fail "legacy file was duplicated or not migrated" "count=$cxn3 $(grep '^- id:' "$legacyf" 2>/dev/null)"
  fi

  # (b) a GROWN conversation is regenerated in place even when the vault file
  # was touched by hand (v3.1: notes are generated artifacts — no freeze)
  mkdir -p "$TMP/edfake/proj" "$TMP/edvault/05-AI-Sessions"
  printf '%s\n' \
    '{"type":"ai-title","aiTitle":"Edit regeneration"}' \
    '{"type":"user","timestamp":"2026-02-01T00:00:00Z","message":{"role":"user","content":"original question marker-one"}}' \
    '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"original answer"}]}}' \
    > "$TMP/edfake/proj/55555555-5555-5555-5555-555555555555.jsonl"
  bash ai-memory-ingest.sh "$TMP/edvault" --source claude-code --path "$TMP/edfake" --yes >/dev/null 2>&1
  edfile=$(ls "$TMP/edvault/05-AI-Sessions/claude-code/"*.md 2>/dev/null | head -1)
  # something touches the vault file (hand edit, or an older version's format) …
  python3 - "$edfile" <<'PYFIX'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.replace(
    "original answer", "original answer\n\nMIN EGEN ANTECKNING: viktigt!"))
PYFIX
  # … then the SOURCE grows: the file must be regenerated in place — the
  # follow-up arrives, the foreign edit does not survive, no duplicate file
  printf '%s\n' \
    '{"type":"user","message":{"role":"user","content":"follow-up question"}}' \
    >> "$TMP/edfake/proj/55555555-5555-5555-5555-555555555555.jsonl"
  bash ai-memory-ingest.sh "$TMP/edvault" --source claude-code --path "$TMP/edfake" --yes > "$TMP/ed.out" 2>&1
  edn=$(ls "$TMP/edvault/05-AI-Sessions/claude-code/"*.md 2>/dev/null | wc -l | tr -d ' ')
  if grep -q "follow-up question" "$edfile" 2>/dev/null \
     && ! grep -q "MIN EGEN ANTECKNING" "$edfile" 2>/dev/null \
     && [ "$edn" = 1 ]; then
    pass "grown conversation regenerated in place over a touched file (no freeze, no duplicate)"
  else
    fail "touched vault file was not regenerated in place" "count=$edn $(tail -5 "$TMP/ed.out")"
  fi
  if ! grep -qi "edited by hand" "$TMP/ed.out"; then
    pass "no edited-by-hand freeze path remains (v3.1)"
  else
    fail "edited-by-hand skip resurfaced" "$(tail -5 "$TMP/ed.out")"
  fi

  # (c) a secret in the TITLE must never reach the heading or the filename
  mkdir -p "$TMP/ttfake/proj" "$TMP/ttvault/05-AI-Sessions"
  printf '%s\n' \
    '{"type":"ai-title","aiTitle":"Rotate github_pat_11ABCDE0000aaaaBBBBcc_ZZ9zz9zz9zz9zz9zz9zz9 now"}' \
    '{"type":"user","timestamp":"2026-03-01T00:00:00Z","message":{"role":"user","content":"help me rotate my token"}}' \
    '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"sure"}]}}' \
    > "$TMP/ttfake/proj/66666666-6666-6666-6666-666666666666.jsonl"
  bash ai-memory-ingest.sh "$TMP/ttvault" --source claude-code --path "$TMP/ttfake" --yes >/dev/null 2>&1
  ttfile=$(ls "$TMP/ttvault/05-AI-Sessions/claude-code/"*.md 2>/dev/null | head -1)
  leakname=$(find "$TMP/ttvault/05-AI-Sessions" -iname "*11abcde0000aaaabbbbcc*" 2>/dev/null)
  if [ -n "$ttfile" ] && [ -z "$leakname" ] \
     && ! grep -qi "11ABCDE0000aaaaBBBBcc" "$ttfile" \
     && grep -q "REDACTED:github-token" "$ttfile"; then
    pass "secret in TITLE scrubbed from heading and filename"
  else
    fail "title secret leaked into heading or filename" "$(head -1 "${ttfile:-/dev/null}" 2>/dev/null) ${leakname:-}"
  fi

  # (d) a failed source must be reflected in the exit code (honest exit)
  printf 'not a sqlite database\n' > "$TMP/broken-state.db"
  mkdir -p "$TMP/exvault/05-AI-Sessions"
  bash ai-memory-ingest.sh "$TMP/exvault" --source hermes --path "$TMP/broken-state.db" --yes > "$TMP/ex.out" 2>&1
  ex_rc=$?
  if [ "$ex_rc" != 0 ]; then
    pass "a failed source makes ingest exit nonzero (rc=$ex_rc)"
  else
    fail "ingest exited 0 despite a failed source" "$(tail -3 "$TMP/ex.out")"
  fi
fi

# ── 6k. regression: sync/ingest secret-gate parity (sync v1.1) ────────────────
# sync's outgoing gate greps for the same token shapes ingest scrubs on import.
# The two lists live in different languages (python re / grep ERE) and drifted
# once (github_pat_/AIza/whsec_/JWT missing from sync). This check extracts
# BOTH sets and fails the suite when they drift — the durable fix.
# Since ingest v3.0 the python pattern set lives in lib/aimem_common.py (the
# shared engine module), not in the ingest heredoc — read it from there.
hdr "regression: sync/ingest secret-gate parity"
if [ "$PY_OK" = 0 ]; then
  skip "no real python3 here"
elif [ ! -f ai-memory-sync.sh ] || [ ! -f lib/aimem_common.py ]; then
  skip "ai-memory-sync.sh or lib/aimem_common.py absent"
else
  if parity=$(python3 - lib/aimem_common.py ai-memory-sync.sh <<'PYFIX'
import re, sys
ing = open(sys.argv[1], encoding="utf-8").read()
syn = open(sys.argv[2], encoding="utf-8").read()
blk = re.search(r"_SECRET_PATTERNS = \((.*?)\n\)\n", ing, re.S)
pats = re.findall(r're\.compile\(r"([^"]+)"', blk.group(1)) if blk else []
m = re.search(r"\nSECRET_ERE='([^']+)'", syn)
frags = m.group(1).split("|") if m else []
strip = lambda s: s.replace("\\b", "")
# grep is line-based: ingest's multi-line private-key pattern can only be
# matched by its BEGIN marker, so compare everything up to the first `.*?`.
want = set(strip(p).split(".*?")[0] for p in pats)
have = set(strip(f) for f in frags)
missing = sorted(want - have); extra = sorted(have - want)
if not pats or not frags or missing or extra:
    print("ingest patterns: %d, sync fragments: %d" % (len(pats), len(frags)))
    for p in missing: print("missing in sync: %s" % p)
    for p in extra:   print("extra in sync:   %s" % p)
    sys.exit(1)
print("%d secret patterns in lockstep" % len(pats))
PYFIX
  ); then
    pass "sync gate matches ingest's scrub set ($parity)"
  else
    fail "sync/ingest secret patterns drifted" "$parity"
  fi
fi

# ── 6k2. regression: sync never downgrades the central's tools (sync v1.3) ────
# A stale clone's push used to overwrite the central's newer .tools copy on
# every run (live incident 2026-07-14→15). _tool_newer is the guard: extract
# the function from the script and prove strictly-newer semantics.
hdr "regression: sync tool-install never downgrades (sync v1.3)"
if [ ! -f ai-memory-sync.sh ]; then
  skip "ai-memory-sync.sh absent"
else
  fndef=$(sed -n '/^_tool_newer()/,/^}/p' ai-memory-sync.sh)
  if [ -z "$fndef" ]; then
    fail "_tool_newer missing from ai-memory-sync.sh" ""
  else
    eval "$fndef"
    tn_ok=1
    _tool_newer 3.1 2.26  || tn_ok=0     # newer local → install
    _tool_newer 3.1 ""    || tn_ok=0     # no remote   → first install
    _tool_newer 2.26 3.1  && tn_ok=0     # older local → keep central
    _tool_newer 3.1 3.1   && tn_ok=0     # same        → no rewrite
    _tool_newer 3.10 3.9  || tn_ok=0     # sort -V, not lexical
    if [ "$tn_ok" = 1 ]; then
      pass "_tool_newer: strictly-newer semantics (incl. 3.10 > 3.9, empty remote)"
    else
      fail "_tool_newer semantics wrong — downgrade guard unreliable" ""
    fi
    if grep -q '_tool_newer "$lver" "$rver"' ai-memory-sync.sh \
       && grep -q 'tools/lib' ai-memory-sync.sh; then
      pass "push gates the tool install on _tool_newer and ships lib/ with it"
    else
      fail "tool install is not gated on _tool_newer (or lib/ not shipped)" ""
    fi
  fi
fi

# ── 6l. launcher degrades gracefully when lib/ is missing (v3.0/v2.0) ─────────
# A stray copy of the .sh with no lib/ anywhere must die LOUDLY with the two
# valid layouts named — never a silent python traceback or a half-run. HOME is
# pointed at an empty sandbox so the default-vault fallback can't accidentally
# find a real ~/Documents/ai-memory/.tools/lib on this machine.
hdr "launcher missing-lib error (ingest v3.0 / search v2.0)"
mkdir -p "$TMP/nolib" "$TMP/nolibhome"
for s in ai-memory-ingest.sh ai-memory-search.sh; do
  if [ ! -f "$s" ]; then skip "$s absent"; continue; fi
  cp "$s" "$TMP/nolib/"
  out=$(HOME="$TMP/nolibhome" bash "$TMP/nolib/$s" --version 2>&1)
  rc=$?
  if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q "python engine not found" \
     && printf '%s' "$out" | grep -q ".tools/lib"; then
    pass "$s: missing lib/ → clear error naming both layouts, exit $rc"
  else
    fail "$s did not degrade clearly without lib/" "rc=$rc: $(printf '%s' "$out" | head -2)"
  fi
done

# ── 6m. installed layout: .tools copies run WITHOUT the repo checkout ─────────
# setup/configure install the launchers into <vault>/.tools/ and the engines
# into <vault>/.tools/lib/. Simulate exactly that layout in a sandbox (same
# files the installers copy), point HOME away from any real vault, and prove
# (a) the .tools copies work standalone — the self-ingest hook path — and
# (b) a stray launcher elsewhere finds the engine via its vault argument.
hdr "installed layout (.tools + .tools/lib, no repo)"
if [ "$PY_OK" = 0 ]; then
  skip "no real python3 here"
elif [ ! -f lib/aimem_ingest.py ] || [ ! -f ai-memory-ingest.sh ] || [ ! -f ai-memory-search.sh ]; then
  skip "launchers or lib/ absent"
else
  IV="$TMP/instvault"
  mkdir -p "$IV/05-AI-Sessions" "$IV/.tools/lib" "$TMP/insthome"
  cp ai-memory-ingest.sh ai-memory-search.sh "$IV/.tools/"
  cp lib/aimem_common.py lib/aimem_ingest.py lib/aimem_search.py "$IV/.tools/lib/"
  # (a) the .tools copies themselves (launcher finds <script_dir>/lib)
  iv=$(HOME="$TMP/insthome" bash "$IV/.tools/ai-memory-ingest.sh" --version 2>&1)
  if [ $? -eq 0 ] && printf '%s' "$iv" | grep -q "v3\."; then
    pass ".tools ingest runs standalone ($iv)"
  else
    fail ".tools ingest failed without the repo" "$iv"
  fi
  mkdir -p "$TMP/instfake/proj"
  printf '%s\n' \
    '{"type":"ai-title","aiTitle":"Installed layout"}' \
    '{"type":"user","timestamp":"2026-01-03T00:00:00Z","message":{"role":"user","content":"installerad-markor fungerar"}}' \
    '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ja"}]}}' \
    > "$TMP/instfake/proj/77777777-7777-7777-7777-777777777777.jsonl"
  HOME="$TMP/insthome" bash "$IV/.tools/ai-memory-ingest.sh" "$IV" \
    --source claude-code --path "$TMP/instfake" --yes > "$TMP/inst.out" 2>&1
  if ls "$IV/05-AI-Sessions/claude-code/"*.md >/dev/null 2>&1 \
     && grep -rq "installerad-markor" "$IV/05-AI-Sessions/claude-code/"; then
    pass ".tools ingest imports for real (the self-ingest hook path)"
  else
    fail ".tools ingest import failed" "$(tail -3 "$TMP/inst.out")"
  fi
  sv=$(HOME="$TMP/insthome" bash "$IV/.tools/ai-memory-search.sh" "$IV" "installerad markor fungerar" 2>&1)
  if [ $? -eq 0 ] && printf '%s' "$sv" | grep -q "MEMORY SEARCH"; then
    pass ".tools search runs standalone against the vault"
  else
    fail ".tools search failed without the repo" "$(printf '%s' "$sv" | head -2)"
  fi
  # (b) stray launcher + vault argument → engine resolved via <vault>/.tools/lib
  mkdir -p "$TMP/stray"
  cp ai-memory-search.sh "$TMP/stray/"
  sv2=$(HOME="$TMP/insthome" bash "$TMP/stray/ai-memory-search.sh" "$IV" "installerad markor fungerar" 2>&1)
  if [ $? -eq 0 ] && printf '%s' "$sv2" | grep -q "MEMORY SEARCH"; then
    pass "stray launcher finds the engine via its vault argument (.tools/lib fallback)"
  else
    fail "vault-argument lib fallback failed" "$(printf '%s' "$sv2" | head -2)"
  fi
fi

# ── 7. mux: real tmux session shape (skipped without tmux) ───────────────────
hdr "mux tmux session (live)"
if ! command -v tmux >/dev/null 2>&1; then
  skip "tmux not installed"
elif [ ! -f ai-memory-mux.sh ]; then
  skip "ai-memory-mux.sh absent"
else
  tmux kill-session -t aimtest_mux 2>/dev/null || true
  mkdir -p "$TMP/muxvault"
  AI_MEMORY_MUX_SESSION=aimtest_mux AI_MEMORY_VAULT="$TMP/muxvault" \
    AI_MEMORY_AGENT_CMD="exec bash" AI_MEMORY_NO_INGEST=1 \
    bash ai-memory-mux.sh start --no-attach >/dev/null 2>&1
  panes=$(tmux list-panes -t aimtest_mux 2>/dev/null | grep -c . )
  mouse=$(tmux show-options -t aimtest_mux mouse 2>/dev/null)
  # Side-by-side default (v1.3): both panes start at the same top row —
  # a stacked (horizontal) split would give two distinct pane_top values.
  tops=$(tmux list-panes -t aimtest_mux -F '#{pane_top}' 2>/dev/null | sort -u | grep -c .)
  lefts=$(tmux list-panes -t aimtest_mux -F '#{pane_left}' 2>/dev/null | sort -u | grep -c .)
  tmux kill-session -t aimtest_mux 2>/dev/null || true
  if [ "$panes" = 2 ]; then pass "2-pane split created"; else fail "expected 2 panes, got $panes"; fi
  if [ "$tops" = 1 ] && [ "$lefts" = 2 ]; then
    pass "panes are SIDE BY SIDE (shared top edge, distinct left edges)"
  else
    fail "split is not side-by-side" "pane_top values: $tops, pane_left values: $lefts"
  fi
  case "$mouse" in *"mouse on"*) pass "mouse on";; *) fail "mouse not on" "$mouse";; esac
fi

# ── summary ──────────────────────────────────────────────────────────────────
printf "\n${B}%s${N}\n" "────────────────────────────────────"
printf "${B}Result:${N} ${G}%d passed${N}, ${R}%d failed${N}, ${Y}%d skipped${N}\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
