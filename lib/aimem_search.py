# =============================================================================
#  aimem_search.py — the python engine behind ai-memory-search.sh.
#  Run via the bash entrypoint (the public interface), never imported by it:
#  `bash ai-memory-search.sh …` execs `python3 <libdir>/aimem_search.py …`
#  with stdin left intact, so --hook still reads its payload from stdin.
#  Shares the query tokenizer with the ingest engine via aimem_common (same
#  directory). Python 3.8+ stdlib only.
# =============================================================================
import sys, os, re, json, argparse
import datetime as _dt
from pathlib import Path

from aimem_common import tokenize, default_vault

VERSION = "2.1"

# Recency ordinal (v2.1): a note's freshness as days since 2020-01-01, taken
# from its LAST-WRITE time (mtime) — i.e. when ingest last wrote it because the
# conversation grew. mtime beats the filename's YYYY-MM-DD prefix here: that
# prefix is the session's START date, so a long-running session (started weeks
# ago, still appending today's facts) would look stale by filename yet carries
# the freshest content. Filename date is only a fallback when mtime is
# unreadable. Bounded well under the frequency slot so it ranks ABOVE raw
# hit-frequency but BELOW distinct-term coverage — see run_search's packing.
_REC_EPOCH = _dt.date(2020, 1, 1).toordinal()

def _recency_ord(path):
    try:
        return max(0, _dt.date.fromtimestamp(path.stat().st_mtime).toordinal()
                      - _REC_EPOCH)
    except (OSError, ValueError, OverflowError):
        pass
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", path.name)
    if m:
        try:
            return max(0, _dt.date(int(m.group(1)), int(m.group(2)),
                                   int(m.group(3))).toordinal() - _REC_EPOCH)
        except ValueError:
            pass
    return 0

def run_search(sess, terms):
    """Score every 05-AI-Sessions/*.md by DISTINCT query terms covered, then
    RECENCY (newer wins), then hit frequency. Returns a ranked list of
    (score, nterms, path, hit_terms, snips).

    Recency was added in v2.1: when the vault holds both an OLD and a NEW
    statement of a fact that changed (a job renamed, an agent that moved host),
    the two match a query equally on terms — and the old, more-repeated one used
    to win on frequency and get injected as 'the answer'. Newer now breaks that
    tie. Term coverage still dominates, so a richer canonical note is unaffected;
    recency only decides between equally-relevant hits."""
    results = []
    for path in sess.rglob("*.md"):
        if path.name == "INDEX.md":
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        low = text.lower()
        hit_terms, total = [], 0
        for t in terms:
            c = low.count(t)
            if c:
                hit_terms.append(t); total += c
        if not hit_terms:
            continue
        lines = text.splitlines()
        scored_lines = []
        for i, ln in enumerate(lines):
            ll = ln.lower()
            d = sum(1 for t in hit_terms if t in ll)
            if d:
                scored_lines.append((d, i + 1, ln.strip()))
        scored_lines.sort(key=lambda x: (-x[0], x[1]))
        # Packing (v2.1): coverage (hit_terms) is the dominant digit block, then
        # recency (0..~4000 days), then frequency (<100000). Each block is scaled
        # so it can never bleed into the one above: coverage >> recency >> freq.
        score = (len(hit_terms) * 10**10
                 + _recency_ord(path) * 10**5
                 + min(total, 99999))
        results.append((score, len(hit_terms), path, hit_terms, scored_lines[:3]))
    results.sort(key=lambda r: -r[0])
    return results

# ── hook mode (--hook): the model-agnostic path ──────────────────────────────
# Live tests proved small models will not CALL a search tool from SOUL guidance
# (0/9). So instead of relying on the model, a hermes `pre_llm_call` shell hook
# runs THIS search on the user's message and INJECTS the top hits into the turn
# — the model just reads them. Hermes passes the turn as JSON on stdin (keys in
# `extra`: user_message, turn_type, conversation_history, ...); a
# `{"context": "..."}` on stdout is appended to the user message. We stay silent
# (no injection) unless a hit is strong, so ordinary chit-chat is untouched and
# every turn is not inflated (hermes spills oversized context to disk anyway).
HOOK_MIN_TERMS = 2       # top hit must cover >= this many DISTINCT query terms
HOOK_MAX_CHARS = 1500    # keep the injected blob small (prompt-cache friendly)

