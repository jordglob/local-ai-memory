# Contributing

This is a small, source-available, **unsupported** project (issues are off).
You're welcome to fork and adapt it. If you send a PR, these are the house
rules that keep the six-script family coherent.

## Before you push

```
bash tests/run.sh        # bash -n + shellcheck + smoke + safety-gate regression
```

CI runs the same harness on **Linux and macOS** for every push/PR. Green there
is the floor; a real live run on the affected OS is the bar (see below).

## House rules

- **bash 3.2 / macOS compatible.** `/bin/bash` on macOS is 3.2. No associative
  arrays, no `mapfile`/`readarray`, no `${var,,}`. `pipefail` broke on 3.2
  historically — match each script's existing `set` discipline (`doctor` and
  `mux` are `set -uo pipefail` on purpose; they run things allowed to fail).
- **Portable tool flags.** Use precise `grep` gates (`grep -q "Status: active"`,
  not `grep -q active`); go through the `apt_get` wrapper, not bare `apt`; probe
  `/dev/tty` by opening it (`{ : >/dev/tty; } 2>/dev/null`), not `[[ -r/-w ]]`.
- **Secrets.** Never as CLI args, never in the tee log, never in the vault;
  `read -s` for input; keyfiles `chmod 600`. See `SECURITY.md`.
- **Verify, don't self-attest.** Read a file back after writing it; check the
  *effective* state (e.g. `sshd -T`), not the write. A green log that did
  nothing is a bug.
- **Fix the class, not the instance.** For every bug, sweep the same pattern
  across all scripts before moving on.

## Versioning (when a script changes)

Bump the changed script's version in **all three** in-script places — the header
comment, the `--version` output, and the banner — **and** add a line to
`PACKAGE_VERSION.txt`. `tests/run.sh` fails on drift between them. (Pure,
behavior-neutral cleanups that don't change what a script does may stay
unversioned — say so in the commit.)

## Proven vs. unproven

A path you could only parse-check or run in a sandbox is **written-but-unproven**
— never call it "done". Record what you actually ran, where, in `TESTING.md`,
and label anything you couldn't live-test.

## The spec is the source of truth

`docs/REQUIREMENTS.md` governs. `CLAUDE.md` is working habits. If code and spec
disagree after a real test, fix the code **and** correct the spec.
