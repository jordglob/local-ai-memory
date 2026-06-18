#!/usr/bin/env bash
# =============================================================================
#  ai-memory-configure.sh  v4.12
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
  -V|--version) echo "ai-memory-configure.sh v4.12"; exit 0 ;;
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
# §4.12 migration-awareness: remember whether a Hermes config existed BEFORE we
# (re)write one — a populated vault + no prior config = a vault moved onto this box.
CONFIG_PREEXISTED=false; [[ -f "$HERMES_CONFIG" ]] && CONFIG_PREEXISTED=true

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   AI Memory Stack  v4.12 — Configure     ║${NC}"
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
_CONV_COUNT=$(find "$VAULT/05-AI-Sessions" -type f -name '*.md' ! -name 'INDEX.md' 2>/dev/null | wc -l | tr -d ' ')
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
MODEL_TAG=$(sget model); SOURCE=$(sget source); DESC=$(sget desc); REASON=$(sget reason)

# Hermes Agent refuses any model below this context floor.
HERMES_CTX_FLOOR=64000

# Is this machine too weak for a useful local model?
# Heuristic: under ~6 GB RAM, a local model is either too small to be useful
# (0.5b) or too slow (3b). Offer cloud-only instead of forcing a local model.
RAM_INT="${RAM_GB%.*}"; [[ "$RAM_INT" =~ ^[0-9]+$ ]] || RAM_INT=0
WEAK_FOR_LOCAL=false
[[ "$RAM_INT" -lt 6 ]] && WEAK_FOR_LOCAL=true

MODE="local"   # local | cloud
if $WEAK_FOR_LOCAL && ! $ASSUME_YES; then
  echo ""
  warn "This machine has ~${RAM_GB} GB RAM — small for a useful local model."
  echo -e "  A tiny local model runs but is weak; a 3B model runs but is slow."
  echo -e "  ${BOLD}Recommended here: cloud-only${NC} — Hermes uses a cloud model"
  echo -e "  (via OpenRouter), nothing heavy runs on this machine."
  echo ""
  echo -e "  1) Cloud-only   ${GREEN}★ recommended for this hardware${NC}"
  echo -e "  2) Local model  (download one anyway — slower, but private/offline)"
  ask "Choice [1/2] (ENTER = 1):"
  read -r _modechoice || _modechoice=""
  [[ "$_modechoice" == "2" ]] && MODE="local" || MODE="cloud"
elif $WEAK_FOR_LOCAL && $ASSUME_YES; then
  MODE="cloud"   # non-interactive on weak hardware defaults to cloud
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
  if ollama list 2>/dev/null | grep -q "^${tag%%:*}"; then
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
  ok "Primary model (cloud): $MODEL_TAG"
else
  # Local path: let the user confirm or override, THEN verify the model exists.
  if ! $ASSUME_YES; then
    ask "Confirm model (ENTER = $MODEL_TAG, or type another Ollama tag):"
    read -r override || override=""
    [[ -n "$override" ]] && MODEL_TAG="$override"
  fi
  ok "Primary model: $MODEL_TAG"
  ensure_model_present "$MODEL_TAG" || true
fi

# §4.2 — warn if the chosen model is likely too weak to drive memory/search tools.
warn_weak_model "$MODEL_TAG" || true

# Context length: never below Hermes' hard floor; scale up with RAM/model max.
# (Pattern-hunt fix: write-against-known-limit — clamp to the floor always.)
CTX=$HERMES_CTX_FLOOR
[[ "$RAM_INT" -ge 40 ]] 2>/dev/null && CTX=128000
[[ "$CTX" -lt "$HERMES_CTX_FLOOR" ]] && CTX=$HERMES_CTX_FLOOR

# ═════════════════════════════════════════════════════════════════════════════
# 4/5  HERMES CONFIG + API KEYS (fallback chain)
# ═════════════════════════════════════════════════════════════════════════════
hdr "4/5  Hermes configuration"

echo ""
if [[ "$MODE" == "cloud" ]]; then
  echo -e "  ${BOLD}Cloud-only setup:${NC} Hermes will use ${GREEN}$MODEL_TAG${NC} via OpenRouter."
  echo -e "  An OpenRouter API key is ${BOLD}required${NC} for this to work."
else
  echo -e "  ${BOLD}Fallback chain:${NC}"
  echo -e "   1. ${GREEN}Local Ollama${NC}   — $MODEL_TAG (free, offline)"
  echo -e "   2. ${YELLOW}OpenRouter${NC}     — cheap cloud models (optional API key)"
  echo -e "   3. ${RED}Anthropic${NC}      — Claude (optional API key, most reliable)"
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