# "How much did it cost" answers often sit on a line whose currency word the
# QUERY missed ("dollar" asked, "USD" written), so the term-ranked snippets can
# skip the very line with the number. Pull value/price lines from the top file
# regardless of query-term match (live 2026-07-08: glm4 got the product right
# from an injection but said the price was "not specified" — it wasn't in the
# snippet).
_VALUE_RE = re.compile(
    r"[€$£]\s?\d"
    r"|\d[\d\s.,]*\s?(?:kr|sek|usd|eur|dollar|euro|kronor)\b"
    r"|\b(?:usd|sek|eur|dollar|euro)\b[\s:]*[$€£]?\s?\d"
    r"|\b(?:pris|price|cost|kostar|kostade|kostnad)\b[^\n]*\d",
    re.I)

# Time/meta memory questions ("what did we talk about yesterday / last week")
# have no strong TOPIC terms, so the term search stays silent and the model
# falls back to hermes' own session_search (which does not see the vault) — the
# live gap the user hit 2026-07-08. For these, inject a dated list of RECENT
# conversations from the vault INDEX instead, so the model can actually answer.
_META_RE = re.compile(
    r"\b(ig[åa]r|f[öo]rrg[åa]r|h[äa]romdagen|nyligen|p[åa] sistone|senaste|"
    r"f[öo]rra veckan|senaste veckan|denna vecka|i veckan|yesterday|last week|"
    r"recently|the other day|this week)\b"
    r"|\b(vad|vilka|n[åa]r) .{0,30}(pratade|snackade|diskuterade|sa|gjorde|tog upp) vi\b"
    r"|what did we (talk|discuss|do|say|cover)\b"
    r"|vad (har vi|gjorde vi|pratade vi)\b",
    re.I)

# Temporal/meta filler that must NOT count as topic terms — else "forra veckan
# pratade" spuriously matches any file containing "veckan" and the topic branch
# wins over the recent-conversations branch (live 2026-07-08).
_META_WORDS = set("""
igar igår forrgar förrgår forra förra vecka veckan haromdagen häromdagen
nyligen sistone senaste yesterday week last recently discuss discussed talk
talked pratade snackade diskuterade prata snacka diskutera sade
""".split())

def _meta_window(msg):
    """(label, keep(date_str)->bool | None). None = generic 'recent', no date filter."""
    m = msg.lower()
    today = _dt.date.today()
    day = lambda n: (today - _dt.timedelta(days=n)).isoformat()
    if re.search(r"\big[åa]r\b|\byesterday\b", m):
        d = day(1); return (f"yesterday ({d})", lambda ds: ds == d)
    if re.search(r"f[öo]rrg[åa]r|day before yesterday", m):
        d = day(2); return (f"({d})", lambda ds: ds == d)
    if re.search(r"f[öo]rra veckan|senaste veckan|last week|denna vecka|this week|i veckan", m):
        lo, hi = day(8), day(0); return ("the last week", lambda ds: lo <= ds <= hi)
    if re.search(r"h[äa]romdagen|nyligen|p[åa] sistone|recently|the other day|\bsenaste\b", m):
        lo = day(5); return ("the last few days", lambda ds: ds >= lo)
    return ("recent", None)

