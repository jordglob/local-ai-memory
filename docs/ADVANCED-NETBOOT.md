# Advanced — zero-touch install over the network (PXE / netboot) — SKETCH

> **Status: DESIGN SKETCH, not built.** This is a plan for the "get everything
> running automagically, no copy-paste" idea. It is the *opposite* end from
> [GET-STARTED.md](../GET-STARTED.md): powerful for provisioning **many** machines,
> overkill for one. Nothing here is tested yet.

## The idea

Boot a bare machine **from the network** instead of a USB stick, have it install a
minimal Linux unattended, and on first boot **automatically fetch this repo and run
`ai-memory-setup.sh --yes`**. Result: rack a box, power it on, walk away, come back
to a running agent. No terminal, no `git`, no copy-paste.

Two layers do the work:
1. **Netboot + unattended OS install** (gets a real Linux onto the disk).
2. **First-boot hook** (runs our stack once, then disables itself).

## Layer 1 — how the machine boots the installer

Pick one; all are well-trodden:

| Approach | What you run | Good when |
|---|---|---|
| **netboot.xyz** | Point the machine's PXE/iPXE at `netboot.xyz` (or self-host its image) | Easiest start; menu of distros |
| **Classic PXE** | Your own DHCP (option 66/67) + TFTP + HTTP serving the installer | You control the LAN |
| **USB autoinstall** | Same autoinstall file, delivered by USB instead of the network | No PXE server available |

The unattended install itself is distro-native:
- **Ubuntu**: *autoinstall* (`user-data`/`cloud-init`) — the documented, supported path.
- **Debian**: *preseed* (`preseed.cfg`).
- **Fedora**: *kickstart* (`ks.cfg`).

Because our stack targets Debian/Ubuntu/Fedora/Arch, **Ubuntu autoinstall** is the
recommended first target (best-documented, matches the most-proven script branch).

## Layer 2 — the first-boot hook (the only project-specific part)

The autoinstall's `late-commands` (Ubuntu) / preseed `late_command` / kickstart
`%post` drops a **one-shot** unit that runs once as the created user, then removes
itself. Sketch (Ubuntu autoinstall `user-data`):

```yaml
autoinstall:
  version: 1
  identity:
    username: ai
    # ...hostname, hashed password...
  packages: [git, curl, ca-certificates]      # solves "git not found" up front
  late-commands:
    - |
      cat > /target/etc/systemd/system/ai-memory-firstboot.service <<'UNIT'
      [Unit]
      Description=First-boot: install the AI Memory Stack (once)
      After=network-online.target
      Wants=network-online.target
      [Service]
      Type=oneshot
      User=ai
      ExecStart=/usr/local/bin/ai-memory-firstboot.sh
      RemainAfterExit=yes
      [Install]
      WantedBy=multi-user.target
      UNIT
    - |
      cat > /target/usr/local/bin/ai-memory-firstboot.sh <<'RUN'
      #!/usr/bin/env bash
      set -euo pipefail
      cd "$HOME"
      git clone https://github.com/jordglob/local-ai-memory
      cd local-ai-memory
      bash ai-memory-setup.sh --yes
      bash ai-memory-configure.sh --yes
      systemctl --user disable ai-memory-firstboot.service 2>/dev/null || true
      sudo systemctl disable ai-memory-firstboot.service || true
      RUN
    - chmod +x /target/usr/local/bin/ai-memory-firstboot.sh
    - curtin in-target -- systemctl enable ai-memory-firstboot.service
```

## Open questions / risks (before this becomes real)

1. **`--yes` + unattended is exactly the danger the security review flagged.** The
   whole point of the hardening pass was that `--yes` must not silently do
   destructive/lockout things. A netboot install runs headless by definition — so
   `remote.sh` must **never** be in the auto-chain, and `setup`/`configure --yes`
   must be re-audited for any irreversible step. See the archived security
   review, [history/REVIEW.md](history/REVIEW.md).
2. **No secrets in the image.** API keys must be entered *after* first boot (or
   pulled from the proposed encrypted secrets bundle, history/REVIEW.md
   Appendix A) — never
   baked into the autoinstall file, which sits on a TFTP/HTTP server.
3. **Which distro to prove first?** Ubuntu autoinstall (see above).
4. **Model download on first boot** can be many GB — fine on a fast LAN, painful
   otherwise; consider a local Ollama mirror for fleets.
5. **Verification:** a fleet needs `doctor` to phone home (or write a status file)
   so you know each box actually reached "agent can read the vault", not just
   "installer exited 0".

## Relation to the beginner path
- One machine, human present → [GET-STARTED.md](../GET-STARTED.md).
- Many machines, hands-off → this. Both end at the same place: `setup → configure →
  doctor → a running agent`.
