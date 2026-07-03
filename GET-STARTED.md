# Get started — the absolute-beginner path

> **Status: DRAFT / being validated.** This page is written for someone who has
> *never* used a Linux terminal. It is being proven by live "naive-user" dogfooding
> on a fresh machine — if a step doesn't work exactly as written, that's a bug in
> *this page*, not in you. Report the wall you hit.

You need three things: a **real Linux** (installed and booted — not a live "cloner"
like Clonezilla, whose changes vanish on reboot), an **internet connection**, and
about **20 GB free disk**. That's it.

You will copy-paste **one block at a time**, press **Enter**, and wait for it to
finish before the next. When a command asks for your **password**, type it and press
Enter — *the screen won't show anything as you type; that's normal.*

---

## Step 1 — Get the files (this is where most people trip)

The main README says `git clone …`. On a brand-new machine that often fails with
**`bash: git: command not found`** — because `git` (the download tool) isn't
installed yet. That's expected. Two ways past it — pick **A** (no git needed):

### A) No git — download a snapshot (recommended for beginners)
Almost every Linux already has `curl` **or** `wget`. This tries both:
```bash
cd ~
curl -fsSL https://github.com/jordglob/local-ai-memory/archive/refs/heads/main.tar.gz -o lam.tar.gz \
  || wget -O lam.tar.gz https://github.com/jordglob/local-ai-memory/archive/refs/heads/main.tar.gz
tar xzf lam.tar.gz
cd local-ai-memory-main
```

### B) Or install git first, then clone
This one line covers the three common Linux families (Debian/Ubuntu, Fedora, Arch):
```bash
sudo apt update && sudo apt install -y git \
  || sudo dnf install -y git \
  || sudo pacman -Sy --noconfirm git
git clone https://github.com/jordglob/local-ai-memory
cd local-ai-memory
```

> **Which Linux am I on?** If you're unsure, run `cat /etc/os-release` — the `NAME=`
> line tells you (Ubuntu/Debian → `apt`, Fedora → `dnf`, Arch → `pacman`).

You should now be *inside* the project folder. Check with `ls` — you should see files
like `ai-memory-setup.sh`.

---

## Step 2 — Run the installer

```bash
bash ai-memory-setup.sh
```
This one script bootstraps everything else it needs (Node, Ollama, the agent, a
markdown "vault"). It **asks before anything opinionated**, is safe to re-run, and
explains each step. It will use `sudo` where it must — that's why it asks for your
password. **Don't run it with `sudo` yourself**; let the script ask.

When it finishes, it prints the **exact next command** to run. Follow that. The
chain is:
```
ai-memory-setup.sh      →  installs the stack
ai-memory-configure.sh  →  picks a model for YOUR hardware
ai-memory-ingest.sh     →  imports your old AI chats (optional)
ai-memory-doctor.sh     →  checks everything is reachable
hermes chat  (or: bash ai-memory-mux.sh)  →  talk to your agent
```

---

## If something goes wrong

| You see… | Do this |
|---|---|
| `git: command not found` | Use **Step 1 option A** (no git needed). |
| `curl: command not found` **and** `wget: command not found` | Install one: `sudo apt install -y curl` (or `dnf`/`pacman`). Then retry A. |
| `Permission denied` | You probably typed `sudo bash …` — run it **without** `sudo`; the script asks when needed. |
| `Not enough disk space` | Free up space (need ~20 GB) or point at a bigger disk. |
| It asks a question you don't understand | The safe answer is usually the default (just press Enter). You can re-run the script later. |

Still stuck? Note the **exact** command you ran and the **exact** message, and open
your notes — remember, a wall here is a gap in this guide.

---

## Not a beginner, or provisioning many machines?
- Power users: the main [README](README.md) has the terse version.
- Automating a *fresh* machine end-to-end over the network (PXE/netboot, zero
  copy-paste): see the sketch in [docs/ADVANCED-NETBOOT.md](docs/ADVANCED-NETBOOT.md).