def _recent_conversations_context(vault, msg):
    idx = vault / "05-AI-Sessions" / "INDEX.md"
    if not idx.is_file():
        return ""
    label, keep = _meta_window(msg)
    entries, cur_src = [], "?"
    for ln in idx.read_text(encoding="utf-8", errors="replace").splitlines():
        s = ln.strip()
        mh = re.match(r"###\s+(.+)$", s)
        if mh:
            cur_src = mh.group(1).strip(); continue
        me = re.match(r"-\s+`(\d{4}-\d{2}-\d{2})`\s*[—–-]\s*(.+?)\s+·\s+`", s)
        if me:
            entries.append((me.group(1), me.group(2).strip(), cur_src))
    if not entries:
        return ""
    entries.sort(reverse=True)                    # newest date first
    picked = [e for e in entries if keep(e[0])][:12] if keep else entries[:10]
    note = ""
    if not picked:                                # window empty → most-recent + note
        picked = entries[:6]
        note = f" — nothing filed under {label}; showing the most recent instead"
    lines = [f"[Recent conversations in the user's own memory ({label}){note}. Use these "
             "to answer what you talked about / did; each is `date — title (source)`:]"]
    for date, title, src in picked:
        t = title if len(title) <= 90 else title[:90] + "…"
        lines.append(f"- {date} — {t} ({src})")
    return "\n".join(lines)[:HOOK_MAX_CHARS]

def _hook_user_message(payload):
    """Pull the latest user text out of a pre_llm_call payload (defensive:
    hermes nests it under `extra`, older/other shapes vary)."""
    def _txt(v):
        if isinstance(v, str):
            return v
        if isinstance(v, dict):
            return v.get("content") or v.get("text") or ""
        if isinstance(v, list) and v:
            # conversation_history: last user turn
            for m in reversed(v):
                if isinstance(m, dict) and str(m.get("role", "")).lower() == "user":
                    return _txt(m.get("content") or m.get("text") or "")
            return _txt(v[-1])
        return ""
    for scope in (payload.get("extra") or {}), payload:
        if not isinstance(scope, dict):
            continue
        if scope.get("turn_type") and str(scope["turn_type"]).lower() != "user":
            return ""          # tool-result / non-user turn → do not inject
        for k in ("user_message", "user_msg", "message", "conversation_history"):
            t = _txt(scope.get(k))
            if t and t.strip():
                return t.strip()
    return ""

def run_hook(vault):
    """Read a pre_llm_call payload on stdin, emit {"context": ...} or nothing."""
    _dbg = os.environ.get("AI_MEMORY_HOOK_DEBUG")
    def dbg(m):
        if _dbg: print(f"[hook] {m}", file=sys.stderr)
    sess = vault / "05-AI-Sessions"
    try:
        payload = json.load(sys.stdin)
    except Exception as e:
        dbg(f"json.load failed: {e}"); return 0
    if not sess.is_dir():
        dbg(f"sess not dir: {sess}"); return 0
    msg = _hook_user_message(payload)
    if not msg:
        dbg("no user message"); return 0
    is_meta = bool(_META_RE.search(msg))
    terms = tokenize(msg)
    if is_meta:                                  # drop temporal filler so a vague
        terms = [t for t in terms if t not in _META_WORDS]   # meta Q isn't a topic
    dbg(f"msg={msg!r} terms={terms} meta={is_meta}")
    if len(terms) < HOOK_MIN_TERMS and not is_meta:
        dbg("too few terms, not meta"); return 0     # too vague (e.g. "hej")
    results = run_search(sess, terms) if terms else []
    best = results[0][1] if results else 0
    dbg(f"results={len(results)} best={best}")
    # A strong TOPIC hit wins; else a time/meta question gets recent conversations.
    if best < HOOK_MIN_TERMS:
        if is_meta:
            ctx = _recent_conversations_context(vault, msg)
            if ctx:
                dbg("meta → recent conversations injected")
                print(json.dumps({"context": ctx})); return 0
        dbg("no strong hit"); return 0               # stay silent
    rel = lambda p: str(p.relative_to(vault))
    lines = ["[Relevant memory from the user's own vault — they may be asking "
             "about this. Answer from it if it fits; ignore if not:]"]
    for ri, (score, nterms, path, hit_terms, snips) in enumerate(results[:3]):
        if nterms < HOOK_MIN_TERMS:
            break
        lines.append(f"- {rel(path)}")
        shown = set()
        for cnt, lineno, snip in snips[:3]:
            shown.add(lineno)
            if len(snip) > 200:
                snip = snip[:200] + "…"
            lines.append(f"    L{lineno}: {snip}")
        # Top file only: also surface up to 2 value/price lines the query terms
        # may have missed (currency word mismatch), so "what did it cost" answers.
        if ri == 0:
            try:
                flines = path.read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError:
                flines = []
            added = 0
            for i, ln in enumerate(flines):
                if added >= 2:
                    break
                if (i + 1) in shown or not _VALUE_RE.search(ln):
                    continue
                s = ln.strip()
                if len(s) > 200:
                    s = s[:200] + "…"
                lines.append(f"    L{i+1}: {s}")
                added += 1
    context = "\n".join(lines)[:HOOK_MAX_CHARS]
    print(json.dumps({"context": context}))
    return 0

