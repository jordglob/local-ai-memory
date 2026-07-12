#!/usr/bin/env bash
# =============================================================================
#  ai-memory-ingest.sh  v2.27
#  Import scattered AI conversations into the vault — 13 sources
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
exec python3 - "$@" << 'PYMAIN'
import sys, os, re, json, zipfile, sqlite3, argparse, datetime, fnmatch, hashlib
import html as htmllib
import itertools, tempfile
from pathlib import Path

VERSION = "2.27"
WITH_CRON = False
HOME = Path.home()

# ── terminal helpers ──────────────────────────────────────────────────────────
IS_TTY = sys.stdout.isatty()
def c(code, s): return f"\033[{code}m{s}\033[0m" if IS_TTY else s
def ok(s):   print(c("0;32", "✓") + f"  {s}")
def info(s): print(c("0;36", "→") + f"  {s}")
def warn(s): print(c("1;33", "⚠") + f"  {s}")
def err(s):  print(c("0;31", "✗") + f"  {s}", file=sys.stderr)
def hdr(s):  print("\n" + c("1", f"── {s} ──"))

ASSUME_YES = False
def ask_yn(question, default=True):
    """Prompt via /dev/tty (stdin is our heredoc). Non-interactive → NO
    unless --yes was passed (v2.27 — a hook/cron run must not consent)."""
    if ASSUME_YES:
        return True
    suffix = "[Y/n]" if default else "[y/N]"
    try:
        with open("/dev/tty", "r+") as tty:
            tty.write(c("1", f"{question} {suffix} "))
            tty.flush()
            ans = tty.readline().strip().lower()
        if not ans:
            return default
        return ans in ("y", "yes", "j", "ja")
    except OSError:
        # No TTY (cron / session hook): the safe answer is NO — a
        # non-interactive run must never e.g. import a Downloads zip without
        # consent. --yes is the explicit opt-in (handled above).  (v2.27)
        warn(f"Non-interactive (no TTY) — assuming no: {question}")
        return False

# ── secret-scrub ──────────────────────────────────────────────────────────────
# The vault is the artifact that gets synced, exported and backed up — the
# project's keystone promise is "secrets never travel". But people PASTE keys
# into chats, and a faithful archive would carry them along. Redact before
# anything is written. Conservative, high-confidence patterns only: silently
# mangling prose would be worse than missing an exotic token format.
_SECRET_PATTERNS = (
    (re.compile(r"\bsk-[A-Za-z0-9_-]{16,}"),                     "[REDACTED:api-key]"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),              "[REDACTED:github-token]"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{22,}\b"),            "[REDACTED:github-token]"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"),                        "[REDACTED:aws-key]"),
    (re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),                   "[REDACTED:google-key]"),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"),            "[REDACTED:slack-token]"),
    (re.compile(r"\bwhsec_[A-Za-z0-9]{16,}\b"),                  "[REDACTED:webhook-secret]"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}\b"),
                                                                 "[REDACTED:jwt]"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----",
                re.S),                                           "[REDACTED:private-key]"),
)

def scrub_secrets(t):
    for rx, repl in _SECRET_PATTERNS:
        t = rx.sub(repl, t)
    return t

# ── optional AI titles (--ai-titles) ──────────────────────────────────────────
# Some sources have no real title — the heading falls back to the raw first
# prompt, and a vault listing full of "Uppgift, svara direkt utan att..." is
# noise. Opt-in: the ALREADY-CONFIGURED local model writes a short title for
# those conversations (§4.5 hybrid — deterministic import stays a script; only
# the interpretation step is a model). WITHOUT the flag ingest is fully offline.
# Endpoint/model: AI_MEMORY_MODEL_URL / AI_MEMORY_MODEL env, else the vault's
# .mcp/ai-config.json (primary.base_url / .model), else localhost ollama + the
# first model its /models endpoint reports. Titling must never break an import:
# the first failure disables it for the rest of the run (loudly) and the
# raw-prompt fallback is used.
AI_TITLES = False
_AI = {"base": None, "model": None, "dead": None, "empties": 0}

def _ai_setup(vault):
    import urllib.request
    base = os.environ.get("AI_MEMORY_MODEL_URL", "")
    model = os.environ.get("AI_MEMORY_MODEL", "")
    cfg = vault / ".mcp" / "ai-config.json"
    if (not base or not model) and cfg.is_file():
        try:
            prim = json.loads(cfg.read_text(encoding="utf-8")).get("primary") or {}
            base = base or prim.get("base_url") or ""
            model = model or prim.get("model") or ""
        except (OSError, ValueError, AttributeError):
            pass
    base = (base or "http://localhost:11434/v1").rstrip("/")
    if not model:
        try:
            with urllib.request.urlopen(f"{base}/models", timeout=10) as r:
                data = json.loads(r.read().decode("utf-8", "replace"))
            model = (data.get("data") or [{}])[0].get("id") or ""
        except Exception as e:
            _AI["dead"] = str(e)
    _AI["base"], _AI["model"] = base, model
    if _AI["dead"] or not model:
        _AI["dead"] = _AI["dead"] or "no model configured"
        warn(f"--ai-titles: model unavailable ({_AI['dead']}) — using fallback titles")
    else:
        info(f"AI titles: {model} @ {base}")

def _ai_post(url, payload):
    """POST json, return parsed json. Generous timeout: the FIRST call may
    load a large model from disk."""
    import urllib.request
    req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.loads(r.read().decode("utf-8", "replace"))

def _ai_clean(text):
    """Model reply → one clean heading line ('' if nothing usable)."""
    # Reasoning models may wrap the answer in <think> blocks — strip them.
    text = re.sub(r"<think>.*?(</think>|$)", "", text or "", flags=re.S)
    # strip wrapping quotes/periods in any order ("Titel". / 'Titel.' etc.)
    line = next((ln.strip().strip('\'" .')
                 for ln in text.splitlines() if ln.strip()), "")
    return " ".join(line.split())[:80]

def _ai_title(msgs):
    """One short heading from the configured model, or None — never raises.
    Model-agnostic on purpose: no model-specific prompt magic, and a blank
    from the OpenAI endpoint gets a second chance via ollama's native
    generate API, so reasoning and plain models are treated the same."""
    if _AI["dead"] or not _AI["model"]:
        return None
    first_user = next((t for r, t in msgs
                       if str(r).lower() in ("user", "human")), "")
    first_asst = next((t for r, t in msgs
                       if str(r).lower() in ("assistant", "model", "ai")), "")
    excerpt = first_user.strip()[:900]
    if first_asst:
        excerpt += "\n---\n" + first_asst.strip()[:600]
    prompt = ("Give this archived AI conversation a short title: "
              "3-8 words, in the same language as the conversation, plain "
              "text, no quotes, no trailing period. Reply with ONLY the "
              "title.\n\n" + excerpt)
    # Two attempts: blanks proved transient/flaky in the live round.
    for _attempt in (1, 2):
        try:
            data = _ai_post(f"{_AI['base']}/chat/completions",
                            {"model": _AI["model"], "stream": False,
                             "temperature": 0.2, "max_tokens": 500,
                             "messages": [{"role": "user", "content": prompt}]})
            text = (data.get("choices") or [{}])[0].get("message", {}).get("content") or ""
        except Exception as e:
            _AI["dead"] = str(e)
            warn(f"--ai-titles: call failed ({e}) — fallback titles from here on")
            return None
        title = _ai_clean(text)
        if title:
            _AI["empties"] = 0
            return title
        # EQUAL TREATMENT for reasoning models: ollama's OpenAI endpoint can
        # 200-OK a blank for them (qwen3.6:35b live 2026-07-07) while the
        # native generate API answers fine — try it before counting a blank.
        # `think: false` first (silences reasoning); plain models reject the
        # key, so retry without it. Non-ollama servers just 404 → skip.
        if _AI["base"].endswith("/v1"):
            root = _AI["base"][:-3]
            for extra in ({"think": False}, {}):
                try:
                    data = _ai_post(f"{root}/api/generate",
                                    {"model": _AI["model"], "stream": False,
                                     "prompt": prompt,
                                     "options": {"temperature": 0.2,
                                                 "num_predict": 500}, **extra})
                    title = _ai_clean(data.get("response") or "")
                    if title:
                        _AI["empties"] = 0
                        return title
                    break                  # answered but blank → count it
                except Exception:
                    continue               # think-key rejected / not ollama
    # NEVER a silent zero — but blanks proved CONTENT-dependent in the live
    # round (one specific tiny conversation reliably drew an empty reply while
    # its neighbours titled fine), so one blank must not kill the whole run:
    # warn, fall back for THIS conversation, keep going. Only a STREAK of
    # blanks (3 in a row) means the model/endpoint is actually broken.
    _AI["empties"] += 1
    if _AI["empties"] >= 3:
        _AI["dead"] = "3 consecutive empty replies"
        warn("--ai-titles: 3 consecutive empty replies — model/endpoint looks "
             "broken; fallback titles from here on")
    else:
        warn("--ai-titles: empty reply for this conversation (retried once) — "
             "using its fallback title, continuing")
    return None

# ── shared output ─────────────────────────────────────────────────────────────
def slugify(s, n=55):
    s = re.sub(r"[^\w\s-]", "", s or "untitled", flags=re.UNICODE).strip()
    return (re.sub(r"[\s_]+", "-", s)[:n].strip("-") or "untitled").lower()

def _safe_id(s, n=40):
    """Whitelist an id to filename-safe chars — a hostile/corrupt export must not
    smuggle path separators (`../`) into the conversation id (path-traversal fix).
    NEVER lossy (v2.27): an over-long id keeps a readable head plus a sha1 of the
    FULL id — the old plain cut made distinct long ids share one filename."""
    raw = str(s or "")
    s = re.sub(r"[^A-Za-z0-9._-]", "", raw).strip("._-")
    if not s:
        return "noid"
    if len(s) <= n:
        return s
    return (s[:n - 17].rstrip("._-") + "-"
            + hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16])

