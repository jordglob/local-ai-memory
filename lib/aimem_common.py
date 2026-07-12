# =============================================================================
#  aimem_common.py — shared helpers for the AI Memory Stack's python engines
#  (lib/aimem_ingest.py and lib/aimem_search.py import from here).
#
#  Plain Python 3.8+ stdlib only — this must run on a fresh box's system
#  python3, no pip installs. Installed to <vault>/.tools/lib/ alongside the
#  bash entrypoints by setup/configure; the entrypoints resolve this dir as
#  <script_dir>/lib first, then <vault>/.tools/lib.
# =============================================================================
import re
import os
import tempfile
from pathlib import Path


def default_vault():
    """The stack's default vault location when no vault argument is given."""
    return Path.home() / "Documents" / "ai-memory"


# ── secret-scrub ──────────────────────────────────────────────────────────────
# The vault is the artifact that gets synced, exported and backed up — the
# project's keystone promise is "secrets never travel". But people PASTE keys
# into chats, and a faithful archive would carry them along. Redact before
# anything is written. Conservative, high-confidence patterns only: silently
# mangling prose would be worse than missing an exotic token format.
# NOTE: ai-memory-sync.sh carries the same set as a grep ERE (SECRET_ERE);
# tests/run.sh fails the suite if the two drift.
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


# ── query tokenizer (search + hook) ──────────────────────────────────────────
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


# ── filenames / writes ────────────────────────────────────────────────────────
def slugify(s, n=55):
    s = re.sub(r"[^\w\s-]", "", s or "untitled", flags=re.UNICODE).strip()
    return (re.sub(r"[\s_]+", "-", s)[:n].strip("-") or "untitled").lower()


def _atomic_write(path: Path, text: str):
    """EVERY vault write goes through here (ingest v2.27): tempfile in the SAME
    dir + os.replace, so a crash / full disk / parallel run never leaves a
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