def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("positional", nargs="*")
    ap.add_argument("--query")
    ap.add_argument("--top", type=int, default=5)
    ap.add_argument("--hook", action="store_true")
    ap.add_argument("--help", "-h", action="store_true")
    ap.add_argument("--version", "-V", action="store_true")
    ap.add_argument("--yes", "-y", action="store_true")   # accepted for family symmetry
    a = ap.parse_args()

    if a.version:
        print(f"ai-memory-search.sh v{VERSION}"); return 0
    if a.help:
        print('Usage: ai-memory-search.sh [vault] "your topic" [--top N]\n'
              '       ai-memory-search.sh --hook [vault]   (reads a hermes\n'
              '         pre_llm_call payload on stdin; emits {"context":...} to inject)\n'
              "Ranks 05-AI-Sessions/*.md by how many distinct query terms each\n"
              "file contains, prints the top files with answer-bearing snippets.")
        return 0

    pos = list(a.positional)
    query = a.query
    vault = None
    # A positional that is an existing directory is the vault; the rest is the query.
    rest = []
    for p in pos:
        if vault is None and Path(p).expanduser().is_dir() and (Path(p).expanduser() / "05-AI-Sessions").exists():
            vault = Path(p).expanduser()
        else:
            rest.append(p)
    if query is None and rest:
        query = " ".join(rest)
    if vault is None:
        vault = default_vault()

    # Hook mode short-circuits: query comes from the stdin payload, not args.
    if a.hook:
        return run_hook(vault)
    if not query or not query.strip():
        print("ai-memory-search: no query given. Usage: ai-memory-search.sh [vault] \"topic\"",
              file=sys.stderr)
        return 1
    sess = vault / "05-AI-Sessions"
    if not sess.is_dir():
        print(f"ai-memory-search: vault not found ({sess} missing). Run setup first.",
              file=sys.stderr)
        return 1

    terms = tokenize(query)
    if not terms:
        print(f'MEMORY SEARCH — query: "{query}"\nNo searchable terms in the query '
              "(all stopwords). Try naming the topic, brand, or year.")
        return 0

    results = run_search(sess, terms)
    rel = lambda p: str(p.relative_to(vault))

    print(f'MEMORY SEARCH — query: "{query}"')
    print(f"terms: {', '.join(terms)}")
    if not results:
        print(f"\nNo file in 05-AI-Sessions matched ANY of those terms. The topic\n"
              "may use different words — try synonyms, a brand/model name, or a year.\n"
              "(This really searched every file; it is not a tool that can't see the vault.)")
        # Still show what the index knows, if present.
        idx = sess / "INDEX.md"
        if idx.exists():
            print(f"\nThe index exists at {rel(idx)} — skim its titles for the topic.")
        return 0

    best = results[0][1]
    print(f"{len(results)} file(s) matched; top hit covers {best}/{len(terms)} terms.\n")
    for rank, (score, nterms, path, hit_terms, snips) in enumerate(results[:a.top], 1):
        print(f"{rank}. [{nterms}/{len(terms)} terms] {rel(path)}")
        print(f"   matched: {', '.join(hit_terms)}")
        for d, lineno, snip in snips:
            if len(snip) > 200:
                snip = snip[:200] + "…"
            print(f"   L{lineno}: {snip}")
        print()
    print("Read the top file(s) above and answer from them. If none looks right,\n"
          "re-run with different words (synonyms, brand, model number, year).")
    return 0

if __name__ == "__main__":
    sys.exit(main())
