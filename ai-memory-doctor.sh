#!/usr/bin/env bash
# =============================================================================
#  ai-memory-doctor.sh  v1.0
#  Health + reachability check for the AI Memory Stack — "prove my memory is
#  reachable from every door."  READ-ONLY: it diagnoses, never changes anything.
#
#  Checks (deterministic, no model, no tokens):
#    1. Vault structure
#    2. Import INDEX present + in sync with the files on disk (detects
#       imported-but-not-indexed and indexed-but-missing — §4.3.1)
#    3. Handover (~/.hermes/SOUL.md) present, with the ABSOLUTE vault path +
#       search routine — the cwd-independent thing that makes EVERY door work
#    4. Per-door wiring (TERMINAL_CWD in .env + the shell launcher)
#    5. Model floor — warns if the configured model is likely too weak (§4.2)
#    6. Searchability proof — from a FOREIGN cwd, the prescribed absolute-path
#       search actually finds vault content (the core promise, model-free)
#  Optional (--live): a real recall round-trip through the shell door — runs
#  `hermes chat -q` and confirms a REAL tool call returned vault content (§4.3.1
#  point 8).  Costs tokens + needs the model up; dashboard/gateway must be
#  confirmed in the browser (can't be driven headlessly).
#
#  Usage: bash ai-memory-doctor.sh [path/to/vault] [--live]
#  Exit:  0 = healthy (warnings allowed) · 1 = a critical door is broken
# =============================================================================

# NOTE: intentionally NOT `set -e` — doctor RUNS checks that are meant to fail
# (a missing handover is a finding, not a script error). We track findings
# ourselves; a failed check must never abort the rest of the report.
set -uo pipefail

if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi
info() { echo -e "${CYAN}→${NC}  $*"; }
hdr()  { echo -e "\n${BOLD}── $* ──${NC}"; }
lc()   { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

PASS=0; WARN=0; FAIL=0
p() { echo -e "  ${GREEN}✓${NC}  $*"; PASS=$((PASS+1)); }
w() { echo -e "  ${YELLOW}⚠${NC}  $*"; WARN=$((WARN+1)); }
f() { echo -e "  ${RED}✗${NC}  $*"; FAIL=$((FAIL+1)); }
fix() { echo -e "      ${DIM}fix: $*${NC}"; }

LIVE=false
VAULT=""
for arg in "$@"; do
  case "$arg" in
    --live) LIVE=true ;;
    -h|--help)    sed -n '2,21p' "$0" | sed 's/^#//'; exit 0 ;;
    -V|--version) echo "ai-memory-doctor.sh v1.0"; exit 0 ;;
    -*) ;;
    *) [[ -z "$VAULT" ]] && VAULT="$arg" ;;
  esac
