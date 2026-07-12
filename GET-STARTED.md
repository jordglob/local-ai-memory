# Get started — from a blank computer

> Honest promise: this starts from **nothing** — a machine with no Linux, no `git`,
> no `curl`. If a step assumes something you don't have, that's a bug in *this page*
> (it's being proven by real beginner testing), not in you.

## What you'll need
- The computer you want to run this on (**its disk will be erased** in Part 0).
- A **USB stick**, 8 GB or bigger (also erased).
- **A second computer with internet** to prepare the USB stick.
- About **30 GB free** on the target computer.

---

## Part 0 — Put a real Linux on the computer  *(don't skip this)*

A blank or freshly-imaged machine usually has almost nothing: no `git`, no `curl`, and
software sources that refuse to install anything (*"…can't be done securely…"*). **You
can't fix that by pasting commands — you need a proper operating system first.**

⚠️ **Not Clonezilla** — that's a disk *copier*; it runs from RAM and forgets everything
on reboot. **Not a "minimal" or "server" image** — too bare. Use a normal **desktop**
Linux. **Ubuntu Desktop** is the most beginner-friendly.

1. On your **second computer**, download **Ubuntu Desktop** from
   `ubuntu.com/download/desktop`.
2. Write it to the USB stick with **balenaEtcher** (`etcher.balena.io`) — pick the
   file, pick the USB, click **Flash**.
3. Put the USB in the **target** computer and turn it on, tapping the boot-menu key
   (often **F12**, **F2**, **Esc**, or **Del**) to choose the USB stick.
4. Choose **Install Ubuntu** (not "Try Ubuntu"). Follow the wizard, let it install to
   the disk, **reboot**, and remove the USB when asked.

You now have a real Linux with a **web browser**, a **terminal**, and **working
software sources** — which quietly fixes the git / curl / "can't be done securely"
problems all at once.

---

## Part 1 — Get the project  *(no typing needed)*

1. Open **Firefox** and go to `github.com/jordglob/local-ai-memory`.
2. Click the green **`< > Code`** button → **Download ZIP**.
3. Open the **Files** app → **Downloads**, right-click the ZIP → **Extract Here**.

You now have a folder called `local-ai-memory-main`.

---

## Part 2 — Run it

1. In **Files**, open the `local-ai-memory-main` folder.
2. Right-click an empty area → **Open in Terminal**.
3. Type this and press **Enter**:
   ```bash
   bash ai-memory-setup.sh
   ```

It installs everything else and guides you step by step. When it asks for your
**password**, type it and press Enter — *nothing shows on screen while you type; that's
normal.* At the end it prints the exact **next** command; follow that (`configure` →
`doctor` → `hermes chat`).

---

## Shortcut for later (only on a real Linux)
Once you're on Ubuntu and comfortable, this one line does Part 1 + 2 together:
```bash
curl -fsSL https://raw.githubusercontent.com/jordglob/local-ai-memory/main/bootstrap.sh | bash
```
(The browser+ZIP path above needs *nothing* extra, so it's the safer first-timer route.)

---

## Stuck? Read the signal
| You see… | What it really means | Do |
|---|---|---|
| `git`/`curl: command not found`, or apt says *"can't be done securely"* | You're on a **cloner/minimal** system, not a real install | Go back to **Part 0** and install Ubuntu Desktop |
| the password prompt shows nothing as you type | totally normal | type it, press Enter |
| a question you don't understand | — | press **Enter** for the safe default; you can re-run later |
| the boot menu won't show the USB | secure-boot / boot-order | enter BIOS/UEFI (same key at power-on), enable USB/legacy boot, save |

---

Power users: the terse path is in the main [README](README.md).
Automating many machines hands-off: the netboot sketch lives in the companion
repo `local-ai-memory-fleet` (with the rest of the fleet/remote tooling).