def _safe_date(s):
    """Accept only a leading YYYY-MM-DD; anything else (incl. `../..`) → 'undated'."""
    m = re.match(r"(\d{4}-\d{2}-\d{2})", str(s or ""))
    return m.group(1) if m else "undated"

def _atomic_write(path: Path, text: str):
    """EVERY vault write goes through here (v2.27): tempfile in the SAME dir +
    os.replace, so a crash / full disk / parallel run never leaves a
    half-written conversation, INDEX or report behind."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent),
                               prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

# Sources whose ids v≤2.26 truncated to 12 chars — the only dirs where a legacy
# (truncated-id) file may exist for the v2.27 adopt-in-place migration. aider is
# deliberately NOT here: its short positional ids were never truncated, and a
# prefix rule would let `proj-100` claim `proj-1000`'s file.
_LEGACY_TRUNCATED = {"codex-cli", "gemini-cli", "openclaw",
                     "cursor", "lm-studio", "open-webui"}

_ID_CACHE = {}   # str(out_dir) -> {embedded raw id: Path} — built once per run

def _embedded_id(path):
    """The raw `- id:` line from a vault file's HEADER (never message text)."""
    try:
        head = path.read_text(encoding="utf-8", errors="replace")[:2000]
    except OSError:
        return None
    head = head.split("\n---\n", 1)[0]
    m = re.search(r"(?m)^- id: (.+)$", head)
    return m.group(1).strip() if m else None

def _dir_ids(out_dir: Path):
    """Map every conversation file in out_dir by its embedded id (exact binding,
    v2.27 — the old suffix-glob `*-{cid}.md` matched OTHER ids that merely ended
    the same way, e.g. aider's `proj-001` bound to `other-proj-001`.)"""
    key = str(out_dir)
    cache = _ID_CACHE.get(key)
    if cache is None:
        cache = {}
        if out_dir.is_dir():
            for p in sorted(out_dir.glob("*.md")):
                if p.name == "INDEX.md":
                    continue
                eid = _embedded_id(p)
                if eid and eid != "?":
                    cache.setdefault(eid, p)
        _ID_CACHE[key] = cache
    return cache

# Role labels write_conv emits are many-to-one ("user" and "human" both render
# as **You:**) — when hashing a file BACK, try every original-role combination.
_LABEL_ROLES = {"You": ("user", "human"),
                "Assistant": ("assistant", "model", "ai"),
                "System": ("system",)}

def _disk_hash_ok(prior, stored):
    """True iff the on-disk file still hashes to its OWN stored hash — i.e. it
    is exactly what some ingest run wrote. False means the USER edited it by
    hand (or the format is foreign), and it must never be overwritten (v2.27)."""
    parts = prior.split("\n---\n", 1)
    if len(parts) != 2:
        return False
    blocks, cur = [], None
    for line in parts[1].splitlines():
        m = re.match(r"^\*\*(.+):\*\*$", line)
        if m:
            cur = [m.group(1), []]
            blocks.append(cur)
        elif cur is not None:
            cur[1].append(line)
    if not blocks:
        return False
    parsed = [(lab, "\n".join(ls).strip()) for lab, ls in blocks]
    labels = []
    for lab, _t in parsed:
        if lab not in labels:
            labels.append(lab)
    for combo in itertools.product(*[_LABEL_ROLES.get(l, (l,)) for l in labels]):
        role_of = dict(zip(labels, combo))
        h = hashlib.sha256()
        for lab, t in parsed:
            h.update((str(role_of[lab]) + "\x00" + t + "\x00").encode("utf-8"))
        if h.hexdigest()[:16] == stored:
            return True
    return False

def write_conv(out_dir: Path, source: str, conv: dict, stats: dict):
    """conv: {id, title, created, messages:[(role,text)], note?}

    Idempotent by STABLE conversation id (never by the mtime-derived date): the
    prior import for this id is found by the EXACT `- id:` line embedded in the
    file (v2.27), its stored content hash is compared, and the file is SKIPPED
    if identical or REWRITTEN in place if the conversation grew/changed — no
    duplicates. A file the USER edited by hand (content no longer matching its
    own stored hash) is warned about and left untouched. Files written by
    ≤v2.26 under a truncated id are adopted in place (id upgraded, filename
    kept) rather than duplicated."""
    raw_id = " ".join(str(conv.get("id") or "").split())
    cid = _safe_id(raw_id)
    date = _safe_date(conv.get("created"))
    # Clean every message (strip renderer-placeholder noise, tidy blank lines)
    # BEFORE the empty check, so a message that was *only* noise is dropped and
    # never emits a hollow "**Assistant:**" block. Secrets are scrubbed here
    # too, so the hash covers the REDACTED text — files written by older
    # versions with a secret intact get a hash mismatch and are rewritten
    # sanitized on the next run.
    msgs = [(r, ct) for r, ct in
            ((r, scrub_secrets(clean_text(t))) for r, t in conv.get("messages", [])) if ct]
    if not msgs:
        stats["empty"] += 1
        return
    # Content hash over the cleaned messages only — deliberately excludes the
    # mtime-derived `created`, so a re-import of the same chat is a true no-op.
    h = hashlib.sha256()
    for r, ct in msgs:
        h.update((str(r) + "\x00" + ct + "\x00").encode("utf-8"))
    content_hash = h.hexdigest()[:16]
    # Locate a prior import of THIS id (stable), ignoring its date/slug prefix.
    # Exact embedded-id binding (v2.27); adopt a ≤v2.26 legacy file whose
    # embedded id is the OLD 12-char truncation of this conversation's id.
    existing, adopted = None, False
    if cid != "noid":
        ids = _dir_ids(out_dir)
        existing = ids.get(raw_id)
        if existing is None and source in _LEGACY_TRUNCATED and len(raw_id) > 12:
            existing = ids.get(raw_id[:12])
            adopted = existing is not None
    prior = prior_title = stored_hash = None
    if existing is not None and existing.exists():
        prior = existing.read_text(encoding="utf-8", errors="replace")
        first = prior.split("\n", 1)[0]
        prior_title = first[2:].strip() if first.startswith("# ") else None
        m = re.search(r"(?m)^- hash: (\S+)$", prior.split("\n---\n", 1)[0])
        stored_hash = m.group(1) if m else None
    # Resolve the heading. A parser marks `untitled` when its title is only a
    # raw-prompt fallback; a heading a prior run already upgraded (the source
    # titled the chat later, or an --ai-titles run) is never downgraded back.
    # Titles are secret-scrubbed BEFORE heading/slug/filename use (v2.27) —
    # a key pasted into a chat title used to ride into the FILENAME.
    title = scrub_secrets((conv.get("title") or "Untitled")).strip() or "Untitled"
    if conv.get("untitled") and prior_title and prior_title != title:
        title = prior_title
    elif conv.get("untitled") and AI_TITLES:
        title = _ai_title(msgs) or title
        title = scrub_secrets(title).strip() or "Untitled"
    path = existing if existing is not None else (out_dir / f"{date}-{slugify(title)}-{cid}.md")
    # Belt-and-suspenders: the resolved target must stay inside the vault, even
    # though id/date are now sanitized above.
    try:
        path.resolve().relative_to(out_dir.resolve())
    except ValueError:
        err(f"{source}: refusing to write outside vault: {path}")
        stats["failed"] += 1
        return
    if prior is not None:
        same = stored_hash == content_hash
        if same and prior_title == title and not adopted:
            stats["skipped"] += 1          # byte-for-byte the same conversation
            return
        # About to rewrite this file — but NEVER over a human's edits (v2.27):
        # if the file no longer hashes to its own stored hash, the user changed
        # it by hand; warn and keep their version. (Legacy files without a hash
        # line can't be verified — rewritten as before, that's how pre-v2.14
        # files got sanitized.)
        if stored_hash and not _disk_hash_ok(prior, stored_hash):
            warn(f"{source}: {existing.name} was edited by hand — SKIPPED, "
                 "never overwritten (delete the file to re-import it)")
            stats["edited"] += 1
            return
        if same and prior_title != title:
            # Same content, better title → RETITLE IN PLACE. The filename never
            # changes after first import: the add-only sync (--ignore-existing)
            # would turn a rename into a duplicate on the central vault.
            info(f"retitle: {path.name} → {title}")
        if adopted:
            info(f"migrate: {path.name} — legacy truncated id "
                 f"'{raw_id[:12]}' upgraded to full id (same file)")
        updated = True                     # grown/retitled/adopted (or legacy w/o hash)
    else:
        updated = False
    L = [f"# {title}", "",
         f"- source: {source}",
         f"- created: {conv.get('created') or '?'}",
         f"- id: {raw_id or '?'}",
         f"- hash: {content_hash}"]
    if conv.get("note"):
        L += [f"- note: {scrub_secrets(str(conv['note']))}"]
    L += ["", "---", ""]
    label = {"user": "**You:**", "human": "**You:**",
             "assistant": "**Assistant:**", "model": "**Assistant:**", "ai": "**Assistant:**",
             "system": "**System:**"}
    for role, text in msgs:
        L += [label.get(str(role).lower(), f"**{role}:**"), "", text.strip(), ""]
    out_dir.mkdir(parents=True, exist_ok=True)
    _atomic_write(path, "\n".join(L))
    if cid != "noid":
        cache = _dir_ids(out_dir)
        if adopted:
            cache.pop(raw_id[:12], None)
        cache[raw_id] = path
    stats["updated" if updated else "new"] += 1

