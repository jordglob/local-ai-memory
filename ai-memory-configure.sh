#!/usr/bin/env bash
# =============================================================================
#  ai-memory-configure.sh  v5.9
#  Interactive configuration of the AI Memory Stack
#
#  What it does:
#    1. Analyzes hardware (RAM, GPU, CPU)
#    2. Scans the disk for local AI models (Ollama, LM Studio, HF cache, ...)
#    3. Picks the model source: local Ollama, REMOTE Ollama (LAN) or cloud
#    4. Writes the real Hermes config (~/.hermes/config.yaml)
#    5. Optionally stores API keys in ~/.hermes/.env and WRITES the fallback
#       chain (hermes fallback_providers) so failover actually happens
#    6. Writes ai-config.json + model inventory report into the vault
#
#  Usage: bash ai-memory-configure.sh [path/to/vault]
#         bash ai-memory-configure.sh [vault] --remote-ollama=HOST[:PORT]
#  Requires: ai-memory-setup.sh completed first
#  Estimated time: 2–5 min (plus model download if you choose to pull one)
#  v5.9:  hook-registration idempotency is whitespace-normalized — a re-run no
#         longer DUPLICATES pre_llm_call when Hermes has re-dumped config.yaml with
#         the long command line-FOLDED (live bug 2026-07-10, surfaced by re-running
#         configure to bake in ad-hoc edits). self-ingest already keys on the event
#         name so it was unaffected; the fix hardens the search-hook check.
#  v5.8:  self-ingest hook fires `ingest --local` (not just --source hermes) — the
#         Hermes session hook is now the OS-general trigger that sweeps EVERY local
#         agent store (claude-code, codex, gemini-cli, …) into the vault, so synced
#         CC sessions get archived without a bespoke per-OS script. Not CC-specific.
#  v5.7:  self-ingest also registers on_session_start (belt-and-suspenders) so a
#         crash you never follow with another session still gets swept at the next
#         start; end-hook stays primary. Idempotent per-event (existing keys kept).
#  v5.6:  registers the self-ingest HOOK (hermes on_session_end → ingest --source
#         hermes) so Hermes archives its OWN sessions into the vault — OS-generally,
#         no per-OS launchd/cron/Task Scheduler. Idempotent full re-scan every fire
#         makes it crash-resilient (a session that dies before its end-hook is
#         archived by the next clean session-end). Proven in an isolated HERMES_HOME
#         sandbox end-to-end (hook fires + writes the ~/Documents vault past macOS TCC).
#  v5.5:  registers the memory-search HOOK (hermes pre_llm_call) so recall is
#         MODEL-AGNOSTIC: small models won't call a tool from SOUL (0/9 live),
#         so the hook runs the search automatically and injects hits into the
#         user message — any model just reads them. Sets hooks_auto_accept:true
#         for non-TTY runs. Targeted config edits; the model/moa block is safe.
#  v5.4:  SOUL points at ai-memory-search.sh — the deterministic memory-search
#         tool (§4.5). Live tests proved the recall floor is a small model's
#         inability to CARRY OUT a multi-step search, not tool access: even
#         with the strategy in SOUL, single models failed 9/9 and MoA was ~50%.
#         So the search itself is now a SCRIPT the model calls in one step;
#         configure installs it into .tools/ and the handover tells the model
#         to run it. Grep fallback kept for when the tool is absent.
#  v5.3:  SOUL handover STEERS TO FILESYSTEM TOOLS. The v5.2 recipe shipped
#         but its live proof failed: small models, seeing hermes' native
#         memory tools, called session_search / the memory tool (which read
#         the agent's OWN session db, not the vault) and came back empty.
#         The handover now says explicitly: the vault is markdown FILES — use
#         grep/ls/cat, NOT session_search or the memory tool, for vault
#         questions.
#  v5.2:  SOUL handover carries the proven SEARCH-PERSISTENCE recipe — the
#         target-picture round (2026-07-07) found the recall floor is the
#         search strategy, not model size: every model (incl. 35B) gave up
#         after one empty grep, but with "don't stop at the first miss, try
#         synonyms/EN+native/acronyms/brand/model, also scan INDEX" in the
#         prompt even a 5 GB model answered exactly. That recipe now lives in
#         SOUL.md so it applies to EVERY model without the user prompting it.
#  v5.1:  --yes NEVER replaces an existing model block (probeable or not) —
#         the v5.0 answer-probe rule clobbered a live moa-provider block
#         (empty base_url → unprobeable → rewritten) on the central. Replace
#         now requires an interactive yes or an explicit --remote-ollama.
#  v5.0:  three model sources (local/remote/cloud); a model config whose
#         endpoint ANSWERS is never clobbered (the WSL live wound, 2026-07-06);
#         fallback chain written for real; ai-config.json carries the real
#         base_url; non-TTY runs never exec ingest; /model + hermes fallback
#         switching taught at the end.
#  v4.13: safe YAML quoting; exact ollama tag match; atomic .env; Windows/WSL RAM; shell-safe launcher.
# =============================================================================

set -euo pipefail

if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

ok()   { echo -e "${GREEN}✓${NC}  $*"; }
info() { echo -e "${CYAN}→${NC}  $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
die()  { echo -e "\n${RED}${BOLD}✗  ERROR: $*${NC}\n" >&2; exit 1; }
hdr()  { echo -e "\n${BOLD}── $* ──${NC}"; }
ask()  { echo -e "${CYAN}?${NC}  $*"; }
lc()   { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

case "${1:-}" in
  -h|--help)
    sed -n '2,25p' "$0" | sed 's/^#//'; exit 0 ;;
  -V|--version) echo "ai-memory-configure.sh v5.9"; exit 0 ;;
esac

ASSUME_YES=false
VAULT=""
REMOTE_OLLAMA=""
for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=true ;;
    --remote-ollama=*) REMOTE_OLLAMA="${arg#*=}" ;;
    -*) ;;
    *)  [[ -z "$VAULT" ]] && VAULT="$arg" ;;
  esac
