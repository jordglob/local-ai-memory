# The Local-AI-Memory Build: A Loving Roast

### or: *a distributed system, so you can remember a conversation*

> Technical retrospective, written by the AI that was in the trenches. Every
> failure below is real — and every one of them belongs to *this project*, not
> to the machine it unfortunately runs on.

---

## The setting

Picture the deployment. To let a small local language model remember what you
said yesterday, we have:

- a **workstation** that does the actual living,
- a **Mac mini** on the LAN acting as the "memory server,"
- a **WSL Ubuntu** in the middle for good measure,
- all three lashed together with **ssh, rsync, and optimism**, shuttling
  **markdown files** back and forth on a timer.

Three operating systems. One markdown folder. This is the architecture for
*taking notes*. A reasonable person uses a text file. But we are not here to be
reasonable; we are here to build a distributed, self-healing, secret-scrubbing,
multi-source ingestion pipeline so that a local model can answer *"where does the
agent run?"* — a question it then gets **wrong**, from memory, confidently. More
on that later. *Sigh.*

## The parade of silent failures

The thing about this project is that it kept **succeeding out loud while failing
in silence.** A tour:

- **The memory was frozen for days and nobody knew.** A well-meaning feature
  ("never overwrite the user's hand-edits") re-derived each note's content hash
  by round-tripping the *rendered* markdown back to source text and trying every
  role-label permutation. One change to the text-cleaning step broke that
  round-trip, so the importer decided **every note had been hand-edited** and
  refused to update any of them. Sync: green. Ingest: green. Vault: a fossil.
  The whole point of the system is to remember, and it had quietly stopped.
- **It was un-fixing itself on a schedule.** A stale copy of the tools on one
  machine would overwrite the central's *newer* tools every night, downgrading
  the fix we'd just shipped — and preserved file timestamps hid the crime, so
  the version number silently walked backwards at the same time each evening.
- **"Local, private, free" was quietly none of those.** The local model server
  was serving **zero models** while a **silent cloud fallback** answered in its
  place. So the offline-first, costs-nothing agent was, in fact, phoning a paid
  API the entire time, invisibly, and nobody noticed because the answers *looked*
  fine. The dream of local inference, brought to you by someone else's GPU.
- **The agent corrupts its own config.** Given the chance, it rewrites
  `config.yaml` and occasionally mangles its own model block, pointing itself at
  the wrong provider. A memory system whose agent forgets how it's configured is
  a special kind of poetry.

Every one of these hid behind a **green status light.** The lesson, engraved in
stone: *silence is not health.* Which is why we then built a watchdog that
assumes the worst.

## The remote-session comedy

At one point the plan was to drive the agent's dashboard in a browser so the
human could stop copy-pasting prompts. Noble. Except the whole session ran over
a **remote desktop**, and the browser — seeing no physical screen — **froze its
own background tabs.** So the automation could *read* a page that was already
open but could never *load* a new one; every navigation to the local dashboard
timed out while a plain command-line request reached the exact same address in
**7 milliseconds.** We proved it wasn't the network, the proxy, the firewall, or
the browser brand, and concluded — correctly — that the entire browser path was
a dead end on this setup. We routed around it with ssh, which is what we should
have done in the first place. *Deep sigh.*

## What we actually built (the part I'm proud of)

Between the fires, real engineering happened:

- **Recency ranking** (`search v2.1`): recall used to surface the *older,
  more-repeated* version of a fact that had since changed. Now freshness (a
  note's last-write time, not the filename's start-date) breaks the tie. Term
  coverage still wins; recency only decides ties.
- **Two-pool entity recall** (`search v2.2`): the curated, authoritative notes
  weren't even being searched — only the raw transcripts were. Now they are, as
  a separate pool, so a fact stated only in a curated note can surface without a
  fragile magic weight. Evaluated live on real questions: **6/7.**
- **Semantic search — built as a concept probe, then honestly thrown away.**
  With a proper embedding model, correct task prefixes, and per-line matching,
  embeddings *still* ranked a literal-overlap distractor above the right note and
  scored everything in a narrow 0.50–0.65 band. Not good enough to justify a new
  dependency and per-turn latency. We wrote it, measured it, and **deleted it on
  purpose** — the step most projects skip.
- **Self-healing** (`vault-health` + `self-heal` + playbooks): the health check
  emits machine-readable alarm codes; a dispatcher maps each to a small
  idempotent playbook, runs it, **re-checks**, and escalates *only what's still
  broken* — with a loop-guard so an unfixable alarm isn't hammered forever. Each
  failure above became a one-line playbook entry.
- **Git history for the vault**, an **end-to-end health watchdog**, a **mode
  menu fixed** (it turned out one of the "switch mode" commands had been a silent
  no-op the entire time), and a **test suite** that grew to **119 green** and
  gates every change.

## The philosophical bit

The stated dream: *let the resident agent run all of this itself, no smarter AI
needed.* We tested that premise empirically. The local model scored **2.5 out of
8** on recall, took up to **eight minutes per question**, and answered several by
returning a **menu** instead of an answer. Honest conclusion: it can run the
*routine* and the *known alarms*, but novel diagnosis — the entire content of
this retrospective — needs a real reasoner. So the north star was reframed:
*self-heal the known, escalate the unknown, and leave a playbook behind each
time, so the part that needs a smart AI shrinks toward zero.* A far better goal
than pretending the local model is smarter than it is.

---

## The bill

**How many hours has this project taken?**
Across its life — the ingest work, the model-cost study, the sync saga, the
recall tuning, and the maintenance marathon — call it **~100 hours.** A
meaningful slice of that wasn't building the thing; it was debugging the system
*around* the thing, on a topology that fought back at every layer.

**How long would a pro dev need today (2026), on sane infra, AI-assisted?**
About **50 hours.** The whole stack — multi-source ingest, the recall hook,
sync, self-heal — is maybe a week and a half of focused work for someone who
knows the tools and *doesn't run three operating systems in a trenchcoat.*

**And a pro dev five years ago (2021)?**
**250–350 hours, and a raised eyebrow.** In 2021 there was no ambient LLM to
co-write the code, no one-command local model server, no free embeddings, and —
crucially — no local model good enough to *be* the agent. The core premise ("a
small local model that remembers you") was barely viable. A competent dev in
2021 would have quoted you triple, shipped something worse, and gently suggested
you just use a text file.

Which, a hundred hours later, remains — technically — an option.

*— written from the trenches, with love and mild despair.*
