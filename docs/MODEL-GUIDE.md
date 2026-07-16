# Which Model for a Local AI Memory? — A Field Guide

*Honest, measured notes on what actually works for the specific job this project
does: a model that recalls **your own conversation history** and answers from it.
All numbers come from live evals run in July 2026 on the project's own Mac mini
(Apple Silicon) against its own vault — not a general benchmark, and not marketing.
Your mileage will vary; the **findings** travel better than the exact percentages.*

---

## The task, and why it's unusual

This is not "which model is smartest." It's a narrower, stricter question:

> Given the user's real question and a vault of their past conversations, does the
> model **find the right note and answer from it** — cheaply, and ideally fast?

Two things make it different from a normal benchmark. First, retrieval matters as
much as reasoning — a brilliant model that won't *search* is useless here. Second,
the useful unit is **cost per correct recall over a month**, not raw quality. At
this project's usage (~250 turns/month, ~50 active days), a few cents per turn is
the whole budget.

## The four tiers

| Tier | Example models | Role |
|---|---|---|
| **Local** | `qwen3.6:35b`, `gemma4:12b` (Ollama) | Free, offline, private — the resident agent |
| **Cloud single** | `nex-n2-mini`, `glm-5.2` (OpenRouter) | Cheap hosted — the daily driver |
| **MoA** (Mixture-of-Agents) | several cheap refs + one aggregator | Selective firepower for hard questions |
| **Frontier** (what Claude Code runs) | `claude-opus-4.8`, `claude-haiku-4.5` | Reasoning/building tier — decisive, not cheap |

---

## The numbers (memory-recall eval, 6 questions × 3 runs)

No model was fully reliable on hard recalls — the best single score was 66%. So
read these as *relative*, not absolute.

| Model | Tier | Correct | Speed | Cost / mo* | Note |
|---|---|---:|---:|---:|---|
| `gemma4:12b` | Local | 38% | fast | free | only *searched* 55% of the time |
| `qwen3.6:35b` | Local | 50% | ~59 s | free | searched 94%, but slow |
| local MoA | Local | ~65% | 2–4 min | free | too slow for daily use |
| **`nex-n2-mini`** | Cloud | **61%** | **~18 s** | **~$0.6** | **the value king** |
| `glm-5.2` | Cloud | 66% | ~fast | ~$2.7 | best single, a bit pricier |
| MoA (good refs) | MoA | ~77%† | slow | $3–5 | ceiling; needs interactive session |

\* at ~250 turns/month. † analytical union ceiling; real ~5–10 pp lower.

## A second eval, and the honest wrinkle

A later 16-question round (deliberately stressing **recently-changed facts**) was
harsher: `nex-n2-mini` ~3.5/8, `qwen3.6:35b` ~2.5/8 (and up to 8 minutes per
answer, sometimes replying with a *menu* instead of an answer). The gap from the
first eval isn't a contradiction — that set was chosen to be hard, and it exposed
that most failures weren't the model being dumb but the **retrieval surfacing a
stale version of a fact that had changed.** That's a *retrieval* problem, and it
was fixed with ranking changes (recency + curated-note search), not a bigger model.

---

## The findings that actually matter

The percentages will age; these won't.

1. **The model floor is decisive — and it's a cliff, not a slope.** Same vault,
   same prompt, same everything — only the model changed: a weak local model made
   **zero** tool calls (it *hallucinated* running grep, twice, then declared the
   history empty), while a small frontier model made **six real** tool calls and
   cited the actual files. Below a capability threshold, no retrieval plumbing
   helps, because the model won't use it. Above it, cheap models do fine. Pick a
   model above the floor; don't try to engineer your way under it.

2. **MoA's lift comes from the *reference* models, not the aggregator.** Mixture-
   of-Agents got to ~77% — but swapping in an expensive aggregator (a frontier
   model) added **nothing** while roughly tripling the cost (~$19/mo vs ~$3–5).
   Spend on diverse, decent references; make the aggregator cheap.

3. **"Real" MoA only runs interactively.** In a headless / one-shot call, only the
   aggregator runs — the reference models never fire. MoA's benefit needs a live
   TTY or gateway session. If you script it, you're just paying for one model.

4. **Local is an emergency option, not a daily driver.** Free and private, yes —
   but it missed roughly half the hard recalls and was slow. Keep it for
   offline/airplane/privacy-critical use; run cheap cloud the rest of the time.

5. **Cheap cloud beats local on both quality *and* speed.** `nex-n2-mini` at
   ~$0.6/month was faster (~18 s vs ~59 s) *and* more accurate than the local 35B.
   "Local-first" is a privacy choice here, not a performance one.

6. **Watch for a silent cloud fallback.** A misconfigured local server can serve
   **zero models** while a fallback quietly answers from a paid API — so your
   "free, local, private" setup is neither free nor local, and the answers look
   fine so you never notice. Verify what's actually answering.

---

## Recommendation (for this kind of setup)

| Situation | Use |
|---|---|
| **Daily driver** | `nex-n2-mini` (cloud) — best cost/quality/speed by a distance |
| **A question that really matters** | MoA with cheap refs + cheap aggregator (interactively) |
| **Offline / privacy-critical** | `qwen3.6:35b` local — accept slower + ~half the hard recalls |
| **Building / diagnosing the system itself** | a frontier model (Claude Code) — the reasoning tier, not for cheap recall |
| **Don't bother** | a frontier model as a MoA aggregator (pure waste), or `gemma4:12b` for recall (won't reliably search) |

## Caveats worth stating plainly

- **Point-in-time.** Models from mid-2026; the landscape moves monthly. Re-run the
  eval when you change models — the harness for it ships in this repo.
- **Self-made benchmark** on one vault and one machine. Treat the ordering as
  signal and the exact numbers as illustration.
- **Recall task, not general intelligence.** A model can be great at coding and
  mediocre here, or vice-versa. This measures *remembering your history*, nothing
  else.

*The one-line version for your friend: run **`nex-n2-mini`** for everyday memory,
keep a local model for offline, reach for MoA (cheap refs, cheap aggregator) only
when it matters — and never pick a model below the tool-calling floor, because no
amount of clever retrieval will save it.*