# Renderer placeholders some exporters embed in their pre-rendered "text" field
# where a tool-call / artifact / search block could not be shown. Pure noise in a
# saved transcript — stripped generically for EVERY source (pattern-hunt class fix).
_NOISE_LINES = (
    "This block is not supported on your current device yet.",
)
def clean_text(t):
    if not t:
        return ""
    # Normalize CRLF/CR → LF first. Transcripts written on Windows (e.g. Claude
    # Code .jsonl synced off that box) carry literal \r\n INSIDE message text;
    # every line-anchored regex below ((?m)^…$, \n{3,}) silently misses CRLF
    # text, and the \r would survive into the vault's markdown (live finding,
    # cc-session-sync round 2026-07-06).
    t = t.replace("\r\n", "\n").replace("\r", "\n")
    for noise in _NOISE_LINES:
        # the placeholder, optionally wrapped in a ``` code fence
        t = re.sub(r"```[ \t]*\n[ \t]*" + re.escape(noise) + r"[ \t]*\n[ \t]*```", "", t)
        t = re.sub(r"(?m)^[ \t]*" + re.escape(noise) + r"[ \t]*$", "", t)
    t = re.sub(r"\n{3,}", "\n\n", t)        # collapse runs of blank lines
    return t.strip()

def text_from_blocks(content):
    """Extract text from a string / list-of-blocks / dict — defensively."""
    if isinstance(content, str):
        return content
    if isinstance(content, dict):
        if isinstance(content.get("parts"), list):
            return "\n".join(p if isinstance(p, str) else p.get("text", "")
                             for p in content["parts"] if p)
        return content.get("text", "") or ""
    if isinstance(content, list):
        out = []
        for b in content:
            if isinstance(b, str):
                out.append(b)
            elif isinstance(b, dict):
                t = b.get("text") or b.get("content") or ""
                if isinstance(t, str) and t and b.get("type") in (
                        None, "text", "input_text", "output_text", "markdown"):
                    out.append(t)
        return "\n".join(out)
    return ""

# ── parsers (each: parse(path, out_root) -> stats dict) ──────────────────────
def _stats(): return {"new": 0, "updated": 0, "skipped": 0, "edited": 0,
                      "empty": 0, "failed": 0}

# Cap on a single decompressed zip member. A malicious/decompression-bomb export
# can be a few KB on disk yet expand to many GB — reading it whole would OOM the
# process. Refuse anything over this uncompressed threshold. (2 GiB is generous;
# a real conversations.json export is MBs, not GBs.)
_MAX_MEMBER_BYTES = 2 * 1024 ** 3

def _zip_read(z, name):
    """Read a zip member as bytes, guarding against decompression bombs."""
    size = z.getinfo(name).file_size
    if size > _MAX_MEMBER_BYTES:
        raise ValueError(f"{name}: {size} bytes uncompressed exceeds "
                         f"{_MAX_MEMBER_BYTES}-byte cap — refusing (possible zip bomb)")
    return z.read(name)

def _zip_read_json(z, name):
    return json.loads(_zip_read(z, name).decode("utf-8", "replace"))

def parse_claude_zip(zpath, out_root):
    st = _stats(); out = out_root / "claude-web"
    with zipfile.ZipFile(zpath) as z:
        name = next((n for n in z.namelist() if n.endswith("conversations.json")), None)
        if not name: raise ValueError("no conversations.json in zip")
        data = _zip_read_json(z, name)
    for conv in data:
        try:
            msgs = []
            for m in conv.get("chat_messages", []):
                role = "user" if m.get("sender") == "human" else "assistant"
                # Prefer the structured content blocks: the flat "text" field
                # embeds renderer placeholders where tool/search/artifact blocks
                # were. Fall back to "text" for the rare block-less message.
                body = text_from_blocks(m.get("content")) or m.get("text") or ""
                parts = [body] if body.strip() else []
                # Uploaded documents carry their extracted text — real user
                # content that would otherwise be lost. Keep it.
                for a in (m.get("attachments") or []):
                    if not isinstance(a, dict):
                        continue
                    fn = a.get("file_name") or "attachment"
                    ec = a.get("extracted_content")
                    if ec and str(ec).strip():
                        parts.append(f"_[attached file: {fn}]_\n\n```\n{str(ec).strip()}\n```")
                    else:
                        parts.append(f"_[attached file: {fn}]_")
                # Images / binary files have no extractable text — note their
                # names so an image-only turn isn't dropped (breaks the thread).
                imgs = [f.get("file_name") for f in (m.get("files") or [])
                        if isinstance(f, dict) and f.get("file_name")]
                if imgs:
                    parts.append("_[attached: " + ", ".join(imgs) + "]_")
                msgs.append((role, "\n\n".join(p for p in parts if p and p.strip())))
            write_conv(out, "claude.ai", {"id": conv.get("uuid"), "title": conv.get("name"),
                       "created": conv.get("created_at"), "messages": msgs}, st)
        except Exception: st["failed"] += 1
    return st

def parse_chatgpt_zip(zpath, out_root):
    st = _stats(); out = out_root / "chatgpt"
    with zipfile.ZipFile(zpath) as z:
        name = next((n for n in z.namelist() if n.endswith("conversations.json")), None)
        if not name: raise ValueError("no conversations.json in zip")
        data = _zip_read_json(z, name)
    for conv in data:
        try:
            mapping = conv.get("mapping") or {}
            # walk canonical thread: current_node → root, then reverse
            chain, node = [], conv.get("current_node")
            seen = set()
            while node and node in mapping and node not in seen:
                seen.add(node); chain.append(mapping[node]); node = mapping[node].get("parent")
            chain.reverse()
            msgs = []
            for entry in chain:
                m = entry.get("message") or {}
                role = ((m.get("author") or {}).get("role") or "")
                if role not in ("user", "assistant"): continue
                t = text_from_blocks(m.get("content"))
                if t.strip(): msgs.append((role, t))
            created = conv.get("create_time")
            if isinstance(created, (int, float)):
                created = datetime.datetime.fromtimestamp(created).isoformat()
            write_conv(out, "chatgpt", {"id": conv.get("id") or conv.get("conversation_id"),
                       "title": conv.get("title"), "created": created, "messages": msgs}, st)
        except Exception: st["failed"] += 1
    return st

# Claude Code session transcripts interleave the conversation with harness
# records (mode switches, file snapshots, tool outputs) and wrap non-human
# user content in markup tags. Only the human↔assistant exchange belongs in
# a memory vault — the rest is noise that would poison search results.
_CC_TAGS = ("system-reminder", "command-name", "command-message", "command-args",
            "local-command-stdout", "local-command-caveat", "task-notification")
_CC_TAG_RE = re.compile(r"<(" + "|".join(_CC_TAGS) + r")\b[^>]*>.*?</\1>", re.S)

def _cc_user_text(t):
    """Strip Claude Code harness markup from a user turn; '' if nothing human remains."""
    t = _CC_TAG_RE.sub("", t or "")
    t = re.sub(r"(?m)^Caveat: The messages below were generated by the user.*$", "", t)
    t = re.sub(r"\[Request interrupted by user[^\]]*\]", "", t)
    return t.strip()

def parse_claude_code(root, out_root):
    st = _stats(); out = out_root / "claude-code"
    for jl in Path(root).rglob("*.jsonl"):
        try:
            msgs, title, created = [], None, None
            for raw in jl.read_text(encoding="utf-8", errors="replace").splitlines():
                raw = raw.strip()
                if not raw: continue
                try: rec = json.loads(raw)
                except json.JSONDecodeError: continue
                rtype = rec.get("type")
                if rtype == "ai-title" and rec.get("aiTitle"):
                    title = rec["aiTitle"]; continue      # keep the LAST title
                if rtype == "summary" and rec.get("summary"):
                    title = title or rec["summary"]; continue
                if rtype not in ("user", "assistant"): continue
                if rec.get("isSidechain"): continue       # subagent transcripts
                if created is None and rec.get("timestamp"):
                    created = rec["timestamp"]
                m = rec.get("message") or {}
                role = m.get("role") or rtype
                t = text_from_blocks(m.get("content"))
                if role == "user":
                    if rec.get("toolUseResult") is not None:
                        continue                          # tool output, not the human
                    t = _cc_user_text(t)
                if t.strip():
                    msgs.append((role, t))
            if not any(r == "user" for r, _ in msgs):
                st["empty"] += 1; continue                # no human turn → harness noise
            if created is None:
                created = datetime.datetime.fromtimestamp(jl.stat().st_mtime).isoformat()
            write_conv(out, "claude-code",
                       {"id": jl.stem,
                        "title": title or f"Claude Code — {jl.parent.name}",
                        "created": created,
                        "note": f"project dir: {jl.parent.name}",
                        "messages": msgs}, st)
        except Exception: st["failed"] += 1
    return st

def parse_hermes(db_path, out_root):
    """Hermes keeps its own history in ~/.hermes/state.db (sessions + messages).
    Archiving it closes the loop the stack promises: the agent's short-term
    memory becomes long-term, searchable vault memory. Read-only open — safe
    to run while the agent is live (WAL readers don't block the writer).
    Skips source='cli' rows (one-shot `hermes -z` automation/scripting) — only
    interactive (tui) and gateway conversations are archived, so the vault fills
    with real chats, not dev/test one-shots."""
    st = _stats(); out = out_root / "hermes"
    try:
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = con.cursor()
        # Skip one-shot `hermes -z` sessions (source='cli') — archive only real
        # interactive (tui) + gateway conversations. NULL-safe (COALESCE: a NULL
        # source counts as non-cli) AND column-safe (older/test dbs may have no
        # source column → PRAGMA check → no filter, ingest all).
        _cols = [r[1] for r in cur.execute("PRAGMA table_info(sessions)").fetchall()]
        _srcf = "WHERE COALESCE(source, '') != 'cli' " if "source" in _cols else ""
        try:
            # Hermes titles its own sessions (sessions.title) — use that first;
            # v2.14–v2.18 never read the column and every heading fell back to
            # the raw first prompt (ugly-listing live finding, 2026-07-07).
            sessions = cur.execute(
                "SELECT id, model, started_at, title FROM sessions "
                f"{_srcf}ORDER BY started_at").fetchall()
        except sqlite3.OperationalError:   # older hermes: no title column
            sessions = [(i, m, s, None) for i, m, s in cur.execute(
                "SELECT id, model, started_at FROM sessions "
                f"{_srcf}ORDER BY started_at").fetchall()]
        rows = cur.execute(
            "SELECT session_id, role, content FROM messages "
            "WHERE role IN ('user','assistant') ORDER BY timestamp, id").fetchall()
        con.close()
    except sqlite3.Error as e:
        err(f"hermes: cannot open {db_path}: {e}"); st["failed"] += 1; return st
    by_session = {}
    for sid, role, content in rows:
        if isinstance(content, str) and content.strip():
            by_session.setdefault(sid, []).append((role, content))
    for sid, model, started, db_title in sessions:
        try:
            msgs = by_session.get(sid) or []
            if not any(r == "user" for r, _ in msgs):
                st["empty"] += 1; continue         # tool-only / aborted session
            created = None
            if isinstance(started, (int, float)):
                created = datetime.datetime.fromtimestamp(started).isoformat()
            db_title = " ".join((db_title or "").split())
            first_user = next((t for r, t in msgs if r == "user"), "")
            fallback = " ".join(first_user.split())[:60] or f"Hermes — {sid}"
            conv = {"id": sid, "title": db_title or fallback, "created": created,
                    "note": f"model: {model}" if model else None,
                    "messages": msgs}
            if not db_title:
                conv["untitled"] = True    # raw-prompt fallback → --ai-titles eligible
            write_conv(out, "hermes", conv, st)
        except Exception: st["failed"] += 1
    return st