done
VAULT="${VAULT:-$HOME/Documents/ai-memory}"
[[ "$VAULT" != /* ]] && VAULT="$PWD/$VAULT"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
OUT="$VAULT/05-AI-Sessions"
SOUL="$HERMES_HOME/SOUL.md"
ENVF="$HERMES_HOME/.env"
CFG="$HERMES_HOME/config.yaml"
CONFIGURE="$VAULT/.tools/ai-memory-configure.sh"
INGEST="$VAULT/.tools/ai-memory-ingest.sh"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   AI Memory Stack  v1.0 — Doctor         ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
info "Vault:       $VAULT"
info "Hermes home: $HERMES_HOME"

# ── 1. Vault ─────────────────────────────────────────────────────────────────
hdr "1. Vault"
if [[ ! -d "$OUT" ]]; then
  f "No vault at $VAULT (missing 05-AI-Sessions/)."
  fix "bash ai-memory-setup.sh $VAULT"
  echo -e "\n${RED}${BOLD}Cannot continue without a vault.${NC}\n"
  exit 1
fi
CONV=$(find "$OUT" -type f -name '*.md' ! -name 'INDEX.md' 2>/dev/null | wc -l | tr -d ' ')
p "Vault present — $CONV imported conversation file(s)."

# ── 2. Import index ──────────────────────────────────────────────────────────
hdr "2. Import index"
if [[ ! -f "$OUT/INDEX.md" ]]; then
  w "No INDEX.md — a keyword-less 'what do you remember?' has no manifest to read."
  fix "bash $INGEST --reindex $VAULT"
else
  REPORT=$(python3 - "$OUT" << 'PYIDX'
import sys, re
from pathlib import Path
out = Path(sys.argv[1])
disk = {str(p.relative_to(out)) for p in out.rglob("*.md") if p.name != "INDEX.md"}
idx_txt = (out / "INDEX.md").read_text(errors="replace")
indexed = set(re.findall(r"05-AI-Sessions/(\S+?\.md)", idx_txt))
missing_from_index = disk - indexed
indexed_but_absent = indexed - disk
print(f"DISK {len(disk)}")
print(f"INDEXED {len(indexed)}")
for m in sorted(missing_from_index): print(f"MISSING {m}")
for a in sorted(indexed_but_absent): print(f"ABSENT {a}")
PYIDX
)
  NMISS=$(echo "$REPORT" | grep -c '^MISSING ')
  NABS=$(echo "$REPORT" | grep -c '^ABSENT ')
  IDXN=$(echo "$REPORT" | awk '/^INDEXED/{print $2}')
  if [[ "$NMISS" -eq 0 && "$NABS" -eq 0 ]]; then
    p "INDEX.md is in sync with disk ($IDXN conversations listed)."
  else
    [[ "$NMISS" -gt 0 ]] && w "$NMISS conversation(s) on disk are NOT in the index (imported-but-not-indexed)."
    [[ "$NABS"  -gt 0 ]] && w "$NABS index entr(ies) point to files that no longer exist."
    fix "bash $INGEST --reindex $VAULT"
  fi
fi

# ── 3. Handover (the cwd-independent door fix) ───────────────────────────────
hdr "3. Handover  (makes recall work from EVERY door, any directory)"
if [[ ! -f "$SOUL" ]]; then
  f "No handover at $SOUL — the dashboard/gateway will be memory-blind."
  fix "bash $CONFIGURE $VAULT"
else
  hok=true
  grep -q "ai-memory handover" "$SOUL"      || { f "SOUL.md has no ai-memory handover block."; hok=false; }
  grep -qF "$VAULT" "$SOUL"                  || { f "Handover is missing the ABSOLUTE vault path ($VAULT)."; hok=false; }
  grep -qiE "grep -rli|SEARCH" "$SOUL"       || { w "Handover has no explicit search routine."; hok=false; }
  $hok && p "Handover present — absolute vault path + search routine, loaded by every door."
  $hok || fix "bash $CONFIGURE $VAULT"
fi

# ── 4. Per-door wiring ───────────────────────────────────────────────────────
hdr "4. Door wiring  (every launch rooted at the vault)"
tcwd=""
if [[ -f "$ENVF" ]]; then
  tcwd=$(grep '^TERMINAL_CWD=' "$ENVF" 2>/dev/null | tail -1 | cut -d= -f2-)
  tcwd=${tcwd%\"}; tcwd=${tcwd#\"}        # strip optional surrounding double quotes
fi
if [[ "${tcwd%/}" == "${VAULT%/}" ]]; then
  p "TERMINAL_CWD → vault (in ~/.hermes/.env)."
else
  w "TERMINAL_CWD not set to the vault in ~/.hermes/.env."
  fix "bash $CONFIGURE $VAULT"
fi
launcher=false
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f "$rc" ]] || continue
  if grep -q "ai-memory hermes launcher" "$rc" && grep -q "TERMINAL_CWD=" "$rc"; then launcher=true; fi
done
if $launcher; then
  p "Shell launcher installed — 'hermes', 'hermes dashboard' and 'hermes gateway' all root at the vault."
else
  w "No shell launcher (or it doesn't export TERMINAL_CWD) — the dashboard may load the wrong context."
  fix "bash $CONFIGURE $VAULT  (then open a new terminal)"
fi

# ── 5. Model floor ───────────────────────────────────────────────────────────
hdr "5. Model capability floor  (§4.2)"
MODEL=""
[[ -f "$CFG" ]] && MODEL=$(grep -m1 '^[[:space:]]*default:' "$CFG" 2>/dev/null | sed 's/.*default:[[:space:]]*//' | tr -d ' ')
if [[ -z "$MODEL" ]]; then
  w "No model found in $CFG."
  fix "bash $CONFIGURE $VAULT"
else
  t=$(lc "$MODEL")
  case "$t" in
    *mini*|*gpt-3.5*|*haiku-3*|*tinyllama*|*phi-2*|*gemma:2b*|\
    *:0.5b*|*:1b*|*:1.5b*|*:2b*|*:3b*|*-1b*|*-3b*|\
    *qwen3.5*|*gemma4*|*:7b*|*:8b*|*:9b*|*:13b*|*:14b*|*-7b*|*-8b*|*-13b*|*-14b*)
      w "Model '$MODEL' may be too weak for memory. Weak models FAKE the search —"
      echo -e "      ${DIM}they say 'nothing found' without running grep (live: qwen3.5 14B = 0 tool"
      echo -e "      calls). For reliable recall prefer a capable cloud model (key in ~/.hermes/.env).${NC}" ;;
    *) p "Model '$MODEL' — above the rough memory tool-use floor (heuristic)." ;;
  esac
