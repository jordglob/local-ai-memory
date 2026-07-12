#!/usr/bin/env bash
# =============================================================================
#  ai-memory-configure.sh  v5.13
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
#  v5.13: installs lib/ (the python engines aimem_common/ingest/search.py) into
#         <vault>/.tools/lib alongside the ingest/search launchers — since
#         ingest v3.0 / search v2.0 the .sh files are thin launchers and the
#         hooks' .tools copies need the engine next to them.
#  v5.12: the "start a session" pointer names the mux cockpit (bash
#         ai-memory-mux.sh — back in the family as the standard interface)
#         with `hermes chat` as the no-tmux alternative.
#  v5.11: prompts read /dev/tty when stdin is a terminal OR a pipe (the
#         bootstrap curl|bash chain) — redirected-stdin runs (tests, cron) stay
#         non-interactive exactly as before; the three config.yaml editors are
#         ONE pass (hooks_auto_accept flipped + announced once); a model pull
#         states its approx download size and checks free disk first; the
#         weak-model warning is a calibrated note when the model IS configure's
#         own recommendation; the Anthropic key prompt is gone from the default
#         flow (nothing in the default config used it); pasted keys are
#         sanity-checked (whitespace/prefix), never stored silently mangled;
#         the ingest handoff is a plain call (exec killed the trap class).
#  v5.10: ships two validated MoA presets for /moa — `balanced` (cheap, family-
#         diverse cloud references + a cheap-but-strong glm-5.2 aggregator; the
#         2026-07-10 testing showed MoA's recall lift comes from the references,
#         not the aggregator, so opus-as-aggregator is wasted spend) and `lokal`
#         (qwen3.6 + gemma4, $0 offline fallback). Idempotent, non-clobbering.
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

# ── Prompt source (v5.11) ─────────────────────────────────────────────────────
# setup reads its prompts from /dev/tty; configure must too, because the guided
# chain can arrive through a PIPE (bootstrap curl|bash → setup → configure), where
# stdin is the exhausted pipe rather than the keyboard. BUT a redirected non-pipe
# stdin (tests/cron run `configure < /dev/null`) must stay non-interactive exactly
# as before — so /dev/tty is used only when stdin is a terminal or a pipe, and
# every read otherwise falls back to plain stdin (EOF-safe, defaults apply).
# Probe by OPENING /dev/tty: the node can exist without a controlling terminal.
CAN_PROMPT=false
if { : >/dev/tty; } 2>/dev/null && { [[ -t 0 ]] || [[ -p /dev/fd/0 ]]; }; then
  CAN_PROMPT=true
fi
prompt_read() {  # prompt_read [read-flags] VAR — read a reply from the right source
  if $CAN_PROMPT; then read "$@" < /dev/tty; else read "$@"; fi
}

# Single source of truth for the version — the --version flag and the banner
# both read $VERSION, so they can never drift from each other again.
VERSION="5.13"

case "${1:-}" in
  -h|--help)
    sed -n '2,25p' "$0" | sed 's/^#//'; exit 0 ;;
  -V|--version) echo "ai-memory-configure.sh v$VERSION"; exit 0 ;;
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
echo -e "${BOLD}║   AI Memory Stack  v$VERSION — Configure      ║${NC}"
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
# v5.11: remember what WE recommended for this hardware, so the capability
# advice further down can tell "our own recommendation" from "user's override".
SUGGESTED_TAG="$MODEL_TAG"
CLOUD_DEFAULT_MODEL="openai/gpt-4o-mini"

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
      prompt_read -r _keep || _keep=""
      [[ "$(lc "${_keep:-y}")" != "n" ]] && MODE="keep"
    else
      ask "Replace it? (endpoint did not answer — it may be off right now) [y/N]"
      prompt_read -r _repl || _repl=""
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
    prompt_read -r _modechoice || _modechoice=""
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

# Approximate download size (GB) for the tags configure itself recommends
# (the CAND table above) — keep the two lists in sync. Anything else gets the
# honest fallback "several GB" rather than a made-up number.
model_download_gb() {  # model_download_gb <tag> → GB or "" (unknown)
  case "$1" in
    llama3.3:70b)                       echo 40 ;;
    qwen3:35b)                          echo 22 ;;
    qwen2.5-coder:32b|deepseek-r1:32b)  echo 20 ;;
    qwen3:14b)                          echo 9  ;;
    qwen3:7b)                           echo 5  ;;
    llama3.2:3b)                        echo 2  ;;
    *)                                  echo "" ;;
  esac
}

