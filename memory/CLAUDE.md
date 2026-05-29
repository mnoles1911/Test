# memory/CLAUDE.md

Per-agent memory files. **Read these when picking up a multi-session task** — they're the "receipts" of what was done, why, and what's left.

## What's in here

- **`MEMORY.md`** — the agent's auto-memory index (entries pointing at the per-topic notes below). Always loaded into Claude Code context.
- **`project_*.md`** — per-PR / per-task receipts written when a feature shipped or was deferred. Each one contains:
  - what was attempted
  - why specific choices were made (the ones that aren't obvious from the code)
  - what was deferred and the explicit signal that would unblock it
  - links to commits, captures, design docs

## When to read

- Picking up work that has a `project_*.md` entry: **read that file first**, even if the design doc covers the same ground. The memory file has the *decisions* that didn't make it into design.
- Before re-attempting something the project has tried before — check whether a memory file flags a prior failed approach.

## When to write

- After a substantial PR ships (or is explicitly deferred), create or update `project_<name>.md` with the receipt format above.
- Add a one-line pointer to `MEMORY.md` so the entry is discoverable.
- Don't write entries for trivial bugfixes — git log is enough.

## Don't

- Don't write conversation logs or "what I tried" narrative here.
- Don't duplicate design doc content — link to it.
- Don't write entries before the work is actually done; in-flight scratch belongs in the conversation.
