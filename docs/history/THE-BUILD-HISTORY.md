# From a Chat Question to a Self-Healing Memory — The Complete Build Log

*A step-by-step history of how `local-ai-memory` was built, reconstructed from the
project's own archived conversations and version ledger. Every date and version is
real. The through-line: almost nothing here was designed on paper and then built —
it was **discovered by running it** on real machines and fixing whatever broke.*

---

## Phase 0 — Genesis (2026-06-10, in a chat)

It did not start with code. It started with a question typed into claude.ai:

> *"Looking for the latest local memory options for AI. Compare mem-agent with
> others on the forums."*

What came back was a survey of the 2025–2026 landscape — mem-agent (Dria), Mem0,
MemOS, Letta/MemGPT, Cognee, Zep — most of them promising vector databases,
knowledge graphs, and "memory operating systems." But buried in the comparison
was the finding that decided everything that followed:

> Letta's own LoCoMo benchmark showed agents using **simple filesystem operations
> (grep, search_files) reached 74% — higher than Mem0's specialised graph memory
> (68.5%).** Infrastructure isn't the bottleneck; how retrieval is used in
> practice is.

That single result is the seed of the whole project. If plain grep over plain
files beats a graph database, then the right design isn't a clever store — it's
**markdown files a small model can search.** No vector DB. No graph. Just text,
owned by you, on your disk. The next question in that same chat — *"compare this
with Obsidian"* — set the shape: an Obsidian-style vault of linked markdown notes.

## Phase 1 — First code, and the core-promise bug (v1–v8, June 15–16)

Five days later the idea became a bundle. From the start it was built by **two
Claudes in tandem**: "WEB" (Claude in chat) wrote and updated the spec; "CC"
(Claude Code) built the scripts and live-tested them on real hardware. They
ping-ponged — spec finding → code fix → live run → new spec finding.

- **v1–v2 (06-15):** the first consolidated bundle (configure, ingest, setup),
  then immediately *generalised for any hardware* — machine-specific paths and a
  personal GitHub handle stripped out, a "who it's for" (reviving old hardware)
  and a design philosophy added. It became a **tool**, not a personal script.
- **v3–v4 (06-15):** the first live run exposed the **core-promise bug**: a plain
  `hermes` invocation searched the *current directory*, not the vault — so the
  agent literally could not find the memory it was supposed to have. Before: "NONE
  FOUND." The fix was a `hermes()` launcher that roots the agent at the vault, plus
  a post-import reachability check. After: 19 files found. The whole product hung
  on this one bug.