# Helper: ensure a local Ollama model is actually present; offer to pull if not.
# (Pattern-hunt fix: verify-before-act — never write a model name without
#  confirming it exists, whether suggested OR user-chosen.)
# v5.11: state the approximate download size and check free disk BEFORE offering
# the pull (same df -Pk read as setup's check) — and when disk is tight, warn
# and do NOT default to yes.
ensure_model_present() {  # ensure_model_present <tag>
  local tag="$1"
  # Exact full name:tag match against ollama's first column — a bare-name prefix
  # (`grep "^${tag%%:*}"`) would treat qwen3:35b as present when only qwen3:7b is.
  if ollama list 2>/dev/null | awk '{print $1}' | grep -qxF "$tag"; then
    return 0   # already there
  fi
  local gb size_label free_gb
  gb="$(model_download_gb "$tag")"
  size_label="${gb:+~${gb} GB}"; size_label="${size_label:-several GB}"
  # POSIX df, like setup's check_disk_space: column 4 of df -Pk = available KB.
  free_gb=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2{print int($4/1024/1024)}')
  warn "Model '$tag' is not downloaded yet."
  echo -e "  ${DIM}Download size: ${size_label} · free disk: ${free_gb:-unknown} GB${NC}"
  if $ASSUME_YES; then
    warn "Non-interactive — leaving it unpulled; run later: ollama pull $tag"
    return 1
  fi
  local _def=y _hint="(Y/n)"
  if [[ -n "$gb" && -n "$free_gb" ]] && [[ "$free_gb" -lt $(( gb + 5 )) ]]; then
    warn "Free disk (${free_gb} GB) is tight for a ${size_label} download (+ headroom)."
    warn "Free up space first, or choose a smaller model."
    _def=n; _hint="(y/N)"
  fi
  ask "Download it now with 'ollama pull $tag'? $_hint"
  local dl; prompt_read -r dl || dl=""   # EOF-safe: don't let set -e abort on closed stdin
  if [[ "$(lc "${dl:-$_def}")" != "n" ]]; then
    if ollama pull "$tag"; then ok "Model downloaded: $tag"; return 0
    else warn "Download failed — run later: ollama pull $tag"; return 1; fi
  fi
  warn "Skipped — config will reference '$tag' but it isn't installed."
  return 1
}

# §4.2 model-capability floor: a model can be cheap enough to chat yet too weak
# to DRIVE the agent's search tools — it guesses filenames instead of running
# grep/search, so imported memory looks "missing" though everything is wired.
# Heuristic by tag — honest "may be", not a hard rule.
is_weak_model_tag() {  # is_weak_model_tag <model_tag> → 0 when likely too weak
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
      return 0 ;;
  esac
  return 1
}

# The STRONG warning — for a weak model the user chose AGAINST the recommendation.
warn_weak_model() {  # warn_weak_model <model_tag>
  echo ""
  warn "'$1' may be too weak to reliably USE your memory."
  echo -e "  ${DIM}Weak models don't just answer worse — they FAKE the search: they say"
  echo -e "  \"I couldn't find anything\" WITHOUT ever running grep, so your imported"
  echo -e "  history looks missing even though it is all there."
  echo -e "  Live-tested here: a 14B local model (qwen3.5) did exactly this — 0 real"
  echo -e "  tool calls; a current-generation CLOUD model searched and cited the files."
  echo -e "  For reliable memory recall, prefer a capable cloud model (set an API key in"
  echo -e "  ~/.hermes/.env). Large local models (32B+) may work but aren't proven here.${NC}"
}

# The CALIBRATED note — same capability facts, but for a model configure ITSELF
# just recommended for this hardware (v5.11: telling a beginner that our own
# 16 GB recommendation "FAKES the search" contradicted the advice one screen up).
note_recommended_ceiling() {  # note_recommended_ceiling <model_tag>
  echo ""
  if [[ "$MODE" == "cloud" ]]; then
    info "Capability note: '$1' is this setup's cloud default — cheap and fine for chat."
    echo -e "  ${DIM}The automatic search hook injects vault hits into every turn, so memory"
    echo -e "  recall works even here — but for heavier digging (multi-step follow-up"
    echo -e "  searches) a stronger cloud model is more reliable. Switch any time with"
    echo -e "  /model in a chat — no reconfigure needed.${NC}"
  else
    info "Capability note: on this hardware, '$1' is the honest ceiling for a local model."
    echo -e "  ${DIM}Memory recall works — the automatic search hook runs the vault search and"
    echo -e "  injects the hits into every turn, so even this model reads your memory —"
    echo -e "  but it is less reliable at follow-up digging than a 32B+/cloud model."
    echo -e "  Add an OpenRouter key (in ~/.hermes/.env) any time to raise the ceiling"
    echo -e "  without reconfiguring.${NC}"
  fi
}

