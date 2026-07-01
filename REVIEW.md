# Code Review — local-ai-memory

*Engineering review of the six-script AI Memory Stack. Line references are to the
reviewed snapshot and are approximate (the scripts are under active edit); treat
them as "look here", not exact addresses.*

## Overview / verdict

The project is ambitious and mostly well-shaped: a family of self-contained,
idempotent bash scripts with consistent flags, a clear local-first philosophy, and
unusually honest "proven vs. unproven" framing in the README. The design is sound.

**It is not yet safe to hand to a stranger, and shouldn't be run unattended.** Two
classes of defect dominate:

1. **The safety rails only exist on the interactive path.** The most dangerous
   operations — deleting the vault, disabling SSH password auth — have their
   confirmations and verifications gated behind interactive prompts, so `--yes`
   turns a guided flow into a silent foot-gun. A destructive tool must be *most*
   careful, not least, when it is told not to ask.
2. **"Verified" is frequently self-attested.** Exports are declared good without
   reading them back, an SSH lockdown is called "VERIFIED" from the config file
   rather than the running daemon, and doctor reports green when the interpreter it
   needs is absent. A green log that did nothing is a bug, not a success.

There are also no automated tests, real supply-chain exposure in `setup`, and
correctness bugs in `ingest`/`configure` that can silently duplicate or corrupt
data. Verdict: **promising, source-available, genuinely unsupported — fix the
Critical and data-loss items before anyone runs the `--yes` paths on a machine they
care about.**

---

## Critical (data-loss & lockout)

- **`ai-memory-uninstall.sh` — `--no-export --yes` silently deletes the vault.**
  (~470–476 guard → `rm` ~422) The loud, explicit confirmation lives inside an
  `if ! $ASSUME_YES` block, so the combination "don't export" + "don't ask" removes
  the user's only copy of their data with no prompt and no backup. This is the
  worst-case path and it's the quietest one.
  *Fix:* require a second, un-skippable confirmation (or refuse outright) when
  `--no-export` and `--yes` are combined; never let both destructiveness and silence
  coincide.

- **`ai-memory-remote.sh` — `--yes` disables password auth with no verified key
  login and no auto-revert.** (~69, ~313, ~320) Password authentication is turned
  off before a key-based login has been proven to work, and nothing schedules a
  timed revert, so a single mistake is a *silent lockout of a possibly-headless
  box*.
  *Fix:* gate the `PasswordAuthentication no` flip behind a real
  `ssh -o BatchMode=yes -o PasswordAuthentication=no` success from the client, and
  arm an `at`/systemd-timer auto-revert that a confirmed login cancels.

- **`ai-memory-remote.sh` — macOS `kickstart -k` can drop the live session.**
  (~343) Restarting remote management with `-k` can tear down the very session the
  operator is using to run the script.
  *Fix:* warn and skip the disruptive restart when the session is remote, or defer
  it behind an explicit confirmation with a documented recovery path.

- **`ai-memory-remote.sh` — `sshd -T` reports the file, not the daemon → false
  "VERIFIED".** (~345–349) The success message claims the hardening took effect, but
  `sshd -T` reflects parsed config, not the *running* daemon's effective policy
  (first-match-wins, drop-in ordering, and un-reloaded state can all diverge). The
  script prints "VERIFIED" for a state that may not be live.
  *Fix:* verify against the live daemon (reload, then confirm via an actual
  key-only login attempt) before claiming success; downgrade the wording otherwise.

---

## Correctness bugs

- **`ai-memory-uninstall.sh` — export "verified" by `-s` only.** (~312) The archive
  is considered valid because the file exists and is non-empty (`-s`); a truncated or
  corrupt tarball passes. The header/README promise a trustworthy backup before
  deletion.
  *Fix:* validate with `tar -tzf` (list the archive) — and ideally confirm the
  manifest and an expected entry — before allowing any removal.

- **`ai-memory-ingest.sh` — idempotency is broken.** (~66–70, ~221+) Filenames are
  derived from mtime, so re-runs produce *new* names and therefore duplicate
  entries, while the header claims records are "matched by ID". Matching is actually
  by filename, so the stated dedupe contract does not hold.
  *Fix:* derive the on-disk name from the stable record `id` (not mtime) and dedupe
  by that id; make the header and behavior agree.

