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
FAMILY="ai-memory-setup.sh ai-memory-configure.sh ai-memory-ingest.sh ai-memory-doctor.sh ai-memory-remote.sh ai-memory-uninstall.sh ai-memory-mux.sh ai-memory-sync.sh"
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
cleanup() { rm -rf "$TMP" 2>/dev/null; command -v tmux >/dev/null 2>&1 && tmux kill-session -t aimtest_mux 2>/dev/null; return 0; }
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