if [[ "$MODE" == "cloud" ]]; then
  # Cloud-only: pick a sensible default cloud model, no local download.
  if $ASSUME_YES; then
    MODEL_TAG="$CLOUD_DEFAULT_MODEL"
  else
    ask "Cloud model tag (ENTER = $CLOUD_DEFAULT_MODEL):"
    prompt_read -r _cloudmodel || _cloudmodel=""
    MODEL_TAG="${_cloudmodel:-$CLOUD_DEFAULT_MODEL}"
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
    prompt_read -r REMOTE_HOST || REMOTE_HOST=""
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
    prompt_read -r _rm || _rm=""
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
    prompt_read -r override || override=""
    [[ -n "$override" ]] && MODEL_TAG="$override"
  fi
  BASE_URL="http://localhost:11434/v1"
  ok "Primary model: $MODEL_TAG"
  ensure_model_present "$MODEL_TAG" || true
fi

# §4.2 — capability advice for the chosen model. Coherent with our own advice
# (v5.11): when the weak-ish tag IS configure's own recommendation for the
# detected hardware (local suggestion kept, or the cloud default), print the
# calibrated note; the scary warning fires only for a model the user chose
# against the recommendation (or a kept/hand-written config we didn't pick).
if is_weak_model_tag "$MODEL_TAG"; then
  _own_rec=false
  [[ "$MODE" == "local" && "$MODEL_TAG" == "$SUGGESTED_TAG" ]] && _own_rec=true
  [[ "$MODE" == "cloud" && "$MODEL_TAG" == "$CLOUD_DEFAULT_MODEL" ]] && _own_rec=true
  if $_own_rec; then
    note_recommended_ceiling "$MODEL_TAG"
  else
    warn_weak_model "$MODEL_TAG"
  fi
fi

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

# v5.11: only the OpenRouter key is asked for — nothing in the default config
# uses an Anthropic key (the fallback chain is OpenRouter-only). Add other
# providers later with `hermes fallback add` + a key in ~/.hermes/.env.
if $ASSUME_YES; then OR_KEY=""; else
  ask "OpenRouter API key (paste = set, ENTER = keep/skip; input hidden):"
  prompt_read -r -s OR_KEY || OR_KEY=""; echo ""   # EOF-safe: closed stdin must not abort