- **`ai-memory-ingest.sh` — path traversal from `id`/`created` into filenames.**
  (~66–68) Untrusted `id`/`created` values flow straight into output paths; a
  crafted or malformed export can write outside the intended session directory.
  *Fix:* sanitize/allow-list these fields (strip `/`, `..`, control chars) before
  using them in any path.

- **`ai-memory-ingest.sh` — zip/JSON handling can OOM.** (~140, ~179) Whole archives
  and JSON blobs are read into memory, so a large export can exhaust RAM on exactly
  the low-memory machines this project targets.
  *Fix:* stream (incremental unzip / streaming JSON) and cap per-item size.

- **`ai-memory-configure.sh` — unquoted YAML + regex splice can corrupt
  `config.yaml`.** (~461–471) Values are written unquoted and edits are spliced with
  regex, so a value containing YAML metacharacters (or an unexpected existing shape)
  can silently produce an invalid or wrong config.
  *Fix:* emit values through a YAML-safe quoter and write the file whole from a
  template rather than regex-splicing in place.

- **`ai-memory-configure.sh` / `ai-memory-setup.sh` — model presence matched by base
  name.** (configure ~315, setup ~701) A check that keys on the base model name
  treats `qwen3:35b` as "present" when only `qwen3:7b` is installed, so the wrong
  (smaller) model is silently accepted.
  *Fix:* match the full `name:tag` against `ollama list`, not the base name.

- **`ai-memory-setup.sh` — `check_disk_space` depends on python3 before install.**
  (~382–390) The space check uses python3, which may not exist yet at that point, so
  it can compute "0 GB" and `die` on a machine that has ample disk.
  *Fix:* compute free space with `df -Pk` (POSIX) and treat a missing interpreter as
  "unknown, warn" rather than "zero, fatal".

- **`ai-memory-setup.sh` — JSON built by string interpolation.** (~1325, ~1336)
  Config/JSON assembled by interpolation breaks on any value containing quotes,
  backslashes, or newlines.
  *Fix:* build JSON with a real encoder (`python3 -c json.dumps`, `jq -n`, or
  `printf` with escaping).

---

## Security

- **`ai-memory-setup.sh` — four unverified `curl | sudo -E bash` installs.**
  (~682, ~803, ~842, ~1297) Piping remote scripts straight into a root shell trusts
  the network and the upstream completely, and the `--max-time` on the fetch means a
  *truncated* download can still be executed as root — running half a script with
  privileges.
  *Fix:* download to a file, verify (checksum/signature or at least a complete,
  non-truncated fetch), then execute; never pipe an interruptible stream into
  `sudo bash`.

- **`ai-memory-remote.sh` — SSH lockdown ordering (also above).** The password-auth
  disable before a proven key login is a security *and* availability defect; called
  out under Critical.

- **`ai-memory-ingest.sh` — path traversal (also above).** Attacker-influenced
  export fields reaching filesystem paths is a security concern as well as a
  correctness one; called out under Correctness.

---

## Portability

- **`ai-memory-setup.sh` — leaked sudo-keepalive.** (~562) A backgrounded sudo
  refresh loop is started but not reliably killed, leaving a lingering process.
  *Fix:* track its PID and `kill` it in an `EXIT` trap.

- **`ai-memory-setup.sh` — swallowed apt errors.** (~743, ~807) Package failures are
  discarded, so a failed install looks successful and later steps break confusingly.
  *Fix:* check exit status and surface the failure.

- **`ai-memory-setup.sh` — PATH not persisted.** (~826–831) PATH additions apply only
  to the current process, so freshly installed tools aren't found in a new shell.
  *Fix:* append to the appropriate profile/rc and tell the user to re-source it.

- **`check_disk_space` python3 dependency** and **model base-name matching** (above)
  also have portability dimensions across macOS/Linux and shells.

---

## Architecture & docs

- **No automated tests at all.** For a family of scripts that edit `sshd`, delete
  vaults, and shell out to package managers, `bash -n` + manual runs is the only
  safety net. This is the single highest-leverage gap.
  *Fix:* add a `bats` (or plain-bash) harness covering flag parsing, the `--yes`
  safety gates, ingest idempotency, and config generation, run in CI.