fi

# ── 6. Searchability proof (no model) ────────────────────────────────────────
hdr "6. Searchability  (the prescribed search reaches your memory from ANY cwd)"
if [[ "$CONV" -eq 0 ]]; then
  w "No conversations imported yet — nothing to search."
  fix "bash $INGEST $VAULT"
else
  KW=$(python3 - "$OUT" << 'PYKW'
import sys, re
from pathlib import Path
out = Path(sys.argv[1])
for pth in sorted(out.rglob("*.md")):
    if pth.name == "INDEX.md": continue
    try: txt = pth.read_text(errors="replace")
    except OSError: continue
    m = re.search(r'#\s+(.+)', txt)
    words = re.findall(r'[A-Za-z]{5,}', m.group(1) if m else pth.stem)
    if words: print(words[0]); break
PYKW
)
  if [[ -z "$KW" ]]; then
    w "Could not derive a probe keyword (unusual filenames) — skipping search proof."
  else
    HITS=$( ( cd /tmp 2>/dev/null && grep -rli --exclude=INDEX.md "$KW" "$OUT" 2>/dev/null ) | wc -l | tr -d ' ')
    if [[ "$HITS" -ge 1 ]]; then
      p "From /tmp (a foreign cwd), the absolute-path search found '$KW' in $HITS file(s) — memory IS reachable."
    else
      f "The prescribed search from a foreign cwd found nothing for '$KW' — reachability is broken."
      fix "bash $CONFIGURE $VAULT"
    fi
  fi
fi

# ── 7. Live recall probe (opt-in) ────────────────────────────────────────────
if $LIVE; then
  hdr "7. Live recall probe  (real round-trip through the shell door)"
  if ! command -v hermes >/dev/null 2>&1; then
    w "'hermes' not on PATH — skipping the live probe."
  elif [[ "$CONV" -eq 0 ]]; then
    w "No conversations to recall — skipping the live probe."
  else
    info "Asking hermes to recall '$KW' from a foreign cwd (this costs a few tokens)..."
    OUTP=$( ( cd /tmp 2>/dev/null && hermes chat -q \
      "Search your memory for \"$KW\" and tell me what you find. Cite the file path." \
      --yolo 2>&1 ) )
    CALLS=$(echo "$OUTP" | grep -oE '[0-9]+ tool call' | head -1 | grep -oE '[0-9]+' )
    CALLS=${CALLS:-0}
    if [[ "$CALLS" -eq 0 ]]; then
      f "Live: the model made 0 tool calls — it is NOT searching (model too weak? see check 5)."
      fix "use a capable cloud model for memory (key in ~/.hermes/.env)"
    elif echo "$OUTP" | grep -q "05-AI-Sessions"; then
      p "Live shell door OK — $CALLS real tool call(s) and a vault file was cited. Memory recall works."
    else
      w "Live: $CALLS tool call(s) made, but no vault file was cited in the answer — inspect manually."
    fi
    echo -e "      ${DIM}Note: the web dashboard / gateway can't be driven headlessly — confirm those"
    echo -e "      in the browser (ask a memory question, expect a real search + a cited file).${NC}"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
hdr "Summary"
echo -e "  ${GREEN}$PASS passed${NC}   ${YELLOW}$WARN warning(s)${NC}   ${RED}$FAIL failed${NC}"
if [[ "$FAIL" -gt 0 ]]; then
  echo -e "\n  ${RED}${BOLD}A critical door is broken — memory recall is not reliable yet.${NC}"
  echo -e "  ${DIM}Apply the fixes above, then re-run: bash $0 $VAULT${NC}\n"
  exit 1
elif [[ "$WARN" -gt 0 ]]; then
  echo -e "\n  ${YELLOW}Working, with warnings — recall should function; address the warnings to harden it.${NC}\n"
  exit 0
else
  echo -e "\n  ${GREEN}${BOLD}All good — your memory is reachable from every door.${NC}"
  $LIVE || echo -e "  ${DIM}Tip: run with --live for a real recall round-trip.${NC}"
  echo ""
  exit 0
fi
