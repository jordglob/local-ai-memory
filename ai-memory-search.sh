#!/usr/bin/env bash
# =============================================================================
#  ai-memory-search.sh  v1.0
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

# Family convention (§2.8): self-copy into $VAULT/.tools/ so every door finds
# the same tool. Resolve the vault from args first (mirrors the python arg parse).
exec python3 - "$@" << 'PYMAIN'
import sys, os, re, argparse
from pathlib import Path

VERSION = "1.0"
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

def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("positional", nargs="*")
    ap.add_argument("--query")
    ap.add_argument("--top", type=int, default=5)
    ap.add_argument("--help", "-h", action="store_true")
    ap.add_argument("--version", "-V", action="store_true")
    ap.add_argument("--yes", "-y", action="store_true")   # accepted for family symmetry
    a = ap.parse_args()

    if a.version:
        print(f"ai-memory-search.sh v{VERSION}"); return 0
    if a.help:
        print('Usage: ai-memory-search.sh [vault] "your topic" [--top N]\n'
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

    # Score every markdown file: coverage (distinct terms) dominates, then hits.
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
        # Best snippet lines: those containing the most DISTINCT query terms.
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
