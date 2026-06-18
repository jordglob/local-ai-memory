# Glossary — the jargon, in plain language

Short, friendly explanations of the words that show up in this project's code,
spec, and commit history. Written for people comfortable *reading* bash but not
necessarily deep shell experts. Each term gets the plain idea, a quick analogy,
and why it matters here.

---

## Shell / scripting terms

### pipe — the `|` symbol
An assembly line for commands: it takes what one command produces and feeds it
straight into the next. `grep "KEY" file | cut -out-the-value` = *"find the line,
then trim it down to just the value."*

### `set -e`
A safety switch meaning **"if any command fails, stop the whole script now."** It
stops a script from blundering forward after something broke.

### `pipefail`
A companion safety switch: **"if any step in a pipe fails, treat the whole pipe
as failed."**

> **Why these bit us:** combined, they were *too* twitchy. When a search
> (`grep`) found **nothing**, that harmless "no match" looked like a failure —
> `pipefail` called the pipe failed, `set -e` then killed the script. A normal
> "nothing found" became a fatal error.
> **Analogy:** an over-sensitive kitchen alarm — you ask *"is there milk?"*,
> *"no"* is a fine answer, but the alarm hears "no", decides something's *broken*,
> and shuts the whole kitchen down. The fix (`|| true`) teaches it that "no" is a
> normal answer, not an emergency.

### idempotent / re-run
**Idempotent** = doing something once gives the same result as doing it many
times. Running it again is safe — it doesn't break or pile up duplicates, it just
lands on the same end state.

> **Analogy:** an elevator call button — press it once or five times, same
> result. (A vending machine that charges you *each* press is *not* idempotent.)
> **Why it matters:** people **re-run** setup scripts all the time (to change a
> setting, recover from an interruption). A good installer must survive a second
> run. Lesson banked here: *"the first run lies"* — testing only a fresh install
> hides bugs that appear on the **second** run, so we run setup twice and require
> both to succeed.

### pattern-hunt
When you find one bug, go look for every *other* place the **same shape** of bug
lives, and fix them all at once — because a bug is rarely alone.

---

## The memory concepts (what this project is really about)

### vault
The folder that holds your imported conversation history and notes — the stuff
you want the AI to actually draw on.

### entry point ("door")
Any way you talk to the agent: the terminal (`hermes chat`), the web dashboard, a
messaging gateway, etc. Memory must work from **every door**, not just the one
that happened to be tested.

### reachability (the "import → reachable" gap)
The core problem: importing your history is easy and looks successful — but can
the agent **actually reach and use** it when you talk to it? Most tools stop at
*"imported! 🎉"* and never check this last hop. This project's whole point is to
make that last hop verifiably true.

### scan / file-search
The agent *actually searching* the vault's files (e.g. running `grep`) to find
relevant history — as opposed to guessing or making things up.

### handover
A small note that's **always loaded at the start of every session** and orients
a fresh agent: *"here's who the user is, here's where their memory lives, search
it before you say you don't know."* Without it, every new session starts with
**amnesia**.

> **Analogy:** a hospital **shift handover** — the nurse going home briefs the
> incoming nurse so they don't start blind. (This is exactly how an AI coding
> assistant resumes after its context is cleared: an always-loaded instructions
> file is its handover.)
> A working handover needs **two halves**: the **orientation** ("go look, here's
> where") *and* the **scan** ("actually search the files"). Either alone fails.

### keystone
From stone arches: the **keystone** is the single wedge-shaped stone at the top
that locks all the others in place — pull it out and the whole arch collapses.

> Here, the "keystone" is **the AI reliably reaching and using your memory from
> every door.** You can install, import a thousand conversations, and pick a great
> model — but if the agent can't reach the memory when you ask, none of it
> matters. It's the piece that makes every other piece worth anything.
