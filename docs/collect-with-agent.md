# Collecting AI history with your agent

`ai-memory-ingest.sh` imports the formats it recognizes deterministically (fast,
free, idempotent). The messy long tail — vendor formats it doesn't recognize, or
history that has no clean export at all — is a better fit for an **agent** that
can *interpret* unknown data instead of needing a fixed schema. This file is the
agent-facing half of that split (see REQUIREMENTS.md §4.5 "DECIDED" and §4.7).

**Why this lives in docs, not in the script:** the script is durable and changes
slowly; agents and their skills change fast. Keeping the prompt here lets it be
updated independently, so a hardcoded prompt never rots inside the bash.

## How it fits together

1. Run a map (imports nothing):
   ```
   bash ai-memory-ingest.sh "<your-vault>" --scan-report
   ```
   This writes `<your-vault>/ai-scan-report.md` with two lists: **recognized**
   exports (with the exact import command) and **unknown** AI-ish candidates the
   script could not identify.
2. Import the recognized ones with the commands the report gives you.
3. Hand the unknown ones to your agent using the starter prompt below.

## Starter prompt for your agent (generic — adapt to your agent)

> I have a scan report at `ai-scan-report.md` in my AI-memory vault. Read its
> "Unknown candidates" section. For each path listed:
> 1. Inspect the file (it may be a zip, JSON, SQLite DB, or HTML export).
> 2. Tell me which AI tool/format it most likely is and whether it holds
>    conversation history worth keeping.
> 3. If it does, propose how to turn it into the vault's markdown format
>    (one file per conversation under `05-AI-Sessions/<source>/`, with a title,
>    `source`/`created`/`id` front-matter, and `You:` / `Assistant:` turns).
> 4. Do not delete or move my originals; only propose actions and, with my
>    approval, write new markdown into the vault.

## Notes

- The vault is plain markdown on disk — agent-neutral by design. Anything your
  agent writes in the same shape (one conversation per file under
  `05-AI-Sessions/<source>/`) is reachable by the same file search the
  recognized imports use.
- If a format shows up often enough to be worth a fast deterministic lane, it can
  graduate into a script parser — but it does not have to, to be useful today.
