#!/usr/bin/env bash
# =============================================================================
#  ai-memory-configure.sh  v3.1
#  Interactive configuration of the AI Memory Stack
#
#  What it does:
#    1. Analyzes hardware (RAM, GPU, CPU)
#    2. Scans the disk for local AI models (Ollama, LM Studio, HF cache, ...)
#    3. Picks the best model for your hardware
#    4. Writes the real Hermes config (~/.hermes/config.yaml) for local Ollama
#    5. Optionally stores API keys in ~/.hermes/.env (fallback chain)
#    6. Writes ai-config.json + model inventory report into the vault
#
#  Usage: bash ai-memory-configure.sh [path/to/vault]
#  Requires: ai-memory-setup.sh completed first
#  Estimated time: 2–5 min (plus model download if you choose to pull one)
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
    sed -n '2,20p' "$0" | sed 's/^#//'; exit 0 ;;
  -V|--version) echo "ai-memory-configure.sh v3.1"; exit 0 ;;
esac

ASSUME_YES=false
VAULT=""
for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=true ;;
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

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   AI Memory Stack  v3.1 — Configure     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
[[ -d "$VAULT/entities" ]] \
  || die "Vault not found: $VAULT\n  Run setup first: bash ai-memory-setup.sh $VAULT"
info "Vault:        $VAULT"
info "Hermes home:  $HERMES_HOME"
command -v hermes &>/dev/null || [[ -d "$HERMES_HOME" ]] \
  || warn "Hermes not detected — config will be written for when it's installed"
echo ""

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
    try:
        for line in open("/proc/meminfo"):
            if line.startswith("MemTotal"):
                hw["ram_gb"] = round(int(line.split()[1])/1e6,1); break
        for line in open("/proc/cpuinfo"):
            if "model name" in line:
                hw["cpu_name"] = line.split(":",1)[1].strip(); break
    except Exception: pass
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
RAM_INT="${RAM_GB%.*}"
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
echo "$SCAN" | python3 - "$REPORT" "$HOME" << 'PYREP'
import sys, json
data = json.load(sys.stdin)
out, home = sys.argv[1], sys.argv[2]
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
MODEL_TAG=$(sget model); SOURCE=$(sget source); DESC=$(sget desc); REASON=$(sget reason)

echo ""
echo -e "  ${BOLD}Suggested model:${NC} ${GREEN}$MODEL_TAG${NC} — $DESC"
echo -e "  Reason: $REASON"
echo ""

if [[ "$SOURCE" == "pull" ]]; then
  PULL=$(sget pull)
  warn "Model not installed yet."
  if $ASSUME_YES; then dl="n"; else
    ask "Download it now with '$PULL'? (y/N)"
    read -r dl
  fi
  if [[ "$(lc "$dl")" == "y" ]]; then
    $PULL && ok "Model downloaded" || warn "Download failed — run later: $PULL"
  fi
fi

if $ASSUME_YES; then override=""; else
  ask "Confirm model (ENTER = $MODEL_TAG, or type another Ollama tag):"
  read -r override
fi
[[ -n "$override" ]] && MODEL_TAG="$override"
ok "Primary model: $MODEL_TAG"

# Context length recommendation (Ollama defaults are low)
CTX=32000
[[ "${RAM_GB%.*}" -ge 40 ]] 2>/dev/null && CTX=64000
[[ "${RAM_GB%.*}" -ge 90 ]] 2>/dev/null && CTX=128000

# ═════════════════════════════════════════════════════════════════════════════
# 4/5  HERMES CONFIG + API KEYS (fallback chain)
# ═════════════════════════════════════════════════════════════════════════════
hdr "4/5  Hermes configuration"

echo ""
echo -e "  ${BOLD}Fallback chain:${NC}"
echo -e "   1. ${GREEN}Local Ollama${NC}   — $MODEL_TAG (free, offline)"
echo -e "   2. ${YELLOW}OpenRouter${NC}     — cheap cloud models (optional API key)"
echo -e "   3. ${RED}Anthropic${NC}      — Claude (optional API key, most reliable)"
echo ""
echo -e "  Keys are stored in ${CYAN}$HERMES_ENV${NC} — never in the vault."
echo -e "  Press ENTER to skip any key."
echo ""

if $ASSUME_YES; then OR_KEY=""; AN_KEY=""; else
  ask "OpenRouter API key (ENTER = skip):"; read -r -s OR_KEY; echo ""
  ask "Anthropic API key (ENTER = skip):";  read -r -s AN_KEY; echo ""