done
VAULT="${VAULT:-$HOME/Documents/ai-memory}"
[[ "$VAULT" != /* ]] && VAULT="$PWD/$VAULT"
MCP_DIR="$VAULT/.mcp"
CONFIG_FILE="$MCP_DIR/ai-config.json"
REPORT_DIR="$VAULT/03-Resources/AI-Models"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_CONFIG="$HERMES_HOME/config.yaml"
HERMES_ENV="$HERMES_HOME/.env"
# §4.12 migration-awareness: remember whether a Hermes config existed BEFORE we
# (re)write one — a populated vault + no prior config = a vault moved onto this box.
CONFIG_PREEXISTED=false; [[ -f "$HERMES_CONFIG" ]] && CONFIG_PREEXISTED=true

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   AI Memory Stack  v5.9 — Configure      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
[[ -d "$VAULT/entities" ]] \
  || die "Vault not found: $VAULT\n  Run setup first: bash ai-memory-setup.sh $VAULT"
info "Vault:        $VAULT"
info "Hermes home:  $HERMES_HOME"
command -v hermes &>/dev/null || [[ -d "$HERMES_HOME" ]] \
  || warn "Hermes not detected — config will be written for when it's installed"
echo ""

# §4.12 migration-awareness: a populated vault with NO prior Hermes config on this
# machine means you restored/synced a vault onto a new box — welcome you back and
# set expectations honestly (config + API keys did NOT travel, by design).
# pipefail-safe: a vault without 05-AI-Sessions/ (unusual but legal) must not
# kill the run — find's rc=1 would otherwise abort under set -euo pipefail.
_CONV_COUNT=$(find "$VAULT/05-AI-Sessions" -type f -name '*.md' ! -name 'INDEX.md' 2>/dev/null | wc -l | tr -d ' ') || _CONV_COUNT=0
if [[ "${_CONV_COUNT:-0}" -gt 0 && "$CONFIG_PREEXISTED" == false ]]; then
  hdr "🧳 Migration detected — welcome back"
  ok "Found a restored memory vault with ${_CONV_COUNT} imported conversation(s)."
  echo -e "  ${DIM}Your memory came across. What did NOT travel (by design): this machine's"
  echo -e "  Hermes config + API keys — I'll set those up now for THIS hardware. If this"
  echo -e "  box is more/less capable than your old one, the best model may differ; I'll"
  echo -e "  recommend based on the scan below. Verify after with: ai-memory-doctor.sh${NC}"
  echo ""
fi

# ═════════════════════════════════════════════════════════════════════════════
# 1/5  HARDWARE ANALYSIS
# ═════════════════════════════════════════════════════════════════════════════
hdr "1/5  Hardware analysis"

HW=$(python3 << 'PYHW'
import os, platform, json, subprocess
def run(cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""
hw = {"ram_gb":0.0,"cpu_name":"","cpu_cores":os.cpu_count() or 0,
      "gpu_type":"none","gpu_name":"","vram_gb":0.0,"apple_silicon":False}
sysname = platform.system()
if sysname == "Darwin":
    m = run(["sysctl","-n","hw.memsize"])
    if m: hw["ram_gb"] = round(int(m)/1e9,1)
    hw["cpu_name"] = run(["sysctl","-n","machdep.cpu.brand_string"])
    if "arm" in platform.machine().lower() or run(["sysctl","-n","hw.optional.arm64"]) == "1":
        hw.update(apple_silicon=True, gpu_type="apple",
                  vram_gb=hw["ram_gb"], gpu_name=hw["cpu_name"] or "Apple Silicon")
elif sysname == "Linux":
    # CAVEAT (WSL2): under WSL2 /proc/meminfo reports the Linux VM's memory
    # allotment (default ~50% of host, capped by .wslconfig), NOT the machine's
    # physical RAM — so ram_gb here can read low on an otherwise capable box.
    try:
        for line in open("/proc/meminfo"):
            if line.startswith("MemTotal"):
                hw["ram_gb"] = round(int(line.split()[1])/1e6,1); break
        for line in open("/proc/cpuinfo"):
            if "model name" in line:
                hw["cpu_name"] = line.split(":",1)[1].strip(); break
    except Exception: pass
elif sysname == "Windows":
    # Native Windows python has no /proc; query physical RAM via the Win32 API so
    # ram_gb isn't left 0 (which would misclassify the box as "weak").
    try:
        import ctypes
        class _MEMSTAT(ctypes.Structure):
            _fields_ = [("dwLength", ctypes.c_ulong),
                        ("dwMemoryLoad", ctypes.c_ulong),
                        ("ullTotalPhys", ctypes.c_ulonglong),
                        ("ullAvailPhys", ctypes.c_ulonglong),
                        ("ullTotalPageFile", ctypes.c_ulonglong),
                        ("ullAvailPageFile", ctypes.c_ulonglong),
                        ("ullTotalVirtual", ctypes.c_ulonglong),
                        ("ullAvailVirtual", ctypes.c_ulonglong),
                        ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]
        ms = _MEMSTAT(); ms.dwLength = ctypes.sizeof(_MEMSTAT)
        if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(ms)):
            hw["ram_gb"] = round(ms.ullTotalPhys/1e9,1)
    except Exception: pass
    hw["cpu_name"] = os.environ.get("PROCESSOR_IDENTIFIER","") or platform.processor()
nv = run(["nvidia-smi","--query-gpu=name,memory.total","--format=csv,noheader,nounits"])
if nv:
    p = nv.split(",")
    hw["gpu_name"] = p[0].strip(); hw["gpu_type"] = "nvidia"
    try: hw["vram_gb"] = round(int(p[1].strip())/1024,1)
    except Exception: pass
print(json.dumps(hw))
PYHW
)

jget() { echo "$HW" | python3 -c "import sys,json; print(json.load(sys.stdin)['$1'])"; }
RAM_GB=$(jget ram_gb); GPU_TYPE=$(jget gpu_type); VRAM_GB=$(jget vram_gb)
APPLE_SI=$(jget apple_silicon); CPU_NAME=$(jget cpu_name); CPU_CORES=$(jget cpu_cores)
GPU_NAME=$(jget gpu_name)

echo ""
echo -e "  RAM:   ${BOLD}${RAM_GB} GB${NC}    CPU: ${BOLD}${CPU_NAME:-unknown} (${CPU_CORES} cores)${NC}"
echo -e "  GPU:   ${BOLD}${GPU_NAME:-none}${NC}${VRAM_GB:+    VRAM: ${BOLD}${VRAM_GB} GB${NC}}"
echo ""
# Round (not truncate) so 5.8 GB reads as 6, not 5, when bucketing hardware.
RAM_INT=$(printf '%.0f' "$RAM_GB" 2>/dev/null || echo 0)
[[ "$RAM_INT" =~ ^[0-9]+$ ]] || RAM_INT=0
if [[ "${RAM_INT:-0}" =~ ^[0-9]+$ ]] && [[ "${RAM_INT:-0}" -lt 32 ]]; then
  warn "RAM is below the recommended 32–48 GB for 32–35B models."
  echo -e "  ${DIM}Guide:  8 GB → 3B models (limited) · 16 GB → 7–14B · 32+ GB → 32–35B${NC}"
  echo ""
fi

# ═════════════════════════════════════════════════════════════════════════════
# 2/5  MODEL SCAN
# ═════════════════════════════════════════════════════════════════════════════
hdr "2/5  Local model scan"
info "Scanning known locations (Ollama, LM Studio, HuggingFace, ~/models)..."

SCAN=$(python3 - "$HOME" << 'PYSCAN'
import sys, os, json, subprocess
from pathlib import Path
home = Path(sys.argv[1])
EXTS = {'.gguf','.ggml','.safetensors','.bin','.pt','.pth','.onnx'}
PATHS = {
 'Ollama': home/'.ollama'/'models',
 'LM Studio': home/'.lmstudio'/'models',
 'LM Studio (macOS)': home/'Library'/'Application Support'/'LM Studio'/'models',
 'HuggingFace': home/'.cache'/'huggingface'/'hub',
 'Jan': home/'.jan'/'models',
 'GPT4All': home/'.local'/'share'/'nomic.ai'/'GPT4All',
 'Loose (~/models)': home/'models',
}
def fmt(b):
    for u in ['B','KB','MB','GB','TB']:
        if b < 1024: return f"{b:.1f}{u}"
        b /= 1024
ollama = []
try:
    r = subprocess.run(['ollama','list'], capture_output=True, text=True, timeout=5)
    if r.returncode == 0:
        ollama = [l.split()[0] for l in r.stdout.strip().split('\n')[1:] if l.split()]
except Exception: pass
models, total = [], 0
for rt, p in PATHS.items():
    if not p.exists(): continue
    for root, dirs, files in os.walk(p):
        if len(Path(root).relative_to(p).parts) > 5: dirs[:] = []; continue
        for fn in files:
            fp = Path(root)/fn
            if fp.suffix.lower() in EXTS:
                try: sz = fp.stat().st_size
                except Exception: continue
                if sz < 100_000_000: continue
                total += sz
                models.append({'path':str(fp),'size':sz,'size_fmt':fmt(sz),
                               'name':fp.stem,'runtime':rt,'ext':fp.suffix.lower()})
models.sort(key=lambda m:-m['size'])
print(json.dumps({'models':models[:50],'ollama':ollama,
                  'count':len(models),'total_fmt':fmt(total) if total else '0B'}))
PYSCAN
)
MODEL_COUNT=$(echo "$SCAN" | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")
TOTAL_FMT=$(echo "$SCAN" | python3 -c "import sys,json; print(json.load(sys.stdin)['total_fmt'])")
OLLAMA_MODELS=$(echo "$SCAN" | python3 -c "import sys,json; print('\n'.join(json.load(sys.stdin)['ollama']))")

echo ""
echo -e "  Model files on disk: ${BOLD}${MODEL_COUNT} (${TOTAL_FMT})${NC}"
if [[ -n "$OLLAMA_MODELS" ]]; then
  echo -e "  Ollama models:"
  while IFS= read -r m; do [[ -n "$m" ]] && echo -e "    ${GREEN}•${NC} $m"; done <<< "$OLLAMA_MODELS"
fi
echo ""

# Inventory report into vault
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/model-inventory-$(date -u +%Y%m%dT%H%M%SZ).md"
python3 - "$REPORT" "$HOME" "$SCAN" << 'PYREP'
import sys, json
out, home, scan = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.loads(scan)
L = ["# Model Inventory","",f"Total: {data['total_fmt']} across {data['count']} files",""]
if data['ollama']:
    L += ["## Ollama models",""] + [f"- `{m}`" for m in data['ollama']] + [""]
L += ["## Files (largest first, top 50)","","| Name | Size | Runtime | Path |","|---|---|---|---|"]
for m in data['models']:
    L.append(f"| {m['name']} | {m['size_fmt']} | {m['runtime']} | `{m['path'].replace(home,'~')}` |")
L += ["", "## Optional housekeeping (review before acting)", "",
      "- The HuggingFace cache can grow large. Inspect it interactively with",
      "  `huggingface-cli scan-cache`, then prune with `huggingface-cli delete-cache`.",
      "- If you prefer one runtime, Ollama can import GGUF files",
      "  (`ollama create <name> -f Modelfile` with `FROM /path/to/model.gguf`).",
      "  This is optional — other tools may depend on their own copies.",
      "  Never bulk-delete model files blindly.", ""]
open(out,"w").write("\n".join(L))
PYREP
ok "Inventory saved: $(basename "$REPORT")"

# ═════════════════════════════════════════════════════════════════════════════
# 3/5  MODEL SELECTION
# ═════════════════════════════════════════════════════════════════════════════
hdr "3/5  Model selection"

SELECTED=$(python3 - "$RAM_GB" "$GPU_TYPE" "$VRAM_GB" "$APPLE_SI" "$OLLAMA_MODELS" << 'PYSEL'
import sys, json
ram, gpu, vram = float(sys.argv[1]), sys.argv[2], float(sys.argv[3])
apple = sys.argv[4] == "True"
ollama = [m for m in sys.argv[5].split('\n') if m.strip()]
if apple: eff = ram - 4
elif gpu == "nvidia" and vram > 0: eff = vram
else: eff = ram * 0.75
# (match-fragment, ollama tag, min effective GB, description)
CAND = [
 ("qwen3:35b","qwen3:35b",28,"Qwen3 35B — strong generalist"),
 ("llama3.3","llama3.3:70b",45,"Llama 3.3 70B — heavy analysis"),
 ("qwen2.5-coder:32b","qwen2.5-coder:32b",26,"Qwen2.5-Coder 32B — coding"),
 ("deepseek-r1:32b","deepseek-r1:32b",26,"DeepSeek-R1 32B — reasoning"),
 ("qwen3:14b","qwen3:14b",12,"Qwen3 14B — balanced"),
 ("qwen3:7b","qwen3:7b",6,"Qwen3 7B — fast"),
 ("llama3.2:3b","llama3.2:3b",3,"Llama3.2 3B — minimal"),
]
# 1) prefer something already in Ollama
for frag, tag, mn, desc in CAND:
    base = frag.split(':')[0]
    for om in ollama:
        if base in om.lower() and "embed" not in om.lower() and eff >= mn:
            print(json.dumps({"model":om,"source":"ollama","desc":desc,
                              "reason":f"already in Ollama; {eff:.0f}GB usable"})); sys.exit()
# 2) recommend a pull
for frag, tag, mn, desc in CAND:
    if eff >= mn:
        print(json.dumps({"model":tag,"source":"pull","desc":desc,
                          "reason":f"best fit for {eff:.0f}GB usable",
                          "pull":f"ollama pull {tag}"})); sys.exit()
print(json.dumps({"model":"llama3.2:3b","source":"pull","desc":"minimal",
                  "reason":"low memory","pull":"ollama pull llama3.2:3b"}))
PYSEL
)
sget() { echo "$SELECTED" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$1',''))"; }
MODEL_TAG=$(sget model); DESC=$(sget desc); REASON=$(sget reason)

# Hermes Agent refuses any model below this context floor.
HERMES_CTX_FLOOR=64000

# ── v5.0 probe helpers ────────────────────────────────────────────────────────
# GET <base>/models on an OpenAI-compatible endpoint; prints one model id per
# line, rc 1 when unreachable/empty. Works for Ollama and OpenRouter alike.
probe_models() {  # probe_models <base_url>
  curl -s --max-time 6 "${1%/}/models" 2>/dev/null | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    ids = [m.get("id", "") for m in (data.get("data") or []) if m.get("id")]
except Exception:
    sys.exit(1)
if not ids:
    sys.exit(1)
print("\n".join(ids))'
}

# Parse the CURRENT top-level model: block out of config.yaml (best effort).
# Sets EXIST_MODEL/EXIST_BASE/EXIST_CTX ("" when absent). Handles both our
# json-quoted scalars and hand-edited plain ones.
EXIST_MODEL=""; EXIST_BASE=""; EXIST_CTX=""
read_existing_model_block() {
  EXIST_MODEL=""; EXIST_BASE=""; EXIST_CTX=""
  [[ -f "$HERMES_CONFIG" ]] || return 0
  local out
  out=$(python3 - "$HERMES_CONFIG" << 'PYREAD'
import sys, json
blk, in_model = {}, False
for ln in open(sys.argv[1]).read().splitlines():
    if ln.startswith("model:"):
        in_model = True; continue
    if in_model:
        if ln.strip() == "":
            continue
        if ln[:1] not in (" ", "\t"):
            break
        s = ln.split(" #", 1)[0].strip()
        if ":" in s:
            k, v = s.split(":", 1)
            blk[k.strip()] = v.strip()
def sc(v):
    v = v.strip()
    try:
        d = json.loads(v)
        if isinstance(d, str):
            return d
    except Exception:
        pass
    if len(v) >= 2 and v[0] == "'" and v[-1] == "'":
        return v[1:-1]    # single-quoted YAML scalar (e.g. base_url: '')
    return v
print(sc(blk.get("default", "")))
print(sc(blk.get("base_url", "")))
print((blk.get("context_length", "").split() or [""])[0])
PYREAD
) || return 0
  EXIST_MODEL=$(printf '%s\n' "$out" | sed -n 1p)
  EXIST_BASE=$(printf '%s\n' "$out" | sed -n 2p)
  EXIST_CTX=$(printf '%s\n' "$out" | sed -n 3p)
}

# Is this machine too weak for a useful local model?
# Heuristic: under ~6 GB RAM, a local model is either too small to be useful
# (0.5b) or too slow (3b). Offer cloud-only instead of forcing a local model.
RAM_INT=$(printf '%.0f' "$RAM_GB" 2>/dev/null || echo 0)  # round, don't truncate
[[ "$RAM_INT" =~ ^[0-9]+$ ]] || RAM_INT=0
WEAK_FOR_LOCAL=false
[[ "$RAM_INT" -lt 6 ]] && WEAK_FOR_LOCAL=true

MODE="local"        # local | remote | cloud | keep
BASE_URL="http://localhost:11434/v1"
REMOTE_HOST=""

# ── v5.0 keep-check: NEVER clobber a model config that provably works ─────────
# The live wound this heals: a WSL machine wired to the central's Ollama over
# LAN ran configure and got silently rewritten to localhost — the working
# setup had to be restored from backup by hand (2026-07-06). Now: if the
# existing block's endpoint ANSWERS, keeping it is the default, and under
# --yes it is never overwritten. An explicit --remote-ollama flag is a stated
# intent to change and skips the keep-check.
if [[ -z "$REMOTE_OLLAMA" ]]; then
  read_existing_model_block
  if [[ -n "$EXIST_MODEL" ]]; then
    # v5.1: --yes NEVER replaces an EXISTING model block — probeable or not.
    # The v5.0 rule ("keep only when the endpoint answers") clobbered a live
    # moa-provider block (base_url empty → unprobeable → rewritten) on the
    # central, 2026-07-07. Unattended runs must be conservative: only an
    # interactive yes or an explicit --remote-ollama flag may replace.
    _answers=false
    [[ "$EXIST_BASE" == http* ]] && probe_models "$EXIST_BASE" >/dev/null 2>&1 && _answers=true
    _baseshow="${EXIST_BASE:-[no base_url — e.g. a moa/aggregate provider]}"
    echo ""
    if $_answers; then
      ok "Existing model config found — and its endpoint answers:"
    else
      info "Existing model config found (endpoint not probeable/answering right now):"
    fi
    echo -e "     ${GREEN}$EXIST_MODEL${NC}  via  ${CYAN}$_baseshow${NC}"
    if $ASSUME_YES; then
      MODE="keep"
      if $_answers; then
        info "Non-interactive: keeping it (a working config is never clobbered under --yes)"
      else
        info "Non-interactive: keeping it — --yes never replaces an existing model block."
        info "To change it: re-run interactively, or pass --remote-ollama=HOST"
      fi
    elif $_answers; then
      ask "Keep this model config? [Y/n]"
      read -r _keep || _keep=""
      [[ "$(lc "${_keep:-y}")" != "n" ]] && MODE="keep"
    else
      ask "Replace it? (endpoint did not answer — it may be off right now) [y/N]"
      read -r _repl || _repl=""
      [[ "$(lc "${_repl:-n}")" == "y" ]] || MODE="keep"
    fi
  fi
fi
if [[ "$MODE" == "keep" ]]; then
  MODEL_TAG="$EXIST_MODEL"
  BASE_URL="$EXIST_BASE"
else
  # ── model source: local / remote (LAN) / cloud ──────────────────────────────
  if [[ -n "$REMOTE_OLLAMA" ]]; then
    MODE="remote"
  elif ! $ASSUME_YES; then
    _def=1; $WEAK_FOR_LOCAL && _def=3
    echo ""
    echo -e "  ${BOLD}Where should Hermes' model run?${NC}"
    if $WEAK_FOR_LOCAL; then
      warn "This machine has ~${RAM_GB} GB RAM — small for a useful local model."
    fi
    _rec1=""; _rec3=""
    [[ "$_def" == 1 ]] && _rec1="   ${GREEN}★ recommended${NC}"
    [[ "$_def" == 3 ]] && _rec3="           ${GREEN}★ recommended for this hardware${NC}"
    echo -e "   1) Local Ollama on this machine${_rec1}"
    echo -e "   2) Ollama on another machine (LAN) — e.g. a Mac mini serving models"
    echo -e "   3) Cloud via OpenRouter${_rec3}"
    ask "Choice [1/2/3] (ENTER = $_def):"
    read -r _modechoice || _modechoice=""
    case "${_modechoice:-$_def}" in
      2) MODE="remote" ;;
      3) MODE="cloud" ;;
      *) MODE="local" ;;
    esac
  else
    $WEAK_FOR_LOCAL && MODE="cloud" || MODE="local"
  fi
fi

echo ""
if [[ "$MODE" == "local" ]]; then
  echo -e "  ${BOLD}Suggested model:${NC} ${GREEN}$MODEL_TAG${NC} — $DESC"
  echo -e "  Reason: $REASON"
fi
echo ""

# Helper: ensure a local Ollama model is actually present; offer to pull if not.
# (Pattern-hunt fix: verify-before-act — never write a model name without
#  confirming it exists, whether suggested OR user-chosen.)
ensure_model_present() {  # ensure_model_present <tag>
  local tag="$1"
  # Exact full name:tag match against ollama's first column — a bare-name prefix
  # (`grep "^${tag%%:*}"`) would treat qwen3:35b as present when only qwen3:7b is.
  if ollama list 2>/dev/null | awk '{print $1}' | grep -qxF "$tag"; then
    return 0   # already there
  fi
  warn "Model '$tag' is not downloaded yet."
  if $ASSUME_YES; then
    warn "Non-interactive — leaving it unpulled; run later: ollama pull $tag"
    return 1
  fi
  ask "Download it now with 'ollama pull $tag'? (Y/n)"
  local dl; read -r dl || dl=""   # EOF-safe: don't let set -e abort on closed stdin
  if [[ "$(lc "${dl:-y}")" != "n" ]]; then
    if ollama pull "$tag"; then ok "Model downloaded: $tag"; return 0
    else warn "Download failed — run later: ollama pull $tag"; return 1; fi
  fi
  warn "Skipped — config will reference '$tag' but it isn't installed."
  return 1
}

# §4.2 model-capability floor: a model can be cheap enough to chat yet too weak
# to DRIVE the agent's search tools — it guesses filenames instead of running
# grep/search, so imported memory looks "missing" though everything is wired.
# Warn (don't block) when a small/cheap model is chosen. Heuristic by tag —
# honest "may be", not a hard rule.
warn_weak_model() {  # warn_weak_model <model_tag>
  # §4.2 floor — fire for: cheap CLOUD tiers (gpt-4o-mini GUESSED filenames, X230
  # live) + tiny local + MID-SIZE LOCAL. The mid-size case is the hard-won one:
  # a 14B local model (qwen3.5) FAKED the search on a real Mac (2026-06-18) — 0
  # real tool calls — while a current cloud model searched correctly. Warn, don't
  # block; large local (32B+) may suffice but is untested here. (No comments inside
  # the case pattern — bash can't parse them between the `\`-continued lines.)
  local t; t="$(lc "$1")"
  case "$t" in
    *mini*|*gpt-3.5*|*haiku-3*|*tinyllama*|*phi-2*|*gemma:2b*|\
    *:0.5b*|*:1b*|*:1.5b*|*:2b*|*:3b*|*-1b*|*-3b*|\
    *qwen3.5*|*gemma4*|*:7b*|*:8b*|*:9b*|*:13b*|*:14b*|*-7b*|*-8b*|*-13b*|*-14b*)
      echo ""
      warn "'$1' may be too weak to reliably USE your memory."
      echo -e "  ${DIM}Weak models don't just answer worse — they FAKE the search: they say"
      echo -e "  \"I couldn't find anything\" WITHOUT ever running grep, so your imported"
      echo -e "  history looks missing even though it is all there."
      echo -e "  Live-tested here: a 14B local model (qwen3.5) did exactly this — 0 real"
      echo -e "  tool calls; a current-generation CLOUD model searched and cited the files."
      echo -e "  For reliable memory recall, prefer a capable cloud model (set an API key in"
      echo -e "  ~/.hermes/.env). Large local models (32B+) may work but aren't proven here.${NC}"
      return 0 ;;
  esac
  return 1
}

if [[ "$MODE" == "cloud" ]]; then
  # Cloud-only: pick a sensible default cloud model, no local download.
  if $ASSUME_YES; then
    MODEL_TAG="openai/gpt-4o-mini"
  else
    ask "Cloud model tag (ENTER = openai/gpt-4o-mini):"
    read -r _cloudmodel || _cloudmodel=""
    MODEL_TAG="${_cloudmodel:-openai/gpt-4o-mini}"
  fi
  BASE_URL="https://openrouter.ai/api/v1"
  ok "Primary model (cloud): $MODEL_TAG"
elif [[ "$MODE" == "remote" ]]; then
  # Remote Ollama over LAN: probe the endpoint, offer ITS model list — never
  # write a base_url that was not seen answering.
  if [[ -n "$REMOTE_OLLAMA" ]]; then
    REMOTE_HOST="$REMOTE_OLLAMA"
  else
    ask "Host/IP of the machine running Ollama (host or host:port):"
    read -r REMOTE_HOST || REMOTE_HOST=""
  fi
  [[ -z "$REMOTE_HOST" ]] && die "Remote Ollama chosen but no host given."
  [[ "$REMOTE_HOST" != *:* ]] && REMOTE_HOST="${REMOTE_HOST}:11434"
  BASE_URL="http://${REMOTE_HOST}/v1"
  info "Probing $BASE_URL ..."
  REMOTE_MODELS=$(probe_models "$BASE_URL") \
    || die "No answer from $BASE_URL — is Ollama running there with OLLAMA_HOST=0.0.0.0?"
  ok "Endpoint answers. Models available there:"
  _i=1
  while IFS= read -r _m; do
    echo "   $_i) $_m"; _i=$((_i+1))
  done <<< "$REMOTE_MODELS"
  # Default: first non-embedding model — an embedder can't chat.
  DEFAULT_REMOTE=$(printf '%s\n' "$REMOTE_MODELS" | grep -vi embed | head -1)
  DEFAULT_REMOTE="${DEFAULT_REMOTE:-$(printf '%s\n' "$REMOTE_MODELS" | head -1)}"
  if $ASSUME_YES; then
    MODEL_TAG="$DEFAULT_REMOTE"
  else
    ask "Model (number or tag, ENTER = $DEFAULT_REMOTE):"
    read -r _rm || _rm=""
    if [[ -z "$_rm" ]]; then
      MODEL_TAG="$DEFAULT_REMOTE"
    elif [[ "$_rm" =~ ^[0-9]+$ ]]; then
      MODEL_TAG=$(printf '%s\n' "$REMOTE_MODELS" | sed -n "${_rm}p")
      [[ -z "$MODEL_TAG" ]] && MODEL_TAG="$DEFAULT_REMOTE"
    else
      MODEL_TAG="$_rm"
    fi
  fi
  ok "Primary model (remote Ollama): $MODEL_TAG"
elif [[ "$MODE" == "local" ]]; then
  # Local path: let the user confirm or override, THEN verify the model exists.
  if ! $ASSUME_YES; then
    ask "Confirm model (ENTER = $MODEL_TAG, or type another Ollama tag):"
    read -r override || override=""
    [[ -n "$override" ]] && MODEL_TAG="$override"
  fi
  BASE_URL="http://localhost:11434/v1"
  ok "Primary model: $MODEL_TAG"
  ensure_model_present "$MODEL_TAG" || true
fi

# §4.2 — warn if the chosen model is likely too weak to drive memory/search tools.
warn_weak_model "$MODEL_TAG" || true

# Context length: never below Hermes' hard floor; scale up with RAM/model max.
# (Pattern-hunt fix: write-against-known-limit — clamp to the floor always.)
if [[ "$MODE" == "keep" ]]; then
  # The kept block's own value — the endpoint already runs with it.
  CTX="${EXIST_CTX:-$HERMES_CTX_FLOOR}"
  [[ "$CTX" =~ ^[0-9]+$ ]] || CTX=$HERMES_CTX_FLOOR
elif [[ "$MODE" == "remote" ]]; then
  # THIS box's RAM says nothing about the serving machine — ask the model
  # itself (/api/show → context_length), clamp to [floor, 128K]: §2.10 says
  # use the model's real capability, but loading a 256K context on the
  # serving box is an OOM trap, not a gift.
  CTX=$(curl -s --max-time 6 -X POST "http://${REMOTE_HOST}/api/show" \
          -H "Content-Type: application/json" \
          -d "{\"model\": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$MODEL_TAG")}" 2>/dev/null \
        | python3 -c '
import sys, json
try:
    mi = (json.load(sys.stdin).get("model_info") or {})
except Exception:
    sys.exit(1)
vals = [v for k, v in mi.items() if k.endswith(".context_length") and isinstance(v, int)]
if not vals:
    sys.exit(1)
print(max(vals))') || CTX=""
  [[ "$CTX" =~ ^[0-9]+$ ]] || CTX=$HERMES_CTX_FLOOR
  [[ "$CTX" -gt 131072 ]] && CTX=131072
  [[ "$CTX" -lt "$HERMES_CTX_FLOOR" ]] && CTX=$HERMES_CTX_FLOOR
else
  CTX=$HERMES_CTX_FLOOR
  [[ "$RAM_INT" -ge 40 ]] 2>/dev/null && CTX=128000
  [[ "$CTX" -lt "$HERMES_CTX_FLOOR" ]] && CTX=$HERMES_CTX_FLOOR
fi

# ═════════════════════════════════════════════════════════════════════════════
# 4/5  HERMES CONFIG + API KEYS (fallback chain)
# ═════════════════════════════════════════════════════════════════════════════
hdr "4/5  Hermes configuration"

echo ""
if [[ "$MODE" == "cloud" ]]; then
  echo -e "  ${BOLD}Cloud-only setup:${NC} Hermes will use ${GREEN}$MODEL_TAG${NC} via OpenRouter."
  echo -e "  An OpenRouter API key is ${BOLD}required${NC} for this to work."
else
  echo -e "  ${BOLD}Fallback chain${NC} — with an OpenRouter key it is ${BOLD}written for real${NC}"
  echo -e "  (hermes fails over automatically on rate-limit/overload/connection errors):"
  echo -e "   1. ${GREEN}Primary${NC}     — $MODEL_TAG"
  echo -e "   2. ${YELLOW}OpenRouter${NC}  — cheap cloud (optional API key)"
  echo -e "  ${DIM}Add more later (e.g. Anthropic): hermes fallback add${NC}"
fi
echo ""
echo -e "  Keys are stored in ${CYAN}$HERMES_ENV${NC} — never in the vault."
# (Pattern-hunt fix: read-preserve — detect an existing key and offer to keep it.)
EXISTING_OR=""
[[ -f "$HERMES_ENV" ]] && EXISTING_OR="$(grep "^OPENROUTER_API_KEY=" "$HERMES_ENV" 2>/dev/null | cut -d= -f2- || true)"  # pipefail-safe: no match must not abort
if [[ -n "$EXISTING_OR" ]]; then
  echo -e "  ${GREEN}An OpenRouter key is already saved${NC} — press ENTER to keep it."
fi
echo -e "  Press ENTER to skip (or keep existing)."
echo ""

if $ASSUME_YES; then OR_KEY=""; AN_KEY=""; else
  ask "OpenRouter API key (paste = set, ENTER = keep/skip; input hidden):"
  read -r -s OR_KEY || OR_KEY=""; echo ""   # EOF-safe: closed stdin must not abort
  ask "Anthropic API key (paste = set, ENTER = keep/skip; input hidden):"
  read -r -s AN_KEY || AN_KEY=""; echo ""   # EOF-safe: closed stdin must not abort
fi
# Confirm a paste landed without echoing the secret.
[[ -n "$OR_KEY" ]] && ok "OpenRouter key received (${#OR_KEY} chars) — looks set."
[[ -n "$AN_KEY" ]] && ok "Anthropic key received (${#AN_KEY} chars) — looks set."
# In cloud mode, a usable key (new or existing) is required — fail clearly if none.
if [[ "$MODE" == "cloud" && -z "$OR_KEY" && -z "$EXISTING_OR" ]]; then
  warn "Cloud-only mode needs an OpenRouter key, but none was given or found."
  warn "Hermes will not be able to reach a model. Re-run and paste a key,"
  warn "or get one at https://openrouter.ai/keys"
fi

mkdir -p "$HERMES_HOME"

# config.yaml — back up and (re)write the model block (skipped in keep mode:
# the whole point of the keep-check is that a WORKING block is left untouched).
if [[ "$MODE" == "keep" ]]; then
  ok "config.yaml model block kept as-is ($MODEL_TAG via $BASE_URL)"
else
if [[ -f "$HERMES_CONFIG" ]]; then
  cp "$HERMES_CONFIG" "${HERMES_CONFIG}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  ok "Backed up existing config.yaml"
fi
python3 - "$HERMES_CONFIG" "$MODEL_TAG" "$CTX" "$MODE" "$BASE_URL" << 'PYCONF'
import sys, os, json
from pathlib import Path
path, model, ctx, mode, base_url = (sys.argv[1], sys.argv[2], int(sys.argv[3]),
                                    sys.argv[4], sys.argv[5])
if mode == "cloud":
    comment = "# cloud via OpenRouter (key in ~/.hermes/.env)"
    extra = ""
else:
    comment = ("# local Ollama (OpenAI-compatible)" if mode == "local"
               else "# remote Ollama over LAN (OpenAI-compatible)")
    # §4.35: a model whose native context is below Hermes' floor must ALSO be
    # told to LOAD at the floor, or Ollama loads it small and Hermes refuses
    # ("runtime context too small") even though context_length passed its check.
    # context_length = what Hermes believes; ollama_num_ctx = what Ollama loads.
    # Applies to local AND remote — the remote server loads with num_ctx too.
    extra = f"  ollama_num_ctx: {ctx}            # force Ollama to load >= Hermes' floor\n"
# QUOTE scalar values so a model tag containing YAML metacharacters (# : { } '
# quotes, leading digits) can never corrupt the file. json.dumps emits a valid
# double-quoted YAML scalar (YAML flow scalars are a JSON superset).
block = (
    "model:\n"
    f"  default: {json.dumps(model)}\n"
    f"  provider: custom            {comment}\n"
    f"  base_url: {json.dumps(base_url)}\n"
    f"  context_length: {ctx}\n"
    + extra
)
p = Path(path)
if p.exists():
    text = p.read_text()
    # Replace the existing top-level `model:` block by walking the file's line
    # structure (not a blind regex splice): drop the `model:` line plus its
    # indented/blank continuation lines up to the next top-level key, then splice
    # our block in. Tolerates arbitrary content inside the old block.
    lines = text.splitlines(keepends=True)
    out, i, replaced = [], 0, False
    while i < len(lines):
        if not replaced and lines[i].startswith("model:"):
            out.append(block)
            i += 1
            while i < len(lines) and (
                lines[i].strip() == "" or lines[i][:1] in (" ", "\t")):
                i += 1
            if i < len(lines):
                out.append("\n")   # keep a blank line before the next section
            replaced = True
        else:
            out.append(lines[i]); i += 1
    text = "".join(out) if replaced else block + "\n" + text
else:
    text = ("# Hermes Agent CLI configuration — written by ai-memory-configure.sh\n"
            "# Env vars in ~/.hermes/.env take precedence over this file.\n\n" + block)
p.parent.mkdir(parents=True, exist_ok=True)
# Atomic write so a failure can never leave a half-written / empty config.
tmp = Path(str(p) + ".tmp")
tmp.write_text(text)
os.replace(str(tmp), str(p))
print("ok")
PYCONF
if [[ "$MODE" == "cloud" ]]; then
  ok "config.yaml → cloud via OpenRouter, model: $MODEL_TAG, ctx: $CTX"
elif [[ "$MODE" == "remote" ]]; then
  ok "config.yaml → remote Ollama ($BASE_URL), model: $MODEL_TAG, ctx: $CTX (+ ollama_num_ctx)"
else
  ok "config.yaml → local Ollama, model: $MODEL_TAG, ctx: $CTX (+ ollama_num_ctx)"
fi
fi   # end keep-mode skip

# §4.35: a green run that writes no config is a bad failure (confirmed on WSL:
# model downloaded, config.yaml never written, Hermes fell back to its default).
# VERIFY the write actually landed by reading it back — fail loudly if not.
verify_config_written() {
  [[ -f "$HERMES_CONFIG" ]] \
    || die "config.yaml was NOT written to $HERMES_CONFIG — Hermes would fall back to its default. Re-run configure."
  # Parse the top-level model: block back out and assert it is WELL-FORMED — the
  # default must be a quoted scalar that decodes to exactly the intended model,
  # context_length must be numeric, and (local) ollama_num_ctx must be numeric.
  # Catches a MALFORMED write (e.g. a tag that corrupted the block), not just a
  # missing default line.
  python3 - "$HERMES_CONFIG" "$MODEL_TAG" "$MODE" << 'PYVERIFY' \
    || die "config.yaml did not pass validation (see message above) — write did not land correctly. Re-run configure."
import sys, json
path, model, mode = sys.argv[1], sys.argv[2], sys.argv[3]
blk, in_model = {}, False
for ln in open(path).read().splitlines():
    if ln.startswith("model:"):
        in_model = True; continue
    if in_model:
        if ln.strip() == "":
            continue
        if ln[:1] not in (" ", "\t"):
            break
        s = ln.strip()
        if ":" in s:
            k, v = s.split(":", 1)
            blk[k.strip()] = v.strip()
if "default" not in blk:
    sys.exit("  config.yaml is missing the model default (%s)." % model)
raw = blk["default"].split(" #", 1)[0].strip()
try:
    val = json.loads(raw)   # our writer emits a json.dumps'd (quoted) scalar
except Exception:
    val = raw               # kept/hand-written blocks may use a plain scalar
if not isinstance(val, str) or val != model:
    sys.exit("  config.yaml default (%r) != intended model (%r)." % (val, model))
cl = blk.get("context_length", "").split()
if (not cl or not cl[0].isdigit()) and mode != "keep":
    sys.exit("  config.yaml is missing a numeric context_length.")
if mode in ("local", "remote"):
    nc = blk.get("ollama_num_ctx", "").split()
    if not nc or not nc[0].isdigit():
        sys.exit("  config.yaml is missing ollama_num_ctx — an Ollama-served model needs it to clear Hermes' 64K floor.")
PYVERIFY
  if [[ "$MODE" == "local" || "$MODE" == "remote" ]]; then
    ok "Verified config.yaml on disk (default == $MODEL_TAG, context_length, ollama_num_ctx)"
  else
    ok "Verified config.yaml on disk (default == $MODEL_TAG, context_length)"
  fi
}
verify_config_written

# .env — only touch our keys, keep the rest
touch "$HERMES_ENV"; chmod 600 "$HERMES_ENV"
set_env() {  # set_env KEY VALUE  (idempotent line replace)
  local k="$1" v="$2"
  grep -q "^${k}=" "$HERMES_ENV" 2>/dev/null \
    && python3 - "$HERMES_ENV" "$k" "$v" << 'PYENV'
import sys, os
p,k,v = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(p).read().splitlines()
out = [f"{k}={v}" if l.startswith(f"{k}=") else l for l in lines]
# Atomic replace (like config.yaml) so a crash can't leave a half-written .env
# that drops other keys; chmod the temp to 600 before swap so perms are preserved.
tmp = p + ".tmp"
with open(tmp, "w") as f:
    f.write("\n".join(out) + "\n")
os.chmod(tmp, 0o600)
os.replace(tmp, p)
PYENV
  [[ -z "$(grep "^${k}=" "$HERMES_ENV" 2>/dev/null)" ]] && echo "${k}=${v}" >> "$HERMES_ENV"
  return 0   # setter succeeds whether it replaced or appended; without this the
             # "key already present" path returns the failed [[ -z ]] test (1) and
             # a bare `set_env …` call trips set -e on every RE-RUN (idempotency bug)
}
[[ -n "$OR_KEY" ]] && { set_env OPENROUTER_API_KEY "$OR_KEY"; ok "OpenRouter key saved"; }
[[ -n "$AN_KEY" ]] && { set_env ANTHROPIC_API_KEY "$AN_KEY"; ok "Anthropic key saved"; }
# Status line must reflect the ACTUAL config — never claim "fully local" in cloud
# mode, and credit an existing key we kept rather than reporting "no keys".
if [[ -z "$OR_KEY" && -z "$AN_KEY" ]]; then
  if [[ "$MODE" == "cloud" ]]; then
    [[ -n "$EXISTING_OR" ]] && info "Keeping existing OpenRouter key — cloud via OpenRouter"
  else
    info "No API keys — Hermes runs fully local"
  fi
fi

# ── v5.0: WRITE the fallback chain the banner has always printed ──────────────
# Hermes reads top-level `fallback_providers` (list of {provider, model,
# base_url?} dicts, own manager: `hermes fallback`) and fails over on
# rate-limit/overload/connection errors. Written only when it can actually
# fire: a non-cloud primary + an OpenRouter key. An existing non-empty chain
# is the user's own — kept untouched (same preserve principle as the model
# block).
if [[ "$MODE" != "cloud" ]] && [[ -n "$OR_KEY" || -n "$EXISTING_OR" ]]; then
  _fb=$(python3 - "$HERMES_CONFIG" << 'PYFB'
import sys, os, re
p = sys.argv[1]
text = open(p).read() if os.path.exists(p) else ""
m = re.search(r"(?m)^fallback_providers:[ \t]*(.*)$", text)
if m:
    inline = m.group(1).split("#", 1)[0].strip()
    if inline not in ("", "[]"):
        print("existing"); sys.exit(0)
    for ln in text[m.end():].splitlines():
        if ln.strip() == "":
            continue
        if ln[:1] in (" ", "\t"):
            print("existing"); sys.exit(0)   # indented entries → a real chain
        break
block = ("fallback_providers:          "
         "# auto-failover on rate-limit/overload/connection errors\n"
         "  - provider: openrouter\n"
         "    model: \"openai/gpt-4o-mini\"\n")
if m:
    # bare/empty key → replace that line with the block
    end = m.end()
    if end < len(text) and text[end] == "\n":
        end += 1
    text = text[:m.start()] + block + text[end:]
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text += "\n" + block
tmp = p + ".tmp"
with open(tmp, "w") as f:
    f.write(text)
os.replace(tmp, p)
print("written")
PYFB
) || _fb=""
  case "$_fb" in
    written)  ok "Fallback chain written: $MODEL_TAG → OpenRouter (openai/gpt-4o-mini)" ;;
    existing) info "fallback_providers already configured — keeping your chain" ;;
    *)        warn "Could not write fallback_providers — add manually: hermes fallback add" ;;
  esac
fi

# ═════════════════════════════════════════════════════════════════════════════
# §4.3 / §4.3.1 import->reachable: make EVERY door to Hermes find the vault
# ═════════════════════════════════════════════════════════════════════════════
# Hermes discovers context (which AGENTS.md it loads) and roots its file/search
# tools at TERMINAL_CWD if set, else the launch directory's os.getcwd()
# (verified in the installed Hermes: system_prompt.py + tool_executor.py both read
# `os.getenv("TERMINAL_CWD") or os.getcwd()`). So a session launched from $HOME or
# from Hermes' own install dir (the web dashboard / gateway do this) won't see the
# vault — it loads the wrong AGENTS.md and searches the wrong tree. The fix is
# THREE layers, weakest→strongest, so reachability never depends on HOW or WHERE
# Hermes was launched (§4.3.1 — the keystone):
#   (1) TERMINAL_CWD in ~/.hermes/.env — picked up by `hermes chat`, which loads
#       .env at startup. NOTE: the web dashboard does NOT load .env into its env
#       (verified on macOS — it pins the chat agent's cwd to its own install dir),
#       so .env alone does not fix the dashboard door — see (2).
#   (2) a shell launcher (`hermes()`) that cd's into the vault AND exports
#       TERMINAL_CWD into the command's environment. The cd handles `hermes chat`;
#       the exported TERMINAL_CWD handles `hermes dashboard`/`gateway`, which ignore
#       cwd and pin to their install dir but copy their process env to the agent.
#   (3) the HANDOVER in ~/.hermes/SOUL.md — ALWAYS loaded, every door, independent
#       of cwd (Hermes injects SOUL.md from HERMES_HOME into every system prompt).
#       It carries ABSOLUTE vault paths + a search-don't-guess routine, so recall
#       works even if (1) and (2) are bypassed. This is the primary mechanism.
set_env TERMINAL_CWD "$VAULT"
ok "TERMINAL_CWD → vault (in .env)"

install_vault_launcher() {
  local primary="$HOME/.bashrc"
  case "${SHELL:-}" in *zsh*) primary="$HOME/.zshrc";; esac
  [[ "${OSTYPE:-}" == darwin* && "${SHELL:-}" != *bash* ]] && primary="$HOME/.zshrc"
  local other; [[ "$primary" == *zshrc ]] && other="$HOME/.bashrc" || other="$HOME/.zshrc"
  local targets=("$primary"); [[ -f "$other" ]] && targets+=("$other")
  local rc
  for rc in "${targets[@]}"; do
    python3 - "$rc" "$VAULT" << 'PYLAUNCH'
import sys, re, shlex
from pathlib import Path
rc, vault = sys.argv[1], sys.argv[2]
# Shell-quote the vault path before it goes into the generated hermes() function
# so a path containing a quote/space/$ etc. can't break out and inject shell into
# .bashrc/.zshrc. shlex.quote emits a single POSIX-safe token.
qv = shlex.quote(vault)
start = "# >>> ai-memory hermes launcher >>>"
end   = "# <<< ai-memory hermes launcher <<<"
block = (
    start + "\n"
    "# Run Hermes rooted at your AI-memory vault so its file tools (search/grep) and\n"
    "# context discovery find your imported history. The cd covers `hermes chat`;\n"
    "# the exported TERMINAL_CWD covers `hermes dashboard`/`gateway`, which ignore\n"
    "# cwd (they pin to their install dir) but copy this env to their chat agent.\n"
    "# The subshell keeps your shell's own directory + environment unchanged.\n"
    "# Added by ai-memory-configure.sh (reachability fix, §4.3 / §4.3.1).\n"
    'hermes() { ( cd ' + qv + ' 2>/dev/null && TERMINAL_CWD=' + qv + ' command hermes "$@" ); }\n'
    + end
)
p = Path(rc)
text = p.read_text() if p.exists() else ""
pat = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
if pat.search(text):
    text = pat.sub(lambda m: block, text)
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text += "\n" + block + "\n"
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(text)
PYLAUNCH
    ok "Vault launcher installed in ${rc/#$HOME/~}"
  done
}
install_vault_launcher

# ── (3) The HANDOVER — ~/.hermes/SOUL.md, the cwd-independent keystone ─────────
# SOUL.md from HERMES_HOME is injected into EVERY Hermes system prompt regardless
# of launch directory or door (shell / dashboard / gateway), loaded fresh each
# message. We write a marker-bounded handover block here — orientation + absolute
# vault paths + a search-don't-guess routine — preserving any persona text the
# user already has. ABSOLUTE paths mean recall does not depend on cwd; the
# "run the tool, don't describe it" wording counters weak models that refuse
# (§4.2 / §4.3.1 points 6-8).
install_soul_handover() {
  local soul="$HERMES_HOME/SOUL.md"
  python3 - "$soul" "$VAULT" << 'PYSOUL'
import sys, re
from pathlib import Path
soul, vault = sys.argv[1], sys.argv[2]
start = "<!-- >>> ai-memory handover >>> -->"
end   = "<!-- <<< ai-memory handover <<< -->"
block = (
    start + "\n"
    "## Your memory (available every session, from any working directory)\n\n"
    "You have a personal memory vault on this machine at:\n"
    "    " + vault + "\n"
    "It holds the user's profile and their imported AI-conversation history, and\n"
    "is your long-term memory — reachable no matter where this session launched.\n\n"
    "CRITICAL — the vault is plain markdown FILES on disk. Reach it ONLY with your\n"
    "FILESYSTEM tools (shell grep / ls / cat / read-file on the paths below). Do\n"
    "NOT use session_search, the memory tool, skill search, or any built-in\n"
    "\"memory\" feature to answer these questions: those look at this agent's OWN\n"
    "session database and skills, NOT the user's vault, so they will falsely come\n"
    "back empty. If you catch yourself calling session_search / a memory tool for a\n"
    "vault question, STOP and run grep on the vault path instead.\n\n"
    "When the user asks what you know, about your memory, or any past topic, BEFORE\n"
    "you say \"I don't have that\", \"I don't remember\", or \"nothing is imported\":\n"
    "1. Read the user's profile:  " + vault + "/entities/user.md\n"
    "2. Find out what history EXISTS. Read the index if it is there:\n"
    "       " + vault + "/05-AI-Sessions/INDEX.md\n"
    "   If that file does NOT exist, LIST the history folder instead — actually run\n"
    "   the tool, and include the sub-folders:\n"
    "       ls -R \"" + vault + "/05-AI-Sessions/\"\n"
    "   NEVER say the history is empty without having listed that folder first. The\n"
    "   sub-folders (claude-web/, claude-code/, openclaw/, lmstudio/, ...) hold the\n"
    "   imported conversations; an absent INDEX.md does NOT mean there is no history.\n"
    "3. For a SPECIFIC topic, run your MEMORY SEARCH TOOL — ONE command that does\n"
    "   the whole multi-term, INDEX-aware search FOR you (so a weak model does not\n"
    "   have to craft the strategy). Actually CALL it, do not just describe it:\n"
    "       bash \"" + vault + "/.tools/ai-memory-search.sh\" \"" + vault + "\" \"<the topic in your own words>\"\n"
    "   It prints the most relevant files ranked, with the answer-bearing lines\n"
    "   already quoted — read the top hit(s) and answer from them. Pass the topic\n"
    "   in plain words (include the brand/model/year if you know them); the tool\n"
    "   handles the variants and never stops at the first empty word.\n"
    "   If that script is missing, FALL BACK to grep and do not give up after one\n"
    "   empty result — try synonyms, English AND the user's language, acronyms,\n"
    "   brand names, model numbers, and scan INDEX.md:\n"
    "       grep -rli \"KEYWORD\" \"" + vault + "/05-AI-Sessions/\"\n"
    "   Either way: distinguish what the USER actually did from options, links or\n"
    "   products merely mentioned in a conversation. Never invent filenames.\n\n"
    "You DO have filesystem and command tools available — use them. If a listing or\n"
    "search returns entries, the memory is there; claiming \"no access\" or \"empty\"\n"
    "without having run the tool — or after only ONE search term — is a mistake.\n"
    + end
)
p = Path(soul)
text = p.read_text() if p.exists() else ""
pat = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
if pat.search(text):
    text = pat.sub(lambda m: block, text)
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text += ("\n" if text else "") + block + "\n"
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(text)
PYSOUL
  ok "Memory handover installed in ${soul/#$HOME/~} (loaded by every Hermes door)"
}
install_soul_handover

# The handover tells the agent to run .tools/ai-memory-search.sh — make sure it
# is actually there. Copy the sibling shipped alongside this script (bundle
# install); if absent, the handover's grep fallback still works.
install_search_tool() {
  local here src dst
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  src="$here/ai-memory-search.sh"
  dst="$VAULT/.tools/ai-memory-search.sh"
  if [[ -f "$src" ]]; then
    mkdir -p "$VAULT/.tools"
    cp "$src" "$dst" && chmod +x "$dst" 2>/dev/null
    ok "Memory-search tool installed → ${dst/#$HOME/~}"
  elif [[ -f "$dst" ]]; then
    ok "Memory-search tool already present in .tools/"
  else
    warn "ai-memory-search.sh not found next to configure — the handover's grep"
    warn "fallback will be used until it is placed in $VAULT/.tools/"
  fi
}
install_search_tool

# ── v5.5: register the memory-search HOOK so recall is model-agnostic ─────────
# Live tests proved small models won't CALL the search tool from SOUL (0/9). A
# hermes `pre_llm_call` shell hook runs the search automatically and injects the
# hits into the user's message, so ANY model — however small — just reads them.
# We add the hook to config.yaml's top-level `hooks:` and flip `hooks_auto_accept`
# to true so a non-interactive/auto-started agent runs it without a TTY consent
# prompt. Targeted edits only — the model/moa block is never touched.
install_search_hook() {
  local cmd="bash $VAULT/.tools/ai-memory-search.sh --hook $VAULT"
  python3 - "$HERMES_CONFIG" "$cmd" << 'PYHOOK'
import sys, os, re
path, cmd = sys.argv[1], sys.argv[2]
if not os.path.exists(path):
    print("nocfg"); sys.exit(0)
text = open(path).read()
changed = False
# 1) hooks_auto_accept: true  (needed for non-TTY runs to fire the hook)
if re.search(r"(?m)^hooks_auto_accept:\s*true\b", text):
    pass
elif re.search(r"(?m)^hooks_auto_accept:", text):
    text = re.sub(r"(?m)^hooks_auto_accept:.*$", "hooks_auto_accept: true", text); changed = True
else:
    text = text.rstrip("\n") + "\nhooks_auto_accept: true\n"; changed = True
# 2) hooks: pre_llm_call — inject our command if not already present.
# Whitespace-normalized so a YAML-re-dumped (line-FOLDED) copy of the same command
# still counts as present — else a re-run duplicates the pre_llm_call key (live bug,
# 2026-07-10: Hermes folds the long command across two lines, `cmd in text` missed it).
if re.sub(r"\s+", " ", cmd) in re.sub(r"\s+", " ", text):
    pass
else:
    block = ("hooks:\n"
             "  pre_llm_call:\n"
             "    - command: " + cmd + "\n"
             "      timeout: 20\n")
    m = re.search(r"(?m)^hooks:\s*(\{\}\s*)?$", text)
    if m and (m.group(1) or "").strip() == "{}":
        # `hooks: {}` → replace that one line with the real block
        text = text[:m.start()] + block + text[m.end():]; changed = True
    elif m:
        # `hooks:` with existing children — splice our pre_llm_call under it
        ins = ("  pre_llm_call:\n"
               "    - command: " + cmd + "\n"
               "      timeout: 20\n")
        text = text[:m.end()] + "\n" + ins + text[m.end():]; changed = True
    else:
        text = text.rstrip("\n") + "\n" + block; changed = True
if changed:
    tmp = path + ".tmp"
    open(tmp, "w").write(text); os.replace(tmp, path)
    print("written")
else:
    print("present")
PYHOOK
}
if [[ -f "$HERMES_CONFIG" ]]; then
  case "$(install_search_hook)" in
    written) ok "Memory hook registered (pre_llm_call → ai-memory-search.sh --hook); auto-recall for ANY model" ;;
    present) ok "Memory hook already registered in config.yaml" ;;
    *)       warn "Could not register the memory hook — add it under hooks: pre_llm_call in ~/.hermes/config.yaml" ;;
  esac
fi

# ── v5.6/v5.7/v5.8: register the self-ingest HOOKS — Hermes' session hooks are the
#    OS-general, FDA-safe trigger that sweeps ALL local agents into the vault ──────
# Closes the loop OS-generally (no per-OS launchd/cron/Task Scheduler): hermes
# `on_session_end` + `on_session_start` hooks run `ingest --local` (v5.8), which
# sweeps every directory/db-based agent store — hermes, claude-code, codex,
# gemini-cli, cursor, aider, lmstudio, open-webui, openclaw — skipping the
# zip/Downloads exporters. So the CC (and any other) sessions synced onto this box
# get archived by the next Hermes session, not by a bespoke per-OS script — general,
# not CC-specific. (Pillar 4's hermes self-ingest is a subset: its state.db is one
# of the swept sources, still cli-skipped so -z automation stays out.) Because that
# ingest is fully idempotent and re-scans everything every fire (measured
# ~0.2s), it is CRASH-RESILIENT two ways:
#   • on_session_end (primary) archives the session that just ended cleanly; and
#     since each fire re-scans everything, it also sweeps up any PRIOR session that
#     died before its own end-hook (crash/kill/power-loss) — it's still in state.db.
#   • on_session_start (v5.7 belt-and-suspenders) covers the one residual edge the
#     end-hook can't: a crash after which you NEVER start another session — the next
#     start you do run archives the orphan. Cost is ~0.2s at startup, negligible.
# (Both run in Hermes' own process, which has macOS Full Disk Access, so writing the
# ~/Documents vault works where launchd would be blocked by TCC.) Targeted edit only;
# model/moa block untouched. Idempotent: an event key already present is left as-is.
install_self_ingest() {
  local cmd="bash $VAULT/.tools/ai-memory-ingest.sh $VAULT --local --yes"
  python3 - "$HERMES_CONFIG" "$cmd" << 'PYSELF'
import sys, os, re
path, cmd = sys.argv[1], sys.argv[2]
if not os.path.exists(path):
    print("nocfg"); sys.exit(0)
text = open(path).read()
changed = False
# 1) hooks_auto_accept: true  (needed for non-TTY runs to fire the hooks)
if re.search(r"(?m)^hooks_auto_accept:\s*true\b", text):
    pass
elif re.search(r"(?m)^hooks_auto_accept:", text):
    text = re.sub(r"(?m)^hooks_auto_accept:.*$", "hooks_auto_accept: true", text); changed = True
else:
    text = text.rstrip("\n") + "\nhooks_auto_accept: true\n"; changed = True
# 2) ensure a `hooks:` block exists (convert `hooks: {}` / append if absent)
if not re.search(r"(?m)^hooks:\s*$", text):
    m0 = re.search(r"(?m)^hooks:\s*\{\}\s*$", text)
    if m0:
        text = text[:m0.start()] + "hooks:" + text[m0.end():]; changed = True
    else:
        text = text.rstrip("\n") + "\nhooks:\n"; changed = True
# 3) inject each event under `hooks:` unless that event key is already present
for ev in ("on_session_end", "on_session_start"):
    if re.search(r"(?m)^  " + re.escape(ev) + r":", text):
        continue  # already configured (ours or the user's) — don't clobber
    ins = ("  " + ev + ":\n"
           "    - command: " + cmd + "\n"
           "      timeout: 180\n")
    m = re.search(r"(?m)^hooks:\s*$", text)
    text = text[:m.end()] + "\n" + ins + text[m.end():]; changed = True
if changed:
    tmp = path + ".tmp"
    open(tmp, "w").write(text); os.replace(tmp, path)
    print("written")
else:
    print("present")
PYSELF
}
if [[ -f "$HERMES_CONFIG" ]]; then
  case "$(install_self_ingest)" in
    written) ok "Self-ingest hooks registered (on_session_end + on_session_start → ingest --local); Hermes' session sweeps ALL local agents into the vault, crash-safe" ;;
    present) ok "Self-ingest hooks already registered in config.yaml" ;;
    *)       warn "Could not register the self-ingest hooks — add them under hooks: on_session_end/on_session_start in ~/.hermes/config.yaml" ;;
  esac
fi

# ai-config.json for resume.sh and other tooling — carries the REAL base_url
# (v5.0 fix: this used to hardcode localhost even for cloud/remote setups, so
# --ai-titles and resume.sh probed the wrong endpoint).
mkdir -p "$MCP_DIR"
python3 - "$CONFIG_FILE" "$MODEL_TAG" "$RAM_GB" "$GPU_TYPE" "$VRAM_GB" "$BASE_URL" "$MODE" << 'PYJSON'
import sys, json, datetime
path, mode = sys.argv[1], sys.argv[7]
provider = "openrouter" if mode == "cloud" else "ollama"
cfg = {
  "configured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
  "hardware": {"ram_gb": float(sys.argv[3]), "gpu_type": sys.argv[4],
               "vram_gb": float(sys.argv[5])},
  "primary": {"provider": provider, "model": sys.argv[2],
              "base_url": sys.argv[6]},
  "hermes_config": "~/.hermes/config.yaml",
}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
PYJSON
ok "ai-config.json written (base_url: $BASE_URL)"

# ═════════════════════════════════════════════════════════════════════════════
# 5/5  VALIDATION
# ═════════════════════════════════════════════════════════════════════════════
hdr "5/5  Validation"

if [[ "$MODE" == "cloud" ]]; then
  if [[ -n "$OR_KEY" || -n "$EXISTING_OR" ]]; then
    ok "Cloud-only: OpenRouter key present, model $MODEL_TAG"
  else
    warn "Cloud-only but no OpenRouter key — Hermes can't reach a model yet"
  fi
elif [[ "$MODE" == "remote" || "$MODE" == "keep" ]]; then
  # Validate the ENDPOINT we actually wrote/kept — local ollama CLI says
  # nothing about a model served on another machine.
  if [[ -z "$BASE_URL" || "$BASE_URL" != http* ]]; then
    info "Kept a non-probeable provider config (no base_url) — endpoint check skipped"
  elif probe_models "$BASE_URL" >/dev/null 2>&1; then
    ok "Model endpoint answering: $BASE_URL"
  else
    warn "Model endpoint not answering right now: $BASE_URL"
  fi
else
  if command -v ollama &>/dev/null && ollama list &>/dev/null 2>&1; then
    ok "Ollama responding"
    if ollama list 2>/dev/null | awk '{print $1}' | grep -qxF "$MODEL_TAG"; then
      ok "Primary model available: $MODEL_TAG"
    else
      warn "Model $MODEL_TAG not in Ollama — run: ollama pull $MODEL_TAG"
    fi
  else
    warn "Ollama not responding — start it: ollama serve"
  fi
fi
command -v hermes &>/dev/null \
  && ok "Hermes command found — start with: hermes chat" \
  || info "Hermes not in PATH yet — open a new terminal, then: hermes chat"
echo -e "  ${DIM}A vault launcher was added to your shell startup so 'hermes' (chat,"
echo -e "  'hermes dashboard', and 'hermes gateway') runs rooted at the vault and can"
echo -e "  see your imported history. Open a NEW terminal (or run: source ~/.bashrc)"
echo -e "  for it to take effect, then start the web UI with: hermes dashboard${NC}"

echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✓  Configuration complete               ${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
echo ""
echo -e "  Hermes config: ${CYAN}$HERMES_CONFIG${NC}"
echo -e "  API keys:      ${CYAN}$HERMES_ENV${NC} (chmod 600)"
echo -e "  Model report:  ${CYAN}$REPORT${NC}"
echo ""
echo -e "${BOLD}Start a session:${NC}  ${CYAN}hermes chat${NC}   or   ${CYAN}bash $VAULT/.tools/resume.sh hermes${NC}"
echo ""
echo -e "${BOLD}Switch models any time — no restart needed:${NC}"
echo -e "  ${CYAN}/model${NC} in a chat          — picker; or ${CYAN}/model <tag>${NC} directly"
echo -e "  ${CYAN}hermes fallback add${NC}       — extend the auto-failover chain"
echo -e "  ${CYAN}hermes dashboard${NC}          — switch from the web UI"
echo -e "  ${DIM}Re-run this script to change the primary (a working config is kept unless"
echo -e "  you say otherwise; --remote-ollama=HOST switches to a LAN model server).${NC}"
INGEST="$VAULT/.tools/ai-memory-ingest.sh"
# The exec-ingest offer requires a REAL interactive terminal: on a closed/piped
# stdin the old default-yes exec'd ingest (whose own old default then exec'd
# hermes) — an unattended run must never end in an interactive takeover
# (same bug class as the ingest v2.15 fix).
if ! $ASSUME_YES && [[ -t 0 ]]; then
  echo -e "${BOLD}Next step — import your AI conversation history.${NC}"
  echo -e "  ${DIM}If your export ZIP is in Downloads, it will be found automatically.${NC}"
  ask "Import history now? [Y/n]"
  read -r _go || _go=""   # EOF-safe: don't let set -e abort on closed stdin
  if [[ "$(lc "${_go:-y}")" != "n" ]] && [[ -f "$INGEST" ]]; then
    echo -e "${CYAN}→ Launching ingest...${NC}"
    exec bash "$INGEST" "$VAULT"
  fi
fi
# ── §B4: the LAST thing on screen is the literal next command ────────────────
echo ""
echo -e "${GREEN}${BOLD}▶ NEXT — import your AI history:${NC}"
echo -e "     ${CYAN}${BOLD}bash $INGEST $VAULT${NC}"
echo ""