fi
# v5.11 paste sanity: trim surrounding whitespace (terminal pastes often add a
# trailing newline/space); refuse a key with INNER whitespace — that is a
# mangled multi-line paste and must never be stored silently broken.
if [[ -n "$OR_KEY" ]]; then
  OR_KEY="${OR_KEY#"${OR_KEY%%[![:space:]]*}"}"   # ltrim
  OR_KEY="${OR_KEY%"${OR_KEY##*[![:space:]]}"}"   # rtrim
  if [[ "$OR_KEY" == *[[:space:]]* ]]; then
    warn "That key contains whitespace mid-string — looks like a mangled paste; NOT saved."
    warn "Re-run configure and paste it as one line (OpenRouter keys look like sk-or-…)."
    OR_KEY=""
  elif [[ "$OR_KEY" != sk-or-* ]]; then
    warn "OpenRouter keys normally start with 'sk-or-' — saving what you pasted, but double-check it."
  fi
fi
# Confirm a paste landed without echoing the secret.
[[ -n "$OR_KEY" ]] && ok "OpenRouter key received (${#OR_KEY} chars) — looks set."
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
# Status line must reflect the ACTUAL config — never claim "fully local" in cloud
# mode, and credit an existing key we kept rather than reporting "no keys".
if [[ -z "$OR_KEY" ]]; then
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

# v5.9: the self-ingest hook runs $VAULT/.tools/ai-memory-ingest.sh — configure must
# install/REFRESH it there too, else the hook fires a stale copy (live 2026-07-10: an
# old .tools ingest without --local made `hooks test` exit 2). Same shape as the
# search tool: prefer the sibling shipped next to configure; keep an existing copy.
install_ingest_tool() {
  local here src dst
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  src="$here/ai-memory-ingest.sh"
  dst="$VAULT/.tools/ai-memory-ingest.sh"
  if [[ -f "$src" ]]; then
    mkdir -p "$VAULT/.tools"
    cp "$src" "$dst" && chmod +x "$dst" 2>/dev/null
    ok "Ingest tool installed → ${dst/#$HOME/~} (self-ingest hook runs this copy)"
  elif [[ -f "$dst" ]]; then
    ok "Ingest tool already present in .tools/"
  else
    warn "ai-memory-ingest.sh not found next to configure — the self-ingest hook"
    warn "will fail until it is placed in $VAULT/.tools/ (re-run setup or bundle install)"
  fi
}
install_ingest_tool

# v5.13: ingest + search are thin launchers since ingest v3.0 / search v2.0 —
# their python engines live in lib/ (aimem_common/aimem_ingest/aimem_search.py)
# and MUST be installed alongside the .tools copies, or the launchers (and the
# self-ingest + pre_llm_call hooks that run them) die with a missing-engine
# error. Same source preference as the tools themselves: the lib/ shipped next
# to this script; keep an existing .tools/lib if no source is available.
install_lib_dir() {
  local here srcdir dstdir f dst copied=0
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  srcdir="$here/lib"
  dstdir="$VAULT/.tools/lib"
  if [[ -d "$srcdir" ]] && ls "$srcdir"/aimem_*.py >/dev/null 2>&1; then
    mkdir -p "$dstdir"
    for f in "$srcdir"/aimem_*.py; do
      dst="$dstdir/$(basename "$f")"
      if [[ "$f" != "$dst" ]] && ! cmp -s "$f" "$dst" 2>/dev/null; then
        cp "$f" "$dst" && copied=$(( copied + 1 ))
      fi
    done
    if [[ $copied -gt 0 ]]; then
      ok "Python engine (lib/) installed → ${dstdir/#$HOME/~} ($copied file(s))"
    else
      ok "Python engine (lib/) already current in .tools/lib/"
    fi
  elif ls "$dstdir"/aimem_*.py >/dev/null 2>&1; then
    ok "Python engine already present in .tools/lib/"
  else
    warn "lib/ (python engine) not found next to configure — the .tools ingest/"
    warn "search launchers will fail until lib/*.py lands in $dstdir (re-run setup)"
  fi
}
install_lib_dir

# ── v5.11: ALL managed config.yaml edits in ONE pass ──────────────────────────
# The three separate regex editors (search hook v5.5, self-ingest hooks
# v5.6-v5.8, MoA presets v5.10) were this project's most recurrent live-bug
# class (the v5.1 and v5.9 incidents in the header) — three programs each
# re-reading and re-writing the same file with their own idempotency rules and
# their own silent hooks_auto_accept flip. They are now ONE embedded program
# that reads config.yaml once, applies every managed edit, and writes once
# (atomically). Deliberately still LINE-STRUCTURED edits, not a YAML re-dump: a
# parser round-trip would need PyYAML (not guaranteed on a fresh box) and would
# drop the user's comments and ordering. What it manages:
#   • hooks_auto_accept: true — flipped in ONE place and ANNOUNCED once (needed
#     so a non-TTY/auto-started agent runs hooks without a TTY consent prompt;
#     previously flipped silently in two editors).
#   • pre_llm_call → ai-memory-search.sh --hook (v5.5): model-agnostic recall —
#     small models won't CALL the search tool from SOUL (0/9 live), so the hook
#     runs it and injects hits into the user message. Presence check is
#     whitespace-NORMALIZED (v5.9: Hermes re-dumps config.yaml with the long
#     command line-FOLDED; an exact-substring check missed it → duplicate key).
#   • on_session_end + on_session_start → ingest --local (v5.6/v5.7/v5.8): the
#     OS-general, FDA-safe sweep of ALL local agent stores into the vault,
#     crash-resilient (each fire re-scans everything, ~0.2s). Keyed on the
#     EVENT NAME (fold-proof); an event the user configured is never touched.
#   • MoA presets balanced + lokal (v5.10) — a preset is added only when its
#     NAME is absent, default_preset only when unset; user presets are kept.
# The model / fallback_providers blocks written earlier in this run are never
# touched here.
apply_hermes_config_edits() {
  local search_cmd="bash $VAULT/.tools/ai-memory-search.sh --hook $VAULT"
  local ingest_cmd="bash $VAULT/.tools/ai-memory-ingest.sh $VAULT --local --yes"
  python3 - "$HERMES_CONFIG" "$search_cmd" "$ingest_cmd" << 'PYEDITS'
import sys, os, re
path, search_cmd, ingest_cmd = sys.argv[1], sys.argv[2], sys.argv[3]
if not os.path.exists(path):
    print("nocfg"); sys.exit(0)
orig = open(path).read()
text = orig
out = []

# 1) hooks_auto_accept: true — the ONE place this is flipped.
if re.search(r"(?m)^hooks_auto_accept:\s*true\b", text):
    out.append("autoaccept=present")
elif re.search(r"(?m)^hooks_auto_accept:", text):
    text = re.sub(r"(?m)^hooks_auto_accept:.*$", "hooks_auto_accept: true", text)
    out.append("autoaccept=flipped")
else:
    text = text.rstrip("\n") + "\nhooks_auto_accept: true\n"
    out.append("autoaccept=flipped")

# 2) ensure a top-level `hooks:` block exists (convert `hooks: {}`; append if absent)
if not re.search(r"(?m)^hooks:\s*$", text):
    m0 = re.search(r"(?m)^hooks:\s*\{\}\s*$", text)
    if m0:
        text = text[:m0.start()] + "hooks:" + text[m0.end():]
    else:
        text = text.rstrip("\n") + "\nhooks:\n"

def splice_under_hooks(text, ins):
    m = re.search(r"(?m)^hooks:\s*$", text)
    return text[:m.end()] + "\n" + ins + text[m.end():]

# 3) memory-search hook — whitespace-normalized presence check (v5.9) so a
#    line-folded copy of the same command still counts as present.
if re.sub(r"\s+", " ", search_cmd) in re.sub(r"\s+", " ", text):
    out.append("search=present")
else:
    text = splice_under_hooks(text,
        "  pre_llm_call:\n"
        "    - command: " + search_cmd + "\n"
        "      timeout: 20\n")
    out.append("search=written")

# 4) self-ingest hooks — keyed on the event name (ours or the user's = present)
ingest_state = "present"
for ev in ("on_session_end", "on_session_start"):
    if re.search(r"(?m)^  " + re.escape(ev) + r":", text):
        continue
    text = splice_under_hooks(text,
        "  " + ev + ":\n"
        "    - command: " + ingest_cmd + "\n"
        "      timeout: 180\n")
    ingest_state = "written"
out.append("ingest=" + ingest_state)

# 5) MoA presets — add only what is absent, never touch the user's own
balanced = ("    balanced:\n"
            "      reference_models:\n"
            "        - provider: openrouter\n          model: nex-agi/nex-n2-mini\n"
            "        - provider: openrouter\n          model: z-ai/glm-4.7-flash\n"
            "        - provider: openrouter\n          model: anthropic/claude-haiku-4.5\n"
            "      aggregator:\n        provider: openrouter\n        model: z-ai/glm-5.2\n")
lokal    = ("    lokal:\n"
            "      reference_models:\n"
            "        - provider: ollama-launch\n          model: qwen3.6:35b\n"
            "        - provider: ollama-launch\n          model: gemma4:12b\n"
            "      aggregator:\n        provider: ollama-launch\n        model: qwen3.6:35b\n")
moa_state = "present"
if not re.search(r"(?m)^moa:\s*$", text):
    text = text.rstrip("\n") + "\nmoa:\n  default_preset: balanced\n  presets:\n" + balanced + lokal
    moa_state = "written"
else:
    if not re.search(r"(?m)^  presets:\s*$", text):
        text = re.sub(r"(?m)^(moa:[ \t]*\n)", r"\1  presets:\n", text, count=1); moa_state = "written"
    for name, block in (("balanced", balanced), ("lokal", lokal)):
        if not re.search(r"(?m)^    " + re.escape(name) + r":\s*$", text):
            text = re.sub(r"(?m)^(  presets:[ \t]*\n)", r"\1" + block, text, count=1); moa_state = "written"
    if not re.search(r"(?m)^  default_preset:", text):
        text = re.sub(r"(?m)^(moa:[ \t]*\n)", r"\1  default_preset: balanced\n", text, count=1); moa_state = "written"
out.append("moa=" + moa_state)

if text != orig:
    tmp = path + ".tmp"
    open(tmp, "w").write(text); os.replace(tmp, path)   # atomic, like the model block
print(" ".join(out))
PYEDITS
}
if [[ -f "$HERMES_CONFIG" ]]; then
  _edits="$(apply_hermes_config_edits)" || _edits=""
  if [[ "$_edits" != *"="* ]]; then
    warn "Could not apply the managed config.yaml edits — add them manually in ~/.hermes/config.yaml"
    warn "  (hooks: pre_llm_call / on_session_end / on_session_start, moa: presets)"
  else
    case "$_edits" in
      *autoaccept=flipped*)
        info "hooks_auto_accept → true in config.yaml (hooks run without a per-call consent prompt — required for non-TTY / auto-started sessions)" ;;
    esac
    case "$_edits" in
      *search=written*) ok "Memory hook registered (pre_llm_call → ai-memory-search.sh --hook); auto-recall for ANY model" ;;
      *search=present*) ok "Memory hook already registered in config.yaml" ;;
    esac
    case "$_edits" in
      *ingest=written*) ok "Self-ingest hooks registered (on_session_end + on_session_start → ingest --local); Hermes' session hooks sweep ALL local agents into the vault, crash-safe" ;;
      *ingest=present*) ok "Self-ingest hooks already registered in config.yaml" ;;
    esac
    case "$_edits" in
      *moa=written*) ok "MoA presets installed (balanced = cheap diverse cloud panel; lokal = \$0 offline) — invoke with /moa" ;;
      *moa=present*) ok "MoA presets already present in config.yaml" ;;
    esac
  fi
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
echo -e "${BOLD}Start a session:${NC}  ${CYAN}bash $VAULT/.tools/ai-memory-mux.sh${NC}   ${DIM}(the standard way in —"
echo -e "  a mouse-friendly two-pane tmux cockpit; no tmux? plain ${NC}${CYAN}hermes chat${NC}${DIM} works too)${NC}"
echo ""
echo -e "${BOLD}Switch models any time — no restart needed:${NC}"
echo -e "  ${CYAN}/model${NC} in a chat          — picker; or ${CYAN}/model <tag>${NC} directly"
echo -e "  ${CYAN}hermes fallback add${NC}       — extend the auto-failover chain"
echo -e "  ${CYAN}hermes dashboard${NC}          — switch from the web UI"
echo -e "  ${DIM}Re-run this script to change the primary (a working config is kept unless"
echo -e "  you say otherwise; --remote-ollama=HOST switches to a LAN model server).${NC}"
INGEST="$VAULT/.tools/ai-memory-ingest.sh"
# The ingest offer requires a promptable session ($CAN_PROMPT: a real terminal,
# or the bootstrap pipe with /dev/tty available — v5.11): on a closed/redirected
# stdin the old default-yes exec'd ingest (whose own old default then exec'd
# hermes) — an unattended run must never end in an interactive takeover
# (same bug class as the ingest v2.15 fix).
if ! $ASSUME_YES && $CAN_PROMPT; then
  echo -e "${BOLD}Next step — import your AI conversation history.${NC}"
  echo -e "  ${DIM}If your export ZIP is in Downloads, it will be found automatically.${NC}"
  ask "Import history now? [Y/n]"
  prompt_read -r _go || _go=""   # EOF-safe: don't let set -e abort on closed stdin
  if [[ "$(lc "${_go:-y}")" != "n" ]] && [[ -f "$INGEST" ]]; then
    echo -e "${CYAN}→ Launching ingest...${NC}"
    # Plain call, NOT `exec` (v5.11): exec skips any EXIT trap in the caller
    # chain and detaches ingest from this script's exit status for no gain —
    # the whole exec class was retired across the family this round.
    _rc=0; bash "$INGEST" "$VAULT" || _rc=$?
    exit "$_rc"
  fi
fi
# ── §B4: the LAST thing on screen is the literal next command ────────────────
echo ""
echo -e "${GREEN}${BOLD}▶ NEXT — import your AI history:${NC}"
echo -e "     ${CYAN}${BOLD}bash $INGEST $VAULT${NC}"
echo ""