def parse_codex(root, out_root):
    st = _stats(); out = out_root / "codex"
    for jl in Path(root).rglob("*.jsonl"):
        try:
            msgs = []
            for raw in jl.read_text(encoding="utf-8", errors="replace").splitlines():
                try: rec = json.loads(raw)
                except json.JSONDecodeError: continue
                # rollout format: {"type":..., "payload":{...}} or flat
                for cand in (rec.get("payload"), rec, rec.get("message")):
                    if isinstance(cand, dict) and cand.get("role") in ("user", "assistant"):
                        t = text_from_blocks(cand.get("content"))
                        if t.strip(): msgs.append((cand["role"], t))
                        break
            write_conv(out, "codex-cli",
                       {"id": jl.stem.replace("rollout-", "") or jl.stem,
                        "title": f"Codex — {jl.stem}",
                        "created": datetime.datetime.fromtimestamp(jl.stat().st_mtime).isoformat(),
                        "messages": msgs}, st)
        except Exception: st["failed"] += 1
    return st

def parse_gemini_cli(root, out_root):
    st = _stats(); out = out_root / "gemini-cli"
    root = Path(root)
    # saved chats / checkpoints: [{role: user|model, parts:[{text}]}]
    for f in list(root.rglob("checkpoint*.json")) + list(root.rglob("chats/*.json")):
        try:
            data = json.loads(f.read_text(encoding="utf-8", errors="replace"))
            items = data if isinstance(data, list) else data.get("history") or data.get("messages") or []
            msgs = [(m.get("role", "?"), text_from_blocks(m.get("parts") or m.get("content")))
                    for m in items if isinstance(m, dict)]
            write_conv(out, "gemini-cli",
                       {"id": f.stem, "title": f"Gemini CLI — {f.stem}",
                        "created": datetime.datetime.fromtimestamp(f.stat().st_mtime).isoformat(),
                        "messages": msgs}, st)
        except Exception: st["failed"] += 1
    # logs.json: user prompts only
    for f in root.rglob("logs.json"):
        try:
            data = json.loads(f.read_text(encoding="utf-8", errors="replace"))
            if not isinstance(data, list): continue
            msgs = [("user", e.get("message", "")) for e in data
                    if isinstance(e, dict) and e.get("type") == "user"]
            write_conv(out, "gemini-cli",
                       {"id": f.parent.name, "title": f"Gemini CLI prompts — {f.parent.name}",
                        "created": datetime.datetime.fromtimestamp(f.stat().st_mtime).isoformat(),
                        "messages": msgs, "note": "prompts only (logs.json has no responses)"}, st)
        except Exception: st["failed"] += 1
    return st

def parse_openclaw(root, out_root):
    st = _stats(); out = out_root / "openclaw"
    cron_out = out_root / "openclaw-cron"; cron_seen = 0
    for jl in Path(root).rglob("sessions/*.jsonl"):
        try:
            msgs = []
            for raw in jl.read_text(encoding="utf-8", errors="replace").splitlines():
                try: rec = json.loads(raw)
                except json.JSONDecodeError: continue
                m = rec.get("message") if isinstance(rec.get("message"), dict) else rec
                role = m.get("role")
                t = text_from_blocks(m.get("content"))
                if role in ("user", "assistant") and t.strip():
                    msgs.append((role, t))
            # Scheduler noise: a session whose FIRST user turn is a `[cron:...]`
            # dispatch is an agent run, not a conversation (live run 2026-07-06:
            # 719 of 724). Skipped by default; --with-cron vaults them apart.
            first_user = next((t for r, t in msgs if r == "user"), "")
            if first_user.lstrip().startswith("[cron:"):
                cron_seen += 1
                if not WITH_CRON:
                    continue
                write_conv(cron_out, "openclaw",
                           {"id": jl.stem, "title": f"OpenClaw cron — {jl.stem}",
                            "created": datetime.datetime.fromtimestamp(jl.stat().st_mtime).isoformat(),
                            "messages": msgs}, st)
                continue
            write_conv(out, "openclaw",
                       {"id": jl.stem, "title": f"OpenClaw — {jl.stem}",
                        "created": datetime.datetime.fromtimestamp(jl.stat().st_mtime).isoformat(),
                        "messages": msgs}, st)
        except Exception: st["failed"] += 1
    if cron_seen and not WITH_CRON:
        print(f"  → openclaw: {cron_seen} cron-initiated sessions skipped "
              f"(scheduler noise — rerun with --with-cron to vault them in openclaw-cron/)")
    return st

def parse_cursor(db_path, out_root):
    st = _stats(); out = out_root / "cursor"
    try:
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = con.cursor()
        rows = []
        for table, like in (("cursorDiskKV", "composerData:%"),
                            ("ItemTable", "%aichat%")):
            try:
                cur.execute(f"SELECT key, value FROM {table} WHERE key LIKE ?", (like,))
                rows += cur.fetchall()
            except sqlite3.Error:
                pass
        con.close()
    except sqlite3.Error as e:
        err(f"cursor: cannot open {db_path}: {e}"); st["failed"] += 1; return st
    for key, value in rows:
        try:
            data = json.loads(value if isinstance(value, str) else value.decode("utf-8", "replace"))
            convs = []
            if isinstance(data.get("conversation"), list):     # composerData
                msgs = [("user" if b.get("type") == 1 else "assistant", b.get("text", ""))
                        for b in data["conversation"] if isinstance(b, dict)]
                convs.append((data.get("composerId") or key, data.get("name") or "Cursor chat", msgs))
            for tab in (data.get("tabs") or []):               # legacy chatdata
                msgs = [(b.get("type", "?"), b.get("text", ""))
                        for b in tab.get("bubbles", []) if isinstance(b, dict)]
                convs.append((tab.get("tabId") or key, tab.get("chatTitle") or "Cursor chat", msgs))
            for cid, title, msgs in convs:
                write_conv(out, "cursor", {"id": str(cid), "title": title,
                           "created": None, "messages": msgs}, st)
        except Exception: st["failed"] += 1
    return st