- **`ai-memory-doctor.sh` — vacuous green when python3 missing.** (~92–111) Checks
  that depend on python3 pass (or skip silently) when it is absent, so doctor reports
  healthy on a machine that cannot actually run the stack.
  *Fix:* treat a missing interpreter/dependency as an explicit FAIL/WARN, never a
  silent pass.

- **`ai-memory-doctor.sh` — `--live` breaks the READ-ONLY claim.** (~219–221) doctor
  advertises itself as read-only, but `--live` performs actions with side effects,
  contradicting the contract users rely on.
  *Fix:* either drop the read-only claim when `--live` is set (label it clearly) or
  move the live behavior into a separate command.

- **`ai-memory-setup.sh` — version drift.** (~3, ~45) The header version and the
  `VERSION=` constant have drifted apart historically (e.g. a header `v8.15` against a
  stale `VERSION=8.9`), so `--version` and the banner can disagree. (They were in
  sync at the reviewed snapshot — this is a recurring hazard of tracking the version
  in two places.)
  *Fix:* define `VERSION` once and derive the header/banner from it, or add a
  pre-ship check that the two match.

- **`docs/REQUIREMENTS.md` is a 103 KB journal, not a spec.** It carries three
  changelogs, interstitial section numbering, verbatim duplicated lines (~181–214,
  now fixed), and — until this pass — leaked real private IPs, a username, a host
  path, and a `Mac pid`/`ssh …@…` line. As the declared "source of truth" it is hard
  to navigate and was quietly non-generic.
  *Fix:* split the living spec from the historical journal; keep the spec short and
  normative, archive the narrative separately. (This pass scrubbed the leaks and the
  duplicates but deliberately did not restructure.)

- **Docs say "four scripts"; there are six.** CLAUDE.md (~18) and the historical
  spec describe a four-script `setup → configure → ingest → remote` chain, but the
  shipped family is six: `setup`, `configure`, `ingest`, `doctor`, `remote`,
  `uninstall`. CLAUDE.md has been corrected in this pass; the historical journal
  entries in `docs/REQUIREMENTS.md` were left as-is (they accurately describe the
  state at the time and rewriting them would falsify history).

- **`publish-to-github.sh` — dead placeholder guard.** (~13) The script only rewrites
  the clone URL when `grep -q 'YOUR-USERNAME' README.md` matches, but `README.md`
  already hardcodes the real handle (`jordglob`, README ~28) and contains zero
  `YOUR-USERNAME` occurrences, so the `sed` replacement never runs. The guard is dead
  code and the README is no longer portable to a forker.
  *Fix:* restore the `YOUR-USERNAME` placeholder in README (so the guard works for
  anyone who forks) or drop the now-useless block from the publish script.

---

## Prioritized fix list

1. **Block `uninstall --no-export --yes` from silently deleting the vault** — add an
   un-skippable confirm/refusal. *(Critical, data-loss)*
2. **Gate `remote --yes` password-auth disable behind a verified key login + armed
   auto-revert.** *(Critical, lockout)*
3. **Verify `remote` hardening against the live daemon, not `sshd -T`/config; make
   macOS `kickstart -k` non-disruptive on remote sessions.** *(Critical)*
4. **Validate uninstall exports with `tar -tzf` (and manifest) before any removal.**
   *(Data-loss)*
5. **Replace `curl | sudo -E bash` in setup with download-verify-execute; never run
   a truncated fetch as root.** *(Security)*
6. **Fix ingest idempotency (stable id-based names + dedupe) and sanitize
   `id`/`created` against path traversal.** *(Correctness / security)*
7. **Fix configure YAML generation (quote + template, not regex splice) and full
   `name:tag` model matching.** *(Correctness)*
8. **Make setup robust: POSIX `df` disk check, JSON via encoder, trap the
   sudo-keepalive, stop swallowing apt errors, persist PATH.** *(Correctness /
   portability)*
9. **Make doctor honest: fail (not pass) when python3/deps are missing; reconcile the
   `--live` side effects with the read-only claim.** *(Docs / correctness)*
10. **Add an automated test harness (flag parsing, `--yes` gates, ingest idempotency,
    config gen) in CI.** *(Architecture)*
11. **Housekeeping: single-source the setup version; fix the dead `publish-to-github.sh`
    placeholder guard; split the spec from the journal.** *(Docs)*
