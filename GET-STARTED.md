# Get started — for beginners

> You need a **real Linux** (installed and booted — not a live "cloner" like
> Clonezilla, whose changes vanish on reboot) and an **internet connection**.

## Just paste this one line

Click the little **📋 copy** button on the box below, paste it into your terminal
(right-click → Paste, or **Ctrl+Shift+V**), and press **Enter**:

```bash
curl -fsSL https://raw.githubusercontent.com/jordglob/local-ai-memory/main/bootstrap.sh | bash
```

That's the whole thing. It downloads the project (**no `git` needed**) and starts the
installer, which guides you from there. When it asks for your **password**, type it and
press Enter — *nothing shows on screen while you type; that's normal.*

**No `curl`?** Use this instead:
```bash
wget -qO- https://raw.githubusercontent.com/jordglob/local-ai-memory/main/bootstrap.sh | bash
```

---

### What that line does (and reading it first)
It fetches [`bootstrap.sh`](bootstrap.sh) over HTTPS and runs it. That script downloads
the project's tarball, unpacks it to your home folder, and launches
`ai-memory-setup.sh`. It never uses `sudo` by itself — the installer asks when it must.
If you'd rather read before running, open [bootstrap.sh](bootstrap.sh) — it's short.

### If it doesn't work
| You see… | Do this |
|---|---|
| `curl: not found` **and** `wget: not found` | `sudo apt install -y curl` (or `dnf`/`pacman`), then paste the line again. |
| something about a repository *"can't be done securely"* | That's your system's software sources, not you. Note it and tell whoever's helping — the bootstrap avoids `git`, but the installer may need those sources fixed first. |
| a question you don't understand | The safe answer is usually just **Enter** (the default). You can re-run safely. |

---

Power users: the terse path is in the main [README](README.md). Automating many
machines hands-off: [docs/ADVANCED-NETBOOT.md](docs/ADVANCED-NETBOOT.md).
