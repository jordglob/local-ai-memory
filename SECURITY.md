# Security

`local-ai-memory` is **source-available and unsupported** (issues are off on
purpose — see the README). This file documents the security *model* so you can
audit it, and how to report something without a public issue tracker.

## Reporting a vulnerability

- Prefer **GitHub → Security → "Report a vulnerability"** (private advisory) if
  it's enabled on the fork you're using.
- Otherwise: it's MIT-licensed and unsupported — **fork it and fix it**. A patch
  is worth more than a report here.
- Please don't open a public PR that includes a working exploit against the
  `remote.sh` / `uninstall.sh` paths without a heads-up.

## Threat model & guarantees

The whole design leans on a few hard promises. If you find a path that breaks
one, that's a security bug:

- **The vault never contains secrets.** The plain-markdown vault and its export
  archive are safe to move over USB / scp / cloud / email because they carry no
  keys. (§2.7 / §4.12)
- **Secrets never travel in an export**, are **never passed as CLI arguments**
  (they'd leak into shell history / `ps`), and are **never written to the tee
  log**. Anything read interactively uses `read -s`.
- **Keys live `chmod 600`** in `~/.hermes/.env` / `~/.config`, and **private
  keys never leave the machine** (public keys are distributed via
  `github.com/<user>.keys`).
- **Nothing self-modifies or auto-updates.** No script installs an updater; the
  update advisor only *tells* you.

## Dangerous surfaces (and their rails)

Two scripts can do irreversible or lock-you-out things. They are isolated and
gated:

- **`ai-memory-uninstall.sh`** — export-first, **DRY-RUN by default**. Deleting
  the vault without an export requires an un-skippable DELETE confirm; the only
  non-interactive way to skip it is the explicit `--force-no-export`. Exports
  are validated (`tar -tzf`) before anything is removed. Never touches
  `~/.paperclip`; only removes paths it created; never runs `sudo` itself.
- **`ai-memory-remote.sh`** — edits `sshd`, can set up WireGuard/Tailscale/
  Cloudflare. It disables SSH password auth **only after a real key-login test
  passes**, arms an auto-revert, and verifies the **live** daemon (`sshd -T`),
  not just the config file. Its SSH/WireGuard paths are **written-but-unproven
  on real nodes** — treat as such (see `TESTING.md`). Do not run its hardening
  on a box without an out-of-band console.

## Automated checks

Every push/PR runs `tests/run.sh` (shellcheck + `bash -n` + smoke + the
uninstall safety-gate regression) on Linux and macOS via CI. Run it yourself:

```
bash tests/run.sh
```