- **v5–v8 (06-15/16):** the portability layer, discovered on WSL — dependency
  installs racing the apt lock, `/mnt/c` Windows exports, atomic `config.yaml`
  writes with read-back verification (catching a "configure never wrote the
  config" bug), and `--scan-report`, which maps a messy folder of unknown exports
  without importing anything. Each one was a live-run casualty, not a planned
  feature.

## Phase 2 — The Keystone (v13–v21, June 18)

**v13 was the milestone:** the first end-to-end live run on real Apple Silicon
(an M2 Pro). setup → configure → ingest (8 conversations auto-imported from the
box's own history) → Hermes answering via local Ollama. A working local AI memory,
on a real Mac, reachable on the LAN.

And it immediately revealed the deepest problem, christened **the Keystone**: the
shell door worked, but the **web dashboard was memory-blind** — it launched from
its install directory and never saw the vault. Worse, live use surfaced a truth
that reframed the entire project:

> Same wrong directory, same vault, same orientation file — **only the model
> changed.** qwen3.5 → *zero* tool calls (it hallucinated a grep, twice, then
> claimed the history was empty). claude-haiku-4.5 → *six real tool calls*, ran
> the actual grep, cited the real files.

The fix (v14–v16) was **`SOUL.md`** — a compact, always-injected orientation that
travels into every system prompt no matter which door the agent comes through: *you
have a vault at this absolute path, here is the user, here is the index, SEARCH
before you say you don't know, and actually CALL the tool — don't describe it.*
v15 hardened it (an absent index must trigger `ls -R`, never a false "it's empty");
v16 closed the dashboard door for good (export `TERMINAL_CWD` so the dashboard,
which ignores cwd, inherits the vault via env). v18–v21 finished the trio: a
**model-floor warning**, a **`doctor`** per-door verifier, and **vault
migration/restore**. The lesson carved out here — *the resident model's capability
is decisive, not optional* — would echo all the way to this week's recall eval.

## Phase 3 — Hardening and growth (v22–v37, July 1–7)

With the core proven, the project widened:

- **v22 (07-01):** a review-driven security and correctness pass across the whole
  stack.
- **v23–v25:** `ai-memory-mux.sh` (a tmux cockpit — the 7th family script), and
  Claude Code promoted to a first-class ingest source.
- **v26–v27:** the **memory loop closed** (the agent's own chats get ingested back
  into the vault) and **secret-scrubbing** added on import; then `ai-memory-sync.sh`
  (the 8th script) for a central hub-and-spoke vault.
- **v28–v37 (07-05/07):** more sources (Gemini takeout, Google AI Studio — a 13th
  source), CRLF normalisation for Windows transcripts, an openclaw scheduler-noise
  filter, and an `--ai-titles` feature (with three follow-up fixes when a single
  blank model reply kept benching the whole run — every one found by a live run).

## Phase 4 — The recall pillar (v38–v49, July 7–10)

This is where "the model must search" became "the system searches *for* the model":

- **v38–v41:** the SOUL handover was steered, version by version, toward the
  filesystem tools — because live tests kept proving that weak models won't call a
  search tool from guidance alone.
- **v42–v44:** `ai-memory-search.sh` — a real lexical search engine over the vault.
- **v43 (the pivotal one):** the **`--hook`**. Since small models won't reliably
  *call* a tool, a pre-LLM-call hook runs the search on the user's message and
  **injects the top hits straight into the turn.** The model doesn't have to
  choose to remember — the memory is already in front of it. This is the single
  most important idea in the whole recall design.
- **v46:** the hook learned to answer time/meta questions ("what did we talk about
  last week?") from a dated index.
- **v48–v49:** the **self-ingest loop** — the agent archives its own conversations
  automatically, so the memory grows without anyone running a command.

## Phase 5 — MoA, review, and consolidation (v50–v51, July 10–12)

- **v50:** validated **Mixture-of-Agents** presets for hard questions, and a
  four-angle external-review hardening round (identity/atomicity in ingest,
  lockout-proofing, onboarding, docs-truth-sync).
- **v51:** the grown-up refactor — the remote/netboot layer split into a companion
  repo (so nothing in the main repo can lock you out of a machine), the embedded
  Python engines **extracted to `lib/`** (unit-testable at last), a real user
  **manual**, and the versioning **collapsed from zip bundles to git tags + a
  changelog.** The zip-bundle era (v1–v50) was frozen into the ledger this history
  is partly reconstructed from.

## Phase 6 — The maintenance marathon (v52–v54, July 14–16)

The most recent chapter was less about new features and more about the system
learning to *survive itself* — and it exposed a run of failures that had all been
hiding behind green status lights:

- **ingest v3.1 (07-14):** the "never overwrite hand-edits" guard had a fatal
  flaw — it re-derived each note's hash by round-tripping rendered markdown back to
  source, and one cleaning change made it flag **every** note as edited, silently
  freezing the vault for days. Conversation notes are generated artifacts; the
  guard was deleted and notes now always regenerate.
- **sync v1.3 (07-15):** a stale clone was overwriting the central's *newer* tools
  every night, walking the version backwards while preserved timestamps hid it. The
  install is now gated on a strict version check.
- **search v2.1 — recency (07-16):** recall was surfacing the *older* version of a
  changed fact; freshness now breaks the tie.
- **search v2.2 — entities (07-16):** the curated, authoritative notes weren't even
  being searched. Now they are, as a separate pool — and a semantic/embedding
  alternative was **built as a probe, measured, and rejected** for not being good
  enough to justify its cost.
- **Self-healing:** a health check that emits machine-readable alarm codes, a
  dispatcher that maps each to an idempotent playbook, runs it, re-checks, and
  escalates only what's still broken. The week's fires became one-line playbook
  entries — the mechanism by which the system's need for a smart operator shrinks
  over time.

And the honest coda from the recall eval: the resident local model scored **2.5/8**
and sometimes answered with a menu. The north star was reframed from "the agent
runs everything itself" to "the system self-heals the known and cleanly escalates
the unknown."

---

## Where it stands

From a chat question on 2026-06-10 to a tagged **v54** on 2026-07-16: a
multi-source ingestion pipeline, a lexical recall hook that feeds a small model its
own past, secret-scrubbing, hub-and-spoke sync, git-versioned history, a
119-test suite, and a self-healing maintenance layer — all over plain markdown you
own, searchable with grep, exactly as that first benchmark result predicted.

The next chapter is already written down: a **clean-room run on a fresh Linux box**,
where most of the platform-specific ghosts simply won't exist. If this history
taught anything, it's that the code will be fine — and something entirely
unexpected will break on first contact with real hardware. It always has. That's
the project.

---

## The cost, in hours

The archive puts real numbers on it: from the genesis chat on **2026-06-10** to
tag **v54** on **2026-07-16** — about **five weeks**, **54 package versions**, and
a ledger where nearly every entry ends in *"live-verified on real hardware."* So:

**The builder's hours.** Across those five weeks — the research, the two-Claude
spec/code ping-pong, the ingest and sync work, the model-cost study, the recall
tuning, and the maintenance marathon — roughly **~100 hours.** A real slice of
that wasn't building the thing; it was debugging the ground it stood on, one
platform-specific surprise at a time, exactly as the version ledger records.

**A pro dev today (2026), sane infra, AI-assisted:** about **50 hours.** The whole
stack — 13-source ingest, the recall hook, sync, self-heal, ~120 tests — is maybe
a week and a half of focused work for someone who knows the tools and isn't
discovering each requirement by tripping over it on a live box.

**A pro dev five years ago (2021):** **250–350 hours** — and a very different
project. In 2021 there was no ambient LLM to co-write the code, no one-command
local model server, no free embeddings, and, decisively, **no local model good
enough to be the agent.** The core premise this project rests on — a small local
model that can actually search its own memory and answer from it — was barely
viable. The 2021 version costs triple, ships worse, and quietly suggests a text
file.

Which, five weeks and a hundred hours later, remains — technically — an option.
