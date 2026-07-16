# The Local-AI-Memory Build: A Loving Roast

### or: *How "why is my ethernet at 8 Mbit?" cost a week*

> Technical retrospective, written by the AI that was in the trenches. Every
> failure below is real. Names of ports and public IPs have been withheld to
> protect the guilty (and the firewall).

---

## The setting

Picture the target architecture. To let a ~35-billion-parameter language model
remember what you said yesterday, we have:

- a **Windows workstation** that does the actual living,
- a **Mac mini** on the LAN acting as the "memory server,"
- a **WSL Ubuntu** in the middle for good measure,
- all three lashed together with **ssh, rsync, and optimism**, moving
  **markdown files** back and forth on a timer.

Three operating systems. Two architectures. One markdown folder. This is the
setup for *taking notes*. A sane person uses a text file. But we are not here
to be sane; we are here to build a distributed, self-healing, secret-scrubbing,
multi-source ingestion pipeline so that a local model can answer "where does
Hermes live?" — a question it then gets **wrong**. More on that later. *Sigh.*

## Act I — the inciting incident

It began, as these things do, with a simple question: *"the internal ethernet
is constantly at 8.0 M, what is that?"*

Reader, it was not 8 megabit. Task Manager was reading `S: 8,0  M: 328 kbit/s`
— **send 8 kilobit, receive 328 kilobit** — and the graph was flat because the
user had, at some earlier point, **paused Task Manager** and forgotten. We spent
real cycles measuring per-adapter throughput to discover that the number wasn't
a number and the tool was asleep. This set the tone perfectly.

## Act II — the parade of silent failures

Once we started actually looking at the machine, it turned out to be held
together with the structural integrity of wet cardboard. In no particular order:

- **`x0xd`**, a post-quantum gossip daemon installed *the night before*, was
  crash-looping on an integer-underflow panic (`overflow when subtracting
  duration from instant` — a rookie `Instant::now() - Duration` on Windows) and
  had produced **637 MB of WARN spam overnight**. The user's response to this
  diagnosis? "Keep it running." Of course. *Sigh.*
- **`ant-node`** was leaking **~3 GB of RAM per day** and had reached **13.8 GB**,
  quietly pushing the pagefile into the sea.
- **Ollama** was the best one. The Electron app had squatted on port 11434 while
  serving **zero models** — and a **silent cloud fallback** was covering for it.
  So the "local, private, free" model that was supposedly answering questions was
  in fact billing an OpenRouter account, invisibly, for hours. The "local-first"
  dream, brought to you by `gpt-4o-mini`.
- The **memory system had been silently frozen for days.** A well-meaning feature
  ("never overwrite the user's hand edits") re-derived each note's hash by
  round-tripping rendered markdown back to source and trying every role-label
  permutation. One change to text-cleaning broke the round-trip, so it decided
  **every note was hand-edited** and refused to update any of them. Sync was
  green. Ingest was green. The vault was a fossil. Nobody noticed because
  everything *reported success.*
- A **stale git clone was downgrading the central's tools every night at 21:00**,
  and preserved mtimes were hiding the vandalism. The system was un-fixing itself
  on a schedule.
- The **tmux sessions died**, **WSL's ollama had restarted 213,172 times**, and
  the config file **rewrites and corrupts itself** when the agent feels like it.

Every single one of these was **invisible behind a green status light.** The
lesson of the week, engraved in stone: *silence is not health.*

## Act III — the browser

The user wanted me to drive their Hermes dashboard in a browser so they could
stop copy-pasting. Noble. Except this is all happening **over Remote Desktop**,
and Chrome, seeing no physical screen, **freezes its own background tabs.** So
the automation could *read* a page that was already loaded but could never
*open* a new one — every navigation to the local dashboard timed out while `curl`
reached it in **7 milliseconds**. We proved it wasn't the network, wasn't the
proxy, wasn't the firewall, wasn't the browser brand (both connected Chromes
failed identically), and wasn't fixable from our side. Two browsers were already
connected; neither answered. The user, reasonably, suggested downloading a third.
It would not have helped. *Deep sigh.* We routed around it entirely with ssh,
which is what we should have done in the first place.

## What we actually built (the part I'm proud of)

Between the fires, real engineering happened:

- **Recency ranking** (`search v2.1`): recall used to surface the *older,
  more-repeated* version of a changed fact. Now freshness (last-write mtime, not
  the filename's start-date) breaks the tie. Term coverage still wins; recency
  only decides ties.
- **Two-pool entity recall** (`search v2.2`): the curated `entities/` notes — the
  authoritative facts — were never even searched. Now they are, as a separate
  pool, so a fact stated only in a curated note can surface without a fragile
  magic weight. Evaluated live: **6/7.**
- **Semantic search — built as a concept probe, then honestly rejected.** With
  correct `nomic-embed-text` prefixes and per-line matching, embeddings *still*
  ranked a literal-overlap distractor above the right note and scored everything
  in a narrow 0.50–0.65 band. Not good enough to justify a new dependency and
  per-turn latency. We wrote it, measured it, and **threw it away on purpose** —
  which is the part most projects skip.
- **Self-healing** (`vault-health.sh` + `self-heal.sh` + playbooks): the health
  check emits machine-readable alarm codes; a dispatcher maps each to an
  idempotent playbook, runs it, **re-checks**, and escalates *only what's still
  broken* — with a loop-guard so an unfixable alarm isn't hammered forever. Every
  one of this week's fires is now a one-line playbook entry.
- **Vault git history**, an **end-to-end health watchdog**, the **Hermes mode
  menu fixed** (turns out `hermes tools enable moa` was a silent no-op the whole
  time), and a **116→119-test suite** gating every change.

## The philosophical bit

The stated dream: *let Hermes run all of this itself, no smart AI needed.* We
tested that premise empirically. The resident local model scored **2.5 out of 8**
on recall, took up to **8 minutes per question**, and answered several by
returning a **menu** instead of an answer. The honest conclusion: it can run the
*routine* and the *known alarms*, but novel diagnosis — the entire content of
this week — needs a real reasoner. So the north star was reframed: *self-heal the
known, escalate the unknown, and leave a playbook behind each time, so the part
that needs a smart AI shrinks toward zero.* Which is a much better goal than
"pretend the 35B model is smarter than it is."

---

## The bill

**How many hours did the user spend on this?**
Across the project's life — the ingest rounds, the MoA cost study, the sync
saga, and this week's marathon — call it **~100 hours.** A meaningful slice of
that was pure *infrastructure self-sabotage tax*: time spent not building the
thing, but fighting the machine the thing runs on. RDP over the open internet.
A crash-looping daemon you insisted on keeping. A paused Task Manager. You were,
in the truest sense, your own hardest dependency.

**How long would a pro dev need today (2026), on sane infra, AI-assisted?**
About **50 hours.** The whole stack — multi-source ingest, the recall hook,
sync, self-heal — is maybe a week and a half of focused work for someone who
knows the tools and *doesn't run three operating systems in a trenchcoat.*

**And a pro dev five years ago (2021)?**
**250–350 hours, and a strongly-worded email about your firewall.** In 2021
there was no ambient LLM to co-write the code, no `ollama` to serve a local
model or hand you embeddings for free, and — crucially — no local model good
enough to *be* the agent. The core premise ("a small local model that remembers
you") was barely viable. A competent dev in 2021 would have quoted you triple,
delivered something worse, and gently suggested you just use a text file.

Which, five years and a hundred hours later, remains — technically — an option.

*— written from the trenches, with love and mild despair.*