# config.yaml — back up and (re)write the model block for local Ollama
if [[ -f "$HERMES_CONFIG" ]]; then
  cp "$HERMES_CONFIG" "${HERMES_CONFIG}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  ok "Backed up existing config.yaml"
fi
python3 - "$HERMES_CONFIG" "$MODEL_TAG" "$CTX" "$MODE" << 'PYCONF'
import sys, re, os
from pathlib import Path
path, model, ctx, mode = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
if mode == "cloud":
    base_url = "https://openrouter.ai/api/v1"
    comment = "# cloud via OpenRouter (key in ~/.hermes/.env)"
    extra = ""
else:
    base_url = "http://localhost:11434/v1"
    comment = "# local Ollama (OpenAI-compatible)"
    # §4.35: a local model whose native context is below Hermes' floor must ALSO
    # be told to LOAD at the floor, or Ollama loads it small and Hermes refuses
    # ("runtime context too small") even though context_length passed its check.
    # context_length = what Hermes believes; ollama_num_ctx = what Ollama loads.
    extra = f"  ollama_num_ctx: {ctx}            # force Ollama to load >= Hermes' floor\n"
block = (
    "model:\n"
    f"  default: {model}\n"
    f"  provider: custom            {comment}\n"
    f"  base_url: {base_url}\n"
    f"  context_length: {ctx}\n"
    + extra
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
# Atomic write so a failure can never leave a half-written / empty config.
tmp = Path(str(p) + ".tmp")
tmp.write_text(text)
os.replace(str(tmp), str(p))
print("ok")
PYCONF
if [[ "$MODE" == "cloud" ]]; then
  ok "config.yaml → cloud via OpenRouter, model: $MODEL_TAG, ctx: $CTX"
else
  ok "config.yaml → local Ollama, model: $MODEL_TAG, ctx: $CTX (+ ollama_num_ctx)"
fi

# §4.35: a green run that writes no config is a bad failure (confirmed on WSL:
# model downloaded, config.yaml never written, Hermes fell back to its default).
# VERIFY the write actually landed by reading it back — fail loudly if not.
verify_config_written() {
  [[ -f "$HERMES_CONFIG" ]] \
    || die "config.yaml was NOT written to $HERMES_CONFIG — Hermes would fall back to its default. Re-run configure."
  grep -qF "  default: $MODEL_TAG" "$HERMES_CONFIG" \
    || die "config.yaml is missing the model default ($MODEL_TAG) — write did not land correctly."
  grep -qE "^  context_length: [0-9]+" "$HERMES_CONFIG" \
    || die "config.yaml is missing context_length — write did not land correctly."
  if [[ "$MODE" == "local" ]]; then
    grep -qE "^  ollama_num_ctx: [0-9]+" "$HERMES_CONFIG" \
      || die "config.yaml is missing ollama_num_ctx — a local model needs it to clear Hermes' 64K floor."
  fi
  if [[ "$MODE" == "local" ]]; then
    ok "Verified config.yaml on disk (model, context_length, ollama_num_ctx)"
  else
    ok "Verified config.yaml on disk (model, context_length)"
  fi
}
verify_config_written

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
import sys, re
from pathlib import Path
rc, vault = sys.argv[1], sys.argv[2]
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
    'hermes() { ( cd "' + vault + '" 2>/dev/null && TERMINAL_CWD="' + vault + '" command hermes "$@" ); }\n'
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
    "3. For a SPECIFIC topic, SEARCH with absolute paths — actually CALL the tool,\n"
    "   do not just describe the command:\n"
    "       grep -rli \"KEYWORD\" \"" + vault + "/05-AI-Sessions/\"\n"
    "   then read the matching files and answer from them. Try keyword variants\n"
    "   (synonyms, names, project titles). Never guess or invent filenames. Only\n"
    "   say you found nothing AFTER that grep has actually run and returned nothing.\n\n"
    "You DO have filesystem and command tools available — use them. If a listing or\n"
    "search returns entries, the memory is there; claiming \"no access\" or \"empty\"\n"
    "without having run the tool is a mistake.\n"
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

if [[ "$MODE" == "cloud" ]]; then
  if [[ -n "$OR_KEY" || -n "$EXISTING_OR" ]]; then
    ok "Cloud-only: OpenRouter key present, model $MODEL_TAG"
  else
    warn "Cloud-only but no OpenRouter key — Hermes can't reach a model yet"
  fi
else
  if command -v ollama &>/dev/null && ollama list &>/dev/null 2>&1; then
    ok "Ollama responding"
    if ollama list 2>/dev/null | grep -q "^${MODEL_TAG%%:*}"; then
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
INGEST="$VAULT/.tools/ai-memory-ingest.sh"
if ! $ASSUME_YES; then
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