def parse_aider(md_path, out_root):
    st = _stats(); out = out_root / "aider"
    try:
        text = Path(md_path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        st["failed"] += 1; return st
    sessions = re.split(r"^# aider chat started at (.+)$", text, flags=re.M)
    # split → [pre, date1, body1, date2, body2 ...]
    pairs = list(zip(sessions[1::2], sessions[2::2])) or [("undated", text)]
    proj = slugify(Path(md_path).parent.name)
    for i, (date, body) in enumerate(pairs):
        msgs, state = [], {"role": None, "buf": []}
        def flush():
            if state["role"] and "\n".join(state["buf"]).strip():
                msgs.append((state["role"], "\n".join(state["buf"]).strip()))
            state["buf"] = []
        for line in body.splitlines():
            if line.startswith("#### "):
                if state["role"] != "user": flush(); state["role"] = "user"
                state["buf"].append(line[5:])
            else:
                if state["role"] == "user" and line.strip():
                    flush(); state["role"] = "assistant"
                state["buf"].append(line)
        flush()
        write_conv(out, "aider", {"id": f"{proj}-{i:03d}",
                   "title": f"Aider — {Path(md_path).parent.name}",
                   "created": date.strip()[:10], "messages": msgs}, st)
    return st

def parse_lmstudio(root, out_root):
    st = _stats(); out = out_root / "lmstudio"
    for f in Path(root).rglob("*.json"):
        try:
            data = json.loads(f.read_text(encoding="utf-8", errors="replace"))
            if not isinstance(data, dict): continue
            msgs = []
            for m in data.get("messages", []):
                if "versions" in m:                       # versioned format
                    idx = m.get("currentlySelected", 0)
                    vs = m.get("versions") or []
                    v = vs[idx] if 0 <= idx < len(vs) else (vs[0] if vs else {})
                    role = v.get("role") or v.get("type", "?")
                    t = text_from_blocks(v.get("content"))
                else:
                    role, t = m.get("role", "?"), text_from_blocks(m.get("content"))
                if t.strip(): msgs.append((role, t))
            if not msgs: continue
            write_conv(out, "lm-studio",
                       {"id": f.stem, "title": data.get("name") or f.stem,
                        "created": datetime.datetime.fromtimestamp(f.stat().st_mtime).isoformat(),
                        "messages": msgs}, st)
        except Exception: st["failed"] += 1
    return st

def parse_openwebui(db_path, out_root):
    st = _stats(); out = out_root / "open-webui"
    try:
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = con.cursor()
        cur.execute("SELECT id, title, chat FROM chat")
        rows = cur.fetchall(); con.close()
    except sqlite3.Error as e:
        err(f"open-webui: cannot read {db_path}: {e}"); st["failed"] += 1; return st
    for cid, title, chat_json in rows:
        try:
            chat = json.loads(chat_json) if isinstance(chat_json, str) else chat_json
            items = chat.get("messages") or list((chat.get("history") or {}).get("messages", {}).values())
            msgs = [(m.get("role", "?"), text_from_blocks(m.get("content")))
                    for m in items if isinstance(m, dict)]
            write_conv(out, "open-webui", {"id": str(cid), "title": title,
                       "created": None, "messages": msgs}, st)
        except Exception: st["failed"] += 1
    return st

def _takeout_html_to_text(s):
    """Flatten response HTML: block tags become newlines, list items a dash,
    entities decoded. clean_text() tidies the rest downstream in write_conv."""
    s = re.sub(r"(?i)<li[^>]*>", "\n- ", s)
    s = re.sub(r"(?i)<(?:/?)(?:p|div|h[1-6]|ul|ol|tr|table|blockquote|hr)[^>]*>", "\n", s)
    s = re.sub(r"(?i)<br\s*/?>", "\n", s)
    s = re.sub(r"<[^>]+>", "", s)
    return htmllib.unescape(s).replace("\xa0", " ")

_TAKEOUT_TIME = re.compile(r"\d{1,2}[:.]\d{2}[:.]\d{2}")
_TAKEOUT_YEAR = re.compile(r"(?<!\d)(?:19|20)\d{2}(?!\d)")
# sv + en month names (full + 3-letter). Other locales fall back to grouping by
# the raw date string — still one file per day, just without an ISO prefix.
_TAKEOUT_MONTHS = {
    "januari": 1, "februari": 2, "mars": 3, "april": 4, "maj": 5, "juni": 6,
    "juli": 7, "augusti": 8, "september": 9, "oktober": 10, "november": 11,
    "december": 12, "january": 1, "february": 2, "march": 3, "june": 6,
    "july": 7, "august": 8, "october": 10,
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7,
    "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}

def _takeout_iso_date(seg):
    """'5 juli 2026 07:38:31 CEST' / 'Jul 3, 2026, 9:15:00 AM CEST' → ISO date,
    or None for an unmapped locale (caller then groups by the raw string)."""
    t = _TAKEOUT_TIME.search(seg)
    head = seg[:t.start()] if t else seg
    y = _TAKEOUT_YEAR.search(head)
    if not y:
        return None
    mon = None
    for w in re.findall(r"[^\W\d_]+", head, flags=re.UNICODE):
        mon = _TAKEOUT_MONTHS.get(w.lower()) or _TAKEOUT_MONTHS.get(w.lower()[:3])
        if mon:
            break
    d = re.search(r"(?<!\d)(\d{1,2})(?!\d)", head)
    if not (mon and d and 1 <= int(d.group(1)) <= 31):
        return None
    return f"{int(y.group(0)):04d}-{mon:02d}-{int(d.group(1)):02d}"

def parse_takeout(path, out_root):
    """Google Takeout — Gemini. Parses the My Activity register STRUCTURALLY
    (outer-cell blocks; the action verb is separated from the prompt by a
    non-breaking space; the timestamp is the segment carrying year + time), so
    any UI language works — the old 'Prompted'-keyed regex imported 0 from a
    Swedish export, silently (live round 2026-07-05). Modern exports carry
    Gemini's responses too; grouped one conversation per day (My Activity is a
    flat log with no thread ids)."""
    st = _stats(); out = out_root / "gemini-takeout"
    doc = None
    p = Path(path)
    try:
        if p.suffix == ".zip":
            with zipfile.ZipFile(p) as z:
                cands = [(n, z.getinfo(n).file_size) for n in z.namelist()
                         if "Gemini" in n and n.endswith(".html")]
                # Prefer a real activity register over gems/settings exports
                # that also carry "Gemini" in their path (they shadowed the
                # register in the live round); largest wins within a tier.
                act = [c for c in cands if re.search(r"(?i)a[ck]tivi", Path(c[0]).name)]
                pool = act or cands
                if pool:
                    name = max(pool, key=lambda c: c[1])[0]
                    doc = _zip_read(z, name).decode("utf-8", "replace")
        elif p.is_dir():
            files = list(p.rglob("*Gemini*/*.html"))
            act = [f for f in files if re.search(r"(?i)a[ck]tivi", f.name)]
            pool = act or files or [f for f in p.rglob("MyActivity.html")]
            if pool:
                f = max(pool, key=lambda f: f.stat().st_size)
                doc = f.read_text(encoding="utf-8", errors="replace")
        else:
            doc = p.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        err(f"takeout: {e}"); st["failed"] += 1; return st
    if not doc:
        warn("takeout: no Gemini activity HTML found"); return st

    entries = []   # (day_key, iso_or_None, messages) — newest first, as exported
    for block in re.split(r'(?=<div class="outer-cell)', doc)[1:]:
        # main cell = first content-cell that is neither the right-aligned
        # spacer nor the "Products / Why saved" caption cell
        body = None
        for part in block.split('<div class="content-cell')[1:]:
            attrs, _, rest = part.partition(">")
            if "caption" in attrs or "text-right" in attrs:
                continue
            body = rest; break
        if body is None:
            continue
        segs = re.split(r"(?i)<br\s*/?>", body)
        texts = [_takeout_html_to_text(s).strip() for s in segs]
        # segment 0 is "<verb>\xa0<prompt>" — split on the NBSP, which Google
        # emits in every locale, instead of matching the localized verb
        first = htmllib.unescape(re.sub(r"<[^>]+>", "", segs[0]))
        prompt = (first.split("\xa0", 1)[1] if "\xa0" in first else first).strip()
        ts_i = next((i for i in range(1, len(texts))
                     if _TAKEOUT_YEAR.search(texts[i]) and _TAKEOUT_TIME.search(texts[i])), None)
        if ts_i is None or not prompt:
            continue
        attach = [t for t in texts[1:ts_i] if re.search(r"\.\w{2,4}$", t)]
        if attach:
            prompt += "\n\n_[attached: " + ", ".join(attach) + "]_"
        reply = "\n".join(texts[ts_i + 1:]).strip()
        iso = _takeout_iso_date(texts[ts_i])
        t = _TAKEOUT_TIME.search(texts[ts_i])
        day_key = iso or slugify(texts[ts_i][:t.start()] if t else texts[ts_i], 30)
        msgs = [("user", prompt)]
        if reply:
            msgs.append(("assistant", reply))
        entries.append((day_key, iso, msgs))
    if not entries:
        warn("takeout: activity HTML found but 0 entries parsed — Google may have "
             "changed the format (or this is a gems/settings file, not My Activity)")
        return st
    # group per day, oldest→newest inside each (the register is newest-first)
    days = {}; order = []
    for day_key, iso, msgs in reversed(entries):
        if day_key not in days:
            days[day_key] = {"iso": iso, "msgs": []}; order.append(day_key)
        days[day_key]["msgs"].extend(msgs)
    for day_key in order:
        d = days[day_key]
        write_conv(out, "gemini-takeout",
                   {"id": f"takeout-{day_key}",
                    "title": f"Gemini (Google Takeout) — {day_key}",
                    "created": d["iso"], "messages": d["msgs"]}, st)
    info(f"takeout: {len(entries)} activity entries → {len(order)} day file(s)")
    return st

def _aistudio_chunk_text(c):
    """A chunk's visible text: prefer the flat field, else join its parts."""
    t = c.get("text")
    if t is None and isinstance(c.get("parts"), list):
        t = "\n".join(p.get("text", "") for p in c["parts"] if isinstance(p, dict))
    return (t or "").strip()

def _aistudio_thread(raw, fname, out, st):
    d = json.loads(raw)
    chunks = (d.get("chunkedPrompt") or {}).get("chunks") or []
    msgs = []
    created = None
    for c in chunks:
        if not isinstance(c, dict) or c.get("isThought"):
            continue                        # model reasoning — noise in an archive
        role = "assistant" if c.get("role") == "model" else "user"
        if created is None and c.get("createTime"):
            created = c["createTime"]
        bits = []
        t = _aistudio_chunk_text(c)
        if t:
            bits.append(t)
        # Images: note their presence, never vault the bytes. driveImage carries
        # only a Drive file id (the export has no id→filename map — verified
        # against a real export, live round 2026-07-05); inlineImage is base64.
        di = c.get("driveImage")
        if isinstance(di, dict):
            bits.append(f"_[attached image — Drive id {di.get('id', '?')}]_")
        ii = c.get("inlineImage")
        if isinstance(ii, dict):
            bits.append(f"_[attached: inline {ii.get('mimeType', 'image')}]_")
        if not bits:
            continue                        # e.g. a bare rate-limit errorMessage chunk
        if msgs and msgs[-1][0] == role:    # model turns arrive as several chunks
            msgs[-1] = (role, msgs[-1][1] + "\n\n" + "\n\n".join(bits))
        else:
            msgs.append((role, "\n\n".join(bits)))
    si = d.get("systemInstruction")
    if isinstance(si, dict):
        si_text = _aistudio_chunk_text(si)
        if si_text:
            msgs.insert(0, ("system", si_text))
    write_conv(out, "aistudio",
               {"id": fname, "title": fname, "created": created, "messages": msgs}, st)

def parse_aistudio(path, out_root):
    """Google AI Studio — the Drive folder "Google AI Studio" (autosaved
    threads), downloaded as a zip or synced as a directory. Each extension-less
    member is one thread: JSON with chunkedPrompt.chunks. Full threads
    INCLUDING the model's responses, with real createTime timestamps —
    unlike Gemini's Takeout register this is a first-class chat export."""
    st = _stats(); out = out_root / "aistudio"
    n_threads = 0
    def _is_thread(name):
        base = name.rsplit("/", 1)[-1]
        return bool(base) and "." not in base
    try:
        p = Path(path)
        if p.is_file() and zipfile.is_zipfile(p):
            with zipfile.ZipFile(p) as z:
                for n in z.namelist():
                    if n.endswith("/") or not _is_thread(n):
                        continue
                    try:
                        _aistudio_thread(_zip_read(z, n).decode("utf-8", "replace"),
                                         Path(n).name, out, st)
                        n_threads += 1
                    except Exception:
                        st["failed"] += 1
        elif p.is_dir():
            for f in sorted(p.rglob("*")):
                if not f.is_file() or "." in f.name:
                    continue
                try:
                    _aistudio_thread(f.read_text(encoding="utf-8", errors="replace"),
                                     f.name, out, st)
                    n_threads += 1
                except Exception:
                    st["failed"] += 1
        else:
            _aistudio_thread(p.read_text(encoding="utf-8", errors="replace"),
                             p.stem or p.name, out, st)
            n_threads += 1
    except Exception as e:
        err(f"aistudio: {e}"); st["failed"] += 1; return st
    if n_threads == 0:
        warn("aistudio: no thread files found — expected extension-less JSON "
             "members under 'Google AI Studio/' (did the format change?)")
    return st

# ── source registry ───────────────────────────────────────────────────────────
def _appsupport(*parts): return HOME / "Library" / "Application Support" / Path(*parts)

def _is_wsl():
    if os.environ.get("WSL_DISTRO_NAME"): return True
    try:
        return "microsoft" in Path("/proc/version").read_text(errors="replace").lower()
    except OSError:
        return False

def _wsl_windows_homes():
    """Under WSL the Windows side is mounted at /mnt/<drive> — a tool that ran on
    Windows left its sessions in the WINDOWS profile, invisible from the Linux
    $HOME. Return every /mnt/<drive>/Users/<name> so per-user dot-dirs on the
    Windows side are discovered too. Empty everywhere except WSL."""
    if not _is_wsl(): return []
    skip = {"Public", "Default", "Default User", "All Users"}
    homes = []
    for mnt in Path("/mnt").glob("[a-z]"):
        users = mnt / "Users"
        try:
            if users.is_dir():
                homes += [d for d in users.iterdir() if d.is_dir() and d.name not in skip]
        except OSError:
            continue
    return homes

SOURCES = {
    "claude-web":   {"desc": "Claude.ai export ZIP",            "kind": "zip"},
    "chatgpt":      {"desc": "ChatGPT export ZIP",              "kind": "zip"},
    "claude-code":  {"desc": "Claude Code local sessions",      "kind": "dir",
                     "paths": [HOME / ".claude" / "projects"]
                              + [h / ".claude" / "projects" for h in _wsl_windows_homes()],
                     "fn": parse_claude_code},
    "codex":        {"desc": "Codex CLI sessions",              "kind": "dir",
                     "paths": [HOME / ".codex" / "sessions", HOME / ".codex"],
                     "fn": parse_codex},
    "gemini-cli":   {"desc": "Gemini CLI chats/logs",           "kind": "dir",
                     "paths": [HOME / ".gemini"],               "fn": parse_gemini_cli},
    "openclaw":     {"desc": "OpenClaw agent sessions",         "kind": "dir",
                     "paths": [HOME / ".openclaw", HOME / ".clawdbot"],
                     "fn": parse_openclaw},
    "cursor":       {"desc": "Cursor chat databases",           "kind": "glob",
                     "paths": [_appsupport("Cursor", "User"), HOME / ".config" / "Cursor" / "User"],
                     "pattern": "state.vscdb",                  "fn": parse_cursor},
    "aider":        {"desc": "Aider chat history files",        "kind": "glob",
                     "paths": [HOME],                            "pattern": ".aider.chat.history.md",
                     "fn": parse_aider, "shallow": True},
    "lmstudio":     {"desc": "LM Studio conversations",         "kind": "dir",
                     "paths": [HOME / ".lmstudio" / "conversations",
                               HOME / ".cache" / "lm-studio" / "conversations",
                               _appsupport("LM Studio", "conversations")],
                     "fn": parse_lmstudio},
    "open-webui":   {"desc": "Open WebUI database",             "kind": "glob",
                     "paths": [HOME / ".open-webui", HOME / "open-webui"],
                     "pattern": "webui.db",                     "fn": parse_openwebui},
    "gemini-takeout": {"desc": "Google Takeout (Gemini)",       "kind": "zip"},
    "aistudio":     {"desc": "Google AI Studio (Drive export)", "kind": "zip"},
    "hermes":       {"desc": "Hermes agent session history",    "kind": "glob",
                     "paths": [HOME / ".hermes"]
                              + [h / ".hermes" for h in _wsl_windows_homes()],
                     "pattern": "state.db",                     "fn": parse_hermes,
                     "shallow": True},
}

# Match known export *stems* without requiring an extension: browsers (and
# "Save As") routinely drop or change .zip, and the contents are validated by
# sniff_zip() anyway (it reads zip magic bytes, not the name). The trailing
# "*.zip" stays as the generic catch-all for anything still carrying it.
ZIP_PATTERNS = ["data-*", "*chatgpt*", "*conversations*", "takeout-*",
                "Google AI Studio*", "drive-download-*", "*.zip"]

def sniff_zip(zpath):
    """Return source name for an export zip, or None."""
    try:
        with zipfile.ZipFile(zpath) as z:
            names = z.namelist()
            # AI Studio before the Gemini-html check: a Drive export of the
            # "Google AI Studio" folder is unambiguous from its root folder.
            if any(n.startswith("Google AI Studio/") for n in names):
                return "aistudio"
            if any("Gemini" in n and n.endswith(".html") for n in names):
                return "gemini-takeout"
            cj = next((n for n in names if n.endswith("conversations.json")), None)
            if not cj:
                return None
            with z.open(cj) as f:
                head = f.read(262144).decode("utf-8", "replace")
            if '"mapping"' in head:        return "chatgpt"
            if '"chat_messages"' in head:  return "claude-web"
    except (zipfile.BadZipFile, OSError):
        return None
    return None

def find_export_zips(roots, max_depth=2):
    """Targeted pattern-match for export zips. Returns [(path, source)]."""
    found, seen = [], set()
    for root in roots:
        root = Path(root).expanduser()
        if not root.is_dir(): continue
        for dirpath, dirs, files in os.walk(root):
            depth = len(Path(dirpath).relative_to(root).parts)
            if depth >= max_depth: dirs[:] = []
            for pat in ZIP_PATTERNS:
                for f in fnmatch.filter(files, pat):
                    p = Path(dirpath) / f
                    if p in seen: continue
                    seen.add(p)
                    src = sniff_zip(p)
                    if src: found.append((p, src))
    return found

# ── §4.55 scan-to-report (hybrid boundary, see §4.5 DECIDED) ─────────────────
# AI-ish stems only — deliberately NOT the generic "*.zip" catch-all, so random
# archives (drivers, app bundles) are not flagged as unknown AI candidates.
SPECIFIC_ZIP_PATTERNS = ["data-*", "*chatgpt*", "*conversations*", "takeout-*",
                         "Google AI Studio*", "drive-download-*"]

def _human_size(p):
    try: n = float(p.stat().st_size)
    except OSError: return "?"
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024: return f"{n:.0f} {unit}"
        n /= 1024
    return f"{n:.0f} TB"

def scan_for_report(roots, max_depth=2):
    """Classify export candidates WITHOUT importing. Returns (recognized, unknown):
      recognized = [(path, source)]  sniff_zip identified a known format -> fast lane
      unknown    = [(path, pattern)] matched an AI-ish stem but unrecognized -> agent lane
    """
    recognized, unknown, seen = [], [], set()
    for root in roots:
        root = Path(root).expanduser()
        if not root.is_dir(): continue
        for dirpath, dirs, files in os.walk(root):
            depth = len(Path(dirpath).relative_to(root).parts)
            if depth >= max_depth: dirs[:] = []
            for f in files:
                p = Path(dirpath) / f
                if p in seen: continue
                matched = next((pat for pat in SPECIFIC_ZIP_PATTERNS
                                if fnmatch.fnmatch(f, pat)), None)
                # recognise any .zip by content; only specific-pattern misses are "unknown".
                if not matched and not f.lower().endswith(".zip"): continue
                seen.add(p)
                src = sniff_zip(p)
                if src:           recognized.append((p, src))
                elif matched:     unknown.append((p, matched))
    return recognized, unknown

def write_scan_report(vault, roots):
    recognized, unknown = scan_for_report(roots)
    report = vault / "ai-scan-report.md"
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    L = [f"# AI Memory — Scan Report", "",
         f"Generated {now}. This scan imported **nothing** — it is a map so you (or",
         "your agent) can decide what to import, collect, or convert. See",
         "`docs/collect-with-agent.md` for how an agent can act on this file.", "",
         "## Recognized exports — ready to import"]
    if recognized:
        for p, src in recognized:
            L.append(f"- **{SOURCES[src]['desc']}** — `{p}` ({_human_size(p)})")
            L.append(f"  - import: `bash ai-memory-ingest.sh \"{vault}\" "
                     f"--source {src} --path \"{p}\"`")
    else:
        L.append("- (none found)")
    L += ["", "## Unknown candidates — looked AI-ish, format not recognized"]
    if unknown:
        for p, pat in unknown:
            L.append(f"- `{p}` ({_human_size(p)}) — matched `{pat}` but no "
                     "recognizable export inside.")
        L += ["", "Your agent can inspect these and help convert/import them — "
              "see `docs/collect-with-agent.md`."]
    else:
        L.append("- (none found)")
    _atomic_write(report, "\n".join(L) + "\n")
    hdr("Scan report")
    ok(f"Wrote {report}")
    info(f"Recognized: {len(recognized)}   Unknown AI-ish: {len(unknown)}   Imported: 0")
    info("scan-report mode: nothing was imported — review the file above.")
    return 0

def find_files(roots, pattern, max_depth=6, shallow=False):
    out = []
    for root in roots:
        root = Path(root).expanduser()
        if not root.exists(): continue
        if root.is_file():
            if fnmatch.fnmatch(root.name, pattern): out.append(root)
            continue
        try:
            for dirpath, dirs, files in os.walk(root):
                depth = len(Path(dirpath).relative_to(root).parts)
                if depth >= (1 if shallow else max_depth): dirs[:] = []
                dirs[:] = [d for d in dirs if d not in
                           ("node_modules", ".git", ".Trash")]
                out += [Path(dirpath) / f for f in fnmatch.filter(files, pattern)]
        except PermissionError:
            warn(f"Permission denied under {root}.")
            warn("macOS: approve the folder popup, or System Settings → Privacy &"
                 " Security → Files and Folders → Terminal → enable that folder."
                 " For --deep-scan, Full Disk Access may be needed.")
    return out

# ── runner ────────────────────────────────────────────────────────────────────
ZIP_FN = {"claude-web": parse_claude_zip, "chatgpt": parse_chatgpt_zip,
          "gemini-takeout": parse_takeout, "aistudio": parse_aistudio}

def warn_path_source_mismatch(source, path):
    """Light sanity check that an explicit --path plausibly matches --source.
    Non-blocking: warns and continues, since the user asked for this source."""
    spec = SOURCES.get(source, {})
    p = Path(path).expanduser()
    if not p.exists():
        warn(f"--path does not exist: {p}"); return
    kind = spec.get("kind")
    if kind == "zip":
        sniffed = sniff_zip(p)
        if sniffed and sniffed != source:
            warn(f"--path looks like a '{sniffed}' export, not --source '{source}'"
                 " — importing as requested; double-check this is what you meant.")
        elif sniffed is None:
            warn(f"--path is not a recognizable {source} export ZIP"
                 " — importing as requested.")
    elif kind == "dir" and not p.is_dir():
        warn(f"--source {source} expects a directory but --path is a file: {p}")
    elif kind == "glob":
        pat = spec.get("pattern", "")
        if p.is_file() and pat and not fnmatch.fnmatch(p.name, pat):
            warn(f"--path '{p.name}' doesn't match the expected '{pat}' for"
                 f" --source {source} — importing as requested.")

def run_source(name, out_root, explicit_path=None, scan_roots=None):
    spec = SOURCES[name]
    totals = _stats()
    def add(s):
        for k in totals: totals[k] += s.get(k, 0)
    if spec["kind"] == "zip":
        zips = [Path(explicit_path)] if explicit_path else \
               [p for p, src in find_export_zips([HOME / "Downloads"] + (scan_roots or []))
                if src == name]
        for z in zips:
            age = ""
            try:
                days = (datetime.datetime.now()
                        - datetime.datetime.fromtimestamp(z.stat().st_mtime)).days
                age = f" (modified {days} days ago)"
            except OSError: pass
            if explicit_path or ask_yn(f"Found {spec['desc']}: {z}{age} — import it?"):
                try: add(ZIP_FN[name](z, out_root))
                except Exception as e:
                    err(f"{name}: {e}"); totals["failed"] += 1
    elif spec["kind"] == "dir":
        roots = [Path(explicit_path)] if explicit_path else \
                [p for p in spec["paths"] if Path(p).exists()]
        for r in roots:
            try: add(spec["fn"](r, out_root))
            except Exception as e:
                err(f"{name}: {e}"); totals["failed"] += 1
    elif spec["kind"] == "glob":
        files = [Path(explicit_path)] if explicit_path else \
                find_files(list(spec["paths"]) + (scan_roots or []), spec["pattern"],
                           shallow=spec.get("shallow", False))
        for f in files:
            try: add(spec["fn"](f, out_root))
            except Exception as e:
                err(f"{name}: {e}"); totals["failed"] += 1
    return totals

def _index_meta(path, sub):
    """(title, date, source) for a conversation .md — header-aware, with fallback.
    Prefers the header write_conv emits (# Title / - source: / - created:); falls
    back to the subfolder (source) and the YYYY-MM-DD filename prefix (date) so it
    also handles agent-imported files that lack our header."""
    title = None; date = None; source = sub
    try:
        head = path.read_text(errors="replace")[:2000]
    except OSError:
        head = ""
    for line in head.splitlines():
        s = line.strip()
        if title is None and s.startswith("# "):
            title = s[2:].strip()
        elif s.startswith("- source:"):
            source = s.split(":", 1)[1].strip() or sub
        elif s.startswith("- created:"):
            date = s.split(":", 1)[1].strip()[:10]
    if not (date and re.match(r"\d{4}-\d{2}-\d{2}", date)):
        m = re.match(r"(\d{4}-\d{2}-\d{2})", path.name)
        date = m.group(1) if m else "undated"
    return (title or path.stem), date, source

def build_index(vault):
    """(Re)generate 05-AI-Sessions/INDEX.md from the .md files on disk. Derived,
    idempotent and source-agnostic — covers script- and agent-imported files alike,
    so 'imported-but-not-found' becomes a detectable mismatch (§4.3.1). Read on
    demand by the handover, not loaded into every prompt."""
    from collections import Counter, defaultdict
    out_root = vault / "05-AI-Sessions"
    by_source = defaultdict(list)
    for p in sorted(out_root.rglob("*.md")):
        if p.name == "INDEX.md":
            continue
        rel = p.relative_to(out_root)
        sub = rel.parts[0] if len(rel.parts) > 1 else "(loose)"
        title, date, source = _index_meta(p, sub)
        by_source[source].append((date, title, str(rel)))
    total = sum(len(v) for v in by_source.values())
    months = Counter(d[:7] for v in by_source.values() for d, _t, _r in v
                     if re.match(r"\d{4}-\d{2}", d))
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    L = ["# Memory Index — imported AI conversations", "",
         f"_AUTO-GENERATED by ai-memory-ingest v{VERSION} on {stamp}. Do not edit —",
         "regenerated on every `ingest` / `ingest --reindex` run._", "",
         f"**{total} conversations** across **{len(by_source)} source(s).**", "",
         "## By source", ""]
    for s in sorted(by_source):
        L.append(f"- **{s}** — {len(by_source[s])}")
    if months:
        L += ["", "## By month", ""]
        for m in sorted(months, reverse=True):
            L.append(f"- {m} — {months[m]}")
    L += ["", "## Conversations", ""]
    for s in sorted(by_source):
        L += [f"### {s}", ""]
        for date, title, rel in sorted(by_source[s], reverse=True):
            L.append(f"- `{date}` — {title}  ·  `05-AI-Sessions/{rel}`")
        L.append("")
    out_root.mkdir(parents=True, exist_ok=True)
    _atomic_write(out_root / "INDEX.md", "\n".join(L).rstrip() + "\n")
    return total

def main():
    global ASSUME_YES, WITH_CRON, AI_TITLES
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("positional", nargs="*")
    ap.add_argument("--source"); ap.add_argument("--path")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--local", action="store_true")
    ap.add_argument("--list-sources", action="store_true")
    ap.add_argument("--scan", action="append", default=[])
    ap.add_argument("--deep-scan", action="store_true")
    ap.add_argument("--scan-report", action="store_true")
    ap.add_argument("--reindex", action="store_true")
    ap.add_argument("--with-cron", action="store_true")
    ap.add_argument("--ai-titles", action="store_true")
    ap.add_argument("--yes", "-y", action="store_true")
    ap.add_argument("--help", "-h", action="store_true")
    ap.add_argument("--version", "-V", action="store_true")
    a = ap.parse_args()
    ASSUME_YES = a.yes
    WITH_CRON = a.with_cron
    AI_TITLES = a.ai_titles

    if a.version:
        print(f"ai-memory-ingest.sh v{VERSION}"); return 0
    if a.help:
        print("Usage: ai-memory-ingest.sh [vault] [export.zip] "
              "[--source NAME] [--path P] [--local] [--scan DIR] [--deep-scan] "
              "[--scan-report] [--reindex] [--with-cron] [--ai-titles] "
              "[--list-sources] [--yes]\n"
              "--local: sweep every LOCAL agent store (hermes, claude-code, codex, "
              "gemini-cli, …) — skips the zip/Downloads exporters. Used by the "
              "configure self-ingest hook (one OS-general, FDA-safe trigger).\n"
              "--with-cron: also vault openclaw cron/scheduler sessions "
              "(into openclaw-cron/; skipped by default).\n"
              "--scan-report: map exports/unknowns to <vault>/ai-scan-report.md, "
              "import nothing.\n--reindex: rebuild <vault>/05-AI-Sessions/INDEX.md "
              "from what's on disk, import nothing.\n"
              "--ai-titles: let your configured local model write short headings "
              "for untitled\n  conversations (raw-prompt fallbacks). Off by "
              "default — without it ingest is fully\n  offline. Uses "
              "AI_MEMORY_MODEL_URL/AI_MEMORY_MODEL, else .mcp/ai-config.json, "
              "else\n  localhost ollama; on failure falls back to raw-prompt "
              "titles.\nSee script header for details.")
        return 0
    if a.list_sources:
        print(f"\n{'source':<16} description")
        print("-" * 50)
        for k, v in SOURCES.items(): print(f"{k:<16} {v['desc']}")
        return 0

    pos = list(a.positional)
    zip_arg = None
    # Treat a trailing positional that is an existing FILE as the export to
    # import (sniff_zip identifies it by content). Don't require a .zip name —
    # a browser may have stripped it. A directory positional stays as the vault.
    if pos and (pos[-1].endswith(".zip") or Path(pos[-1]).expanduser().is_file()):
        zip_arg = pos.pop()
    vault = Path(pos[0]).expanduser() if pos else HOME / "Documents" / "ai-memory"
    if not vault.is_absolute(): vault = Path.cwd() / vault
    out_root = vault / "05-AI-Sessions"
    if not out_root.exists():
        err(f"Vault not found: {vault}")
        err(f"   Run setup first: bash ai-memory-setup.sh {vault}")
        return 1

    print()
    print(c("1", "╔══════════════════════════════════════════╗"))
    print(c("1", f"║   AI Memory Stack — Ingest v{VERSION:<13}║"))
    print(c("1", "╚══════════════════════════════════════════╝"))
    print()
    info(f"Vault: {vault}")
    if AI_TITLES:
        _ai_setup(vault)

    if a.reindex:                                  # rebuild INDEX.md only, import nothing
        n = build_index(vault)
        ok(f"Index rebuilt → {out_root}/INDEX.md  ({n} conversations)")
        return 0

    scan_roots = [Path(s).expanduser() for s in a.scan]
    if a.deep_scan:
        warn("Deep scan searches your ENTIRE home directory (never system areas).")
        warn("This can take a while and may trigger macOS permission prompts.")
        if ask_yn("Proceed with deep scan?", default=False):
            scan_roots.append(HOME)
        else:
            info("Deep scan cancelled — continuing with default discovery")

    # §4.1 WSL: a Windows user's exports usually live on the WINDOWS side
    # (/mnt/c/Users/<name>/Downloads), not in the WSL home where discovery looks
    # by default. Detect WSL and add the Windows Downloads to discovery — ask, or
    # auto-include under --yes. No-op when not on WSL.
    def _wsl_windows_downloads():
        import glob
        if not Path("/mnt/c").is_dir():
            return []
        # WSL marker: /proc/version usually carries "microsoft", but custom WSL
        # kernels may not — also check osrelease and $WSL_DISTRO_NAME so a clean
        # WSL never silently no-ops (BUG-2, live round 2026-06-16).
        marker = ""
        for _p in ("/proc/version", "/proc/sys/kernel/osrelease"):
            try:
                marker += Path(_p).read_text().lower()
            except OSError:
                pass
        if ("microsoft" not in marker and "wsl" not in marker
                and not os.environ.get("WSL_DISTRO_NAME")):
            return []
        # Skip Windows system/service profiles (not human users). Denylist,
        # case-insensitive — a real WSL run surfaced DefaultAppPool (IIS) slipping
        # through the original four (BUG-1, live round 2026-06-16).
        skip = {"public", "default", "default user", "all users",
                "defaultapppool", "wdagutilityaccount"}
        return [Path(d) for d in sorted(glob.glob("/mnt/c/Users/*/Downloads"))
                if Path(d).is_dir() and Path(d).parent.name.lower() not in skip]
    for _wd in _wsl_windows_downloads():
        if _wd in scan_roots:
            continue
        if ASSUME_YES or ask_yn(f"Running under WSL — also scan your Windows Downloads at {_wd}?"):
            scan_roots.append(_wd)
            ok(f"Including Windows Downloads in discovery: {_wd}")

    if a.scan_report:                              # §4.55 map, don't import
        return write_scan_report(vault, [HOME / "Downloads"] + scan_roots)

    results = {}
    if zip_arg:                                   # backward compatible: sniff & route
        src = sniff_zip(Path(zip_arg).expanduser())
        if not src:
            err(f"Could not identify {zip_arg} as a known export"); return 1
        info(f"Detected {SOURCES[src]['desc']}")
        results[src] = run_source(src, out_root, explicit_path=Path(zip_arg).expanduser())
    elif a.source:
        if a.source not in SOURCES:
            err(f"Unknown source '{a.source}' — see --list-sources"); return 1
        if a.path:
            warn_path_source_mismatch(a.source, a.path)
        results[a.source] = run_source(a.source, out_root,
                                       explicit_path=a.path, scan_roots=scan_roots)
    elif a.local:                                  # OS-general local sweep: every
        # directory/db-based agent store (hermes, claude-code, codex, gemini-cli,
        # …), skipping the zip/Downloads exporters. This is what the configure
        # self-ingest hook fires on session-start/end: one FDA-safe, no-scheduler
        # trigger that archives ALL local agents on this box, not just Hermes.
        hdr("Discovering LOCAL agent sources")
        for name, spec in SOURCES.items():
            if spec.get("kind") == "zip":
                continue
            results[name] = run_source(name, out_root, scan_roots=scan_roots)
    else:                                          # default = discover all
        hdr("Discovering sources")
        for name in SOURCES:
            results[name] = run_source(name, out_root, scan_roots=scan_roots)

    hdr("Summary")
    print(f"\n  {'source':<16} {'new':>5} {'updated':>8} {'skipped':>8} {'edited':>7} {'empty':>6} {'failed':>7}")
    print("  " + "-" * 62)
    tot = _stats()
    for name, s in results.items():
        # An explicitly requested --source always gets its row — an all-zero
        # result the user asked for must be visible, not silently dropped
        # (a Swedish takeout imported 0 with no trace, live round 2026-07-05).
        if any(s.values()) or a.source:
            print(f"  {name:<16} {s['new']:>5} {s['updated']:>8} {s['skipped']:>8} {s['edited']:>7} {s['empty']:>6} {s['failed']:>7}")
        for k in tot: tot[k] += s[k]
    print("  " + "-" * 62)
    print(f"  {'TOTAL':<16} {tot['new']:>5} {tot['updated']:>8} {tot['skipped']:>8} {tot['edited']:>7} {tot['empty']:>6} {tot['failed']:>7}\n")
    if tot["edited"]:
        warn(f"{tot['edited']} vault file(s) were edited by hand and left "
             "untouched — delete a file to let ingest re-import that conversation")
    # Honest exit code (v2.27): a run with failed conversations must not
    # exit 0 — a hook/cron caller has only the exit code to notice.
    rc = 1 if tot["failed"] else 0
    if rc:
        err(f"{tot['failed']} conversation(s)/source(s) FAILED to import — see errors above")
    if tot["new"] or tot["updated"]:
        bits = []
        if tot["new"]:     bits.append(f"{tot['new']} new")
        if tot["updated"]: bits.append(f"{tot['updated']} refreshed")
        ok(f"{', '.join(bits)} conversation(s) → {out_root}")
    elif tot["skipped"]:
        ok("Nothing new — everything already imported")
    else:
        info("Nothing found. Try --scan <dir>, --deep-scan, or --list-sources")
    print()
    # §4.3 post-import reachability check — a green "imported!" line is misleading
    # if a plain `hermes` can't reach the vault. Hermes' file tools root at the
    # directory it is LAUNCHED from, not at a path in config.yaml. Verify the
    # vault is pinned (launcher / TERMINAL_CWD); if not, say so loudly.
    def _memory_reachable(vault):
        vs = str(vault).rstrip("/")
        try:
            for line in (HOME / ".hermes" / ".env").read_text().splitlines():
                if line.strip().startswith("TERMINAL_CWD="):
                    val = line.split("=", 1)[1].strip().strip('"').strip("'")
                    if os.path.expanduser(val).rstrip("/") == vs:
                        return True
        except OSError:
            pass
        for rc in (".bashrc", ".zshrc", ".profile"):
            try:
                t = (HOME / rc).read_text()
            except OSError:
                continue
            if "ai-memory hermes launcher" in t and str(vault) in t:
                return True
        return False
    if tot["new"] or tot["updated"] or tot["skipped"]:
        if _memory_reachable(vault):
            ok("Reachability OK — a plain `hermes` is set to run from your vault.")
        else:
            warn("Heads-up: a plain `hermes` may NOT see what was just imported.")
            print("  Hermes searches the directory it is LAUNCHED from, not the vault.")
            print(f"  Fix once:  {c('1', 'bash ' + str(vault / '.tools' / 'ai-memory-configure.sh') + ' ' + str(vault))}")
            print("  (installs a vault launcher + TERMINAL_CWD in ~/.hermes/.env), or always")
            print(f"  start from the vault:  cd {vault} && hermes chat   (or .tools/resume.sh hermes)")
        print()
    # §4.3.1 — (re)build the import INDEX so a keyword-less "what do you remember?"
    # has a real manifest to read, not just a directory walk. Derived from disk, so
    # it also captures agent-imported files. (--scan-report returned earlier;
    # --reindex handled above — this is the normal-import path.)
    idx_n = build_index(vault)
    ok(f"Index updated → 05-AI-Sessions/INDEX.md  ({idx_n} conversations)")
    info(f"Verify memory is reachable from every door:  "
         f"{c('1', 'bash ' + str(vault / '.tools' / 'ai-memory-doctor.sh'))}")
    print()

    hdr("Next steps")
    import shutil, subprocess
    have_hermes = shutil.which("hermes") is not None
    remote = vault / ".tools" / "ai-memory-remote.sh"
    if ASSUME_YES or not (sys.stdin and os.path.exists("/dev/tty")):
        if have_hermes:
            print(f"  Start your agent:  {c('1', 'hermes chat')}  (from {vault})")
        else:
            print(f"  Install/relaunch a shell, then: {c('1', 'hermes chat')}")
        print(f"  Optional headless node: {c('1', 'bash ' + str(remote))}")
        # §B4: the LAST thing on screen is the literal next command
        print()
        print(c("1;32", "▶ NEXT — talk to your memory:") + "  "
              + c("1;36", "hermes chat") + f"   (from {vault})")
        print()
        return rc
    # Offer to launch hermes right here
    if have_hermes:
        # Default NO, and never under --yes: a non-interactive run must not
        # exec an interactive agent (auto-yes here hijacked a shared tmux pane
        # in the 2026-07-05 live round — the TUI wiped the run's own output).
        if not ASSUME_YES and ask_yn("Start your agent (hermes chat) now?", default=False):
            os.chdir(vault)
            try:
                os.execvp("hermes", ["hermes", "chat"])
            except OSError:
                err("Could not launch hermes — run 'hermes chat' from the vault.")
    else:
        info("'hermes' isn't on PATH in this shell yet.")
        info("Open a new terminal, then run:  hermes chat   (from the vault)")
    print()
    info(f"Optional — set up a headless/remote node later: bash {remote}")
    # §B4: the LAST thing on screen is the literal next command
    print()
    print(c("1;32", "▶ NEXT — talk to your memory:") + "  "
          + c("1;36", "hermes chat") + f"   (from {vault})")
    print()
    return rc

try:
    sys.exit(main())
except BrokenPipeError:
    sys.exit(0)
PYMAIN
