#!/usr/bin/env bash
# =============================================================================
#  ai-memory-search.sh  v1.4
#  v1.4: --hook handles TIME/META memory questions ("what did we talk about
#        yesterday / last week / recently"). These have no strong topic term,
#        so the model used to fall back to hermes' own session_search (blind to
#        the vault) and find nothing (live gap 2026-07-08). Now the hook detects
#        the time/meta phrasing and injects a dated list of RECENT conversations
#        from the vault INDEX (windowed to yesterday / last week / etc.).
#  v1.3: --hook also surfaces VALUE/PRICE lines from the top file even when the
#        query word missed them (asked "dollar", file wrote "USD"). Live proof:
#        with v1.2 glm4 read the injection and named the product but said the
#        price was "not specified" — the term-ranked snippet had skipped the
#        "$1,880" line. Now "what did it cost" answers land.
#  v1.2: PORTABILITY FIX — the v1.1 fd-3 source trick (python3 /dev/fd/3 3<<EOF)
#        read stdin on Linux but SILENTLY failed on macOS bash 3.2 (the Mac
#        mini), so --hook produced nothing there (live 2026-07-08). The source
#        is now written to a temp file and run from there — stdin stays free for
#        the hook payload on BOTH platforms.
#  v1.1: NEW --hook mode — a hermes `pre_llm_call` shell hook that reads the
#        turn on stdin, searches the vault for the user's message, and INJECTS
#        the top hits into the turn. This is the MODEL-AGNOSTIC path: live tests
#        proved small models will not CALL a search tool from SOUL (0/9), so we
#        stop relying on the model — the search runs automatically and the model
#        just reads the results. Silent (no injection) on weak/no hits.
#  Deterministic memory retrieval for the AI Memory Stack — ONE command an
#  agent (any model, however small) can call instead of hand-rolling a
#  multi-term grep strategy it may not follow.
#
#  Why this exists (§4.5 — deterministic work is a script, not model reasoning):
#  live tests (2026-07-07) showed small local models FAIL vault recall not
#  because the data is missing but because they give up after one grep, pick a
#  weak keyword, or invoke a "memory" tool that reads the agent's own session
#  db. The persistent, multi-term, INDEX-aware search is DETERMINISTIC — so it
#  belongs in a script. The model supplies a topic; this returns ranked files
#  with the answer-bearing lines already surfaced.
#
#  What it does: tokenizes the query, scores every 05-AI-Sessions/*.md file by
#  how many DISTINCT query terms it contains (coverage dominates) then by hit
#  frequency, and prints the top files with the lines that match the most terms
#  — so the answer is usually visible in the snippet without opening the file.
#
#  Usage:
#    bash ai-memory-search.sh [vault] "your topic in your own words"
#    bash ai-memory-search.sh --query "..." [--top N] [vault]
#  Prints ranked hits to stdout. Exit 0 with hits, 0 with a clear "no match"
#  line (never a silent empty), 1 only on a usage/vault error.
# =============================================================================
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 1; }

# The python source is written to a temp FILE and run from there — NOT piped on
# stdin (`python3 - << EOF`), because that makes the heredoc BE stdin and the
# hook's payload (piped in for --hook mode) would never arrive. The fd-3 trick
# (`python3 /dev/fd/3 3<<EOF`) reads stdin correctly on Linux but silently fails
# on macOS bash 3.2 (the mini) — the temp file works on both (live 2026-07-08).
_AIMS_PY=$(mktemp 2>/dev/null || echo "/tmp/ai-memory-search.$$.py")
cat > "$_AIMS_PY" <<'PYMAIN'
import sys, os, re, json, argparse
import datetime as _dt
from pathlib import Path

VERSION = "1.4"
HOME = Path.home()

# Grammatical/filler words only — NOT domain words. Dropping "unicycle" or
# "december" would defeat the whole point; we only strip words that match
# everything (pronouns, articles, question words) in Swedish + English.
STOPWORDS = set("""
a an the of to in on at for and or but with without from by as is are was were
be been being do does did have has had will would can could should may might
i you he she it we they me my your our their this that these those there here
what which who whom whose when where why how not no yes if then than so such
vad vem vilken vilket vilka nar var vart varfor hur och eller men med utan
fran av som ar jag du han hon den det vi de mig min mitt dina er ett en till
pa om att har dar over under samt vara vart deras denna detta dessa kan ska
skall vill fick finns gjorde blev
""".split())

def tokenize(q):
    toks, seen = [], set()
    for raw in re.findall(r"[0-9a-zA-Zåäöéüø,\.]+", q.lower()):
        # keep 4-digit years / numbers with separators as one token, else split
        for t in re.findall(r"[0-9]{4,}|[a-zåäöéüø]{3,}|[0-9][0-9,\.]{2,}[0-9]", raw):
            t = t.strip(",.")
            if len(t) < 3 or t in STOPWORDS or t in seen:
                continue
            seen.add(t); toks.append(t)
    return toks

def run_search(sess, terms):
    """Score every 05-AI-Sessions/*.md by DISTINCT query terms covered (then hit
    frequency). Returns a ranked list of (score, nterms, path, hit_terms, snips)."""
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
        score = len(hit_terms) * 100000 + min(total, 99999)
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
        vault = HOME / "Documents" / "ai-memory"

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

sys.exit(main())
PYMAIN
# Run the source file with stdin left intact (so --hook reads the payload),
# then clean up. Non-exec + rc capture so `set -e` can't skip the cleanup.
_rc=0
python3 "$_AIMS_PY" "$@" || _rc=$?
rm -f "$_AIMS_PY"
exit $_rc