fi

mkdir -p "$HERMES_HOME"

# config.yaml — back up and (re)write the model block for local Ollama
if [[ -f "$HERMES_CONFIG" ]]; then
  cp "$HERMES_CONFIG" "${HERMES_CONFIG}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  ok "Backed up existing config.yaml"
fi
python3 - "$HERMES_CONFIG" "$MODEL_TAG" "$CTX" << 'PYCONF'
import sys, re
from pathlib import Path
path, model, ctx = sys.argv[1], sys.argv[2], int(sys.argv[3])
block = (
    "model:\n"
    f"  default: {model}\n"
    "  provider: custom            # local Ollama (OpenAI-compatible)\n"
    "  base_url: http://localhost:11434/v1\n"
    f"  context_length: {ctx}\n"
)
p = Path(path)
if p.exists():
    text = p.read_text()
    # Replace existing top-level model: block (up to next top-level key)
    new, n = re.subn(r"(?ms)^model:.*?(?=^\S|\Z)", block, text, count=1)
    text = new if n else block + "\n" + text
else:
    text = ("# Hermes Agent CLI configuration — written by ai-memory-configure.sh\n"
            "# Env vars in ~/.hermes/.env take precedence over this file.\n\n" + block)
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(text)
print("ok")
PYCONF
ok "config.yaml → provider: custom, base_url: http://localhost:11434/v1, model: $MODEL_TAG"

# .env — only touch our keys, keep the rest
touch "$HERMES_ENV"; chmod 600 "$HERMES_ENV"
set_env() {  # set_env KEY VALUE  (idempotent line replace)
  local k="$1" v="$2"
  grep -q "^${k}=" "$HERMES_ENV" 2>/dev/null \
    && python3 - "$HERMES_ENV" "$k" "$v" << 'PYENV'
import sys
p,k,v = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(p).read().splitlines()
out = [f"{k}={v}" if l.startswith(f"{k}=") else l for l in lines]
open(p,"w").write("\n".join(out) + "\n")
PYENV
  [[ -z "$(grep "^${k}=" "$HERMES_ENV" 2>/dev/null)" ]] && echo "${k}=${v}" >> "$HERMES_ENV"
}
[[ -n "$OR_KEY" ]] && { set_env OPENROUTER_API_KEY "$OR_KEY"; ok "OpenRouter key saved"; }
[[ -n "$AN_KEY" ]] && { set_env ANTHROPIC_API_KEY "$AN_KEY"; ok "Anthropic key saved"; }
[[ -z "$OR_KEY" && -z "$AN_KEY" ]] && info "No API keys — Hermes runs fully local"

# ai-config.json for resume.sh and other tooling
mkdir -p "$MCP_DIR"
python3 - "$CONFIG_FILE" "$MODEL_TAG" "$RAM_GB" "$GPU_TYPE" "$VRAM_GB" << 'PYJSON'
import sys, json, datetime
path = sys.argv[1]
cfg = {
  "configured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
  "hardware": {"ram_gb": float(sys.argv[3]), "gpu_type": sys.argv[4],
               "vram_gb": float(sys.argv[5])},
  "primary": {"provider": "ollama", "model": sys.argv[2],
              "base_url": "http://localhost:11434/v1"},
  "hermes_config": "~/.hermes/config.yaml",
}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
PYJSON
ok "ai-config.json written"

# ═════════════════════════════════════════════════════════════════════════════
# 5/5  VALIDATION
# ═════════════════════════════════════════════════════════════════════════════
hdr "5/5  Validation"

if command -v ollama &>/dev/null && ollama list &>/dev/null 2>&1; then
  ok "Ollama responding"
  if ollama list 2>/dev/null | grep -q "${MODEL_TAG%%:*}"; then
    ok "Primary model available: $MODEL_TAG"
  else
    warn "Model $MODEL_TAG not in Ollama — run: ollama pull $MODEL_TAG"
  fi
else
  warn "Ollama not responding — start it: ollama serve"
fi
command -v hermes &>/dev/null \
  && ok "Hermes command found — start with: hermes chat" \
  || info "Hermes not in PATH yet — open a new terminal, then: hermes chat"

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
echo -e "${BOLD}Next step — import your history:${NC}"
echo -e "  ${CYAN}bash $VAULT/.tools/ai-memory-ingest.sh $VAULT${NC}"
echo ""
