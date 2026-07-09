#!/usr/bin/env bash
# =============================================================================
#  tests/run.sh — the AI Memory Stack's first automated safety net.
#
#  Fast, dependency-light checks that a machine (or CI) can run in seconds:
#    • bash -n parse of every script
#    • shellcheck of every script        (skipped with a note if not installed)
#    • --version / --help smoke tests     (exit 0, prints a version)
#    • version consistency                (header == --version == banner)
#    • regression: uninstall --no-export --yes must NOT delete without the
#      loud DELETE confirm / --force-no-export  (locks in the v1.2 fix)
#    • mux: a real tmux session has 2 panes + mouse on  (skipped if no tmux)
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
FAMILY="ai-memory-setup.sh ai-memory-configure.sh ai-memory-ingest.sh ai-memory-doctor.sh ai-memory-remote.sh ai-memory-uninstall.sh ai-memory-mux.sh ai-memory-sync.sh ai-memory-search.sh"
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

# ── 4. version consistency (header == --version == banner) ───────────────────
hdr "version consistency"
for s in $FAMILY; do
  [ -f "$s" ] || continue
  if [ "$s" = ai-memory-ingest.sh ] && [ "$PY_OK" = 0 ]; then skip "$s (no real python3 here)"; continue; fi
  vflag=$(bash "$s" --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+' | head -1)
  [ -z "$vflag" ] && { skip "$s (no --version)"; continue; }
  # header line 2-4 must mention the same vX.Y
  if head -6 "$s" | grep -qF " $vflag"; then hdr_ok=1; else hdr_ok=0; fi
  # banner (the box line) — only scripts that draw one; tolerate absence
  if grep -qE '║.*'"$vflag" "$s"; then ban_ok=1; else ban_ok=2; fi
  if [ "$hdr_ok" = 1 ] && [ "$ban_ok" != 0 ]; then
    pass "$s  header/banner agree on $vflag"
  else
    fail "$s version drift" "flag=$vflag header_match=$hdr_ok banner=$ban_ok"
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
    '{"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"my key is sk-or-v1-0123456789abcdef0123456789abcdef"}}' \
    '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"noted"}]}}' \
    > "$TMP/ccfake/proj/11111111-1111-1111-1111-111111111111.jsonl"
  bash ai-memory-ingest.sh "$TMP/scrubvault" --source claude-code --path "$TMP/ccfake" --yes >/dev/null 2>&1
  scrubfile=$(ls "$TMP/scrubvault/05-AI-Sessions/claude-code/"*.md 2>/dev/null | head -1)
  if [ -n "$scrubfile" ] && grep -q "REDACTED:api-key" "$scrubfile" \
     && ! grep -q "sk-or-v1-0123456789" "$scrubfile"; then
    pass "pasted api key redacted on import"
  else
    fail "secret survived into vault (or import failed)" "${scrubfile:-no file written}"
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
       && grep -q "ai-memory-ingest.sh .* --source hermes" "$TMP/hh1/config.yaml" 2>/dev/null \
       && grep -q "pre_llm_call:" "$TMP/hh1/config.yaml" 2>/dev/null; then
      pass "configure registers the self-ingest hooks (on_session_end + on_session_start), pre_llm_call intact"
    else
      fail "configure did not register both self-ingest hooks" "$(grep -nE 'hooks|on_session|ingest|pre_llm' "$TMP/hh1/config.yaml" 2>/dev/null | head -8)"
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
    AI_MEMORY_AGENT_CMD="exec bash" \
    bash ai-memory-mux.sh start --no-attach >/dev/null 2>&1
  panes=$(tmux list-panes -t aimtest_mux 2>/dev/null | grep -c . )
  mouse=$(tmux show-options -t aimtest_mux mouse 2>/dev/null)
  tmux kill-session -t aimtest_mux 2>/dev/null || true
  if [ "$panes" = 2 ]; then pass "2-pane split created"; else fail "expected 2 panes, got $panes"; fi
  case "$mouse" in *"mouse on"*) pass "mouse on";; *) fail "mouse not on" "$mouse";; esac
fi

# ── summary ──────────────────────────────────────────────────────────────────
printf "\n${B}%s${N}\n" "────────────────────────────────────"
printf "${B}Result:${N} ${G}%d passed${N}, ${R}%d failed${N}, ${Y}%d skipped${N}\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
