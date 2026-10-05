---
description: Promote-or-drop pass over the accumulator tiers (LEARNINGS.md, IDEAS.md, the standing list) — one verdict per entry, filed or deleted in the same pass
argument-hint: "[--limit N] [learnings|ideas|standing]"
---
You are running the triage procedure for `$ARGUMENTS`, per [`docs/triage.md`](../docs/triage.md) — the
procedure. This command is a POINTER and an ordered checklist, never a restatement: T0-T6 stay in the
doc and are adopted by reference. Where this checklist's compression disagrees with the doc's own text,
the doc wins.
(On an install where the adopter already owns the `/triage` name, `install.sh`'s generic collision-alias
mechanism places this command under the prefixed name `keel-triage` instead — same file, same behavior.)

**T0 — resolve inputs.** The backlog the `/go` way; the learnings file, the ideas file and the standing
list from the project's `CLAUDE.md` map. A named tier in `$ARGUMENTS` narrows the pass to it. An absent
input → one line, skip; never create a tier.

**T1 — order and bound.** `[2×]`+ learnings first, then recurring standing-list lines, ideas, `[1×]`
learnings oldest first, undated last. Bound: 40 entries unless `--limit N` raises it; at the bound stop
with "N remain, next pass starts at …".

**T2 — one verdict per entry:** `PROMOTE-RULE` (known surface, one-paragraph edit, a repo you may edit
directly — edit now), `PROMOTE-TICKET` (needs a test, a design pass, or a PR — file it in the landing
repo's backlog now), `KEEP`, or `DROP` (mooted, or `[1×]` past the 60-day horizon; an undated entry gets
a read first).

**T3 — an entry never survives a promotion.** Delete or mark it in the same edit as the promotion.

**T4-T6 — record and write carefully.** Append one counts line to the caller's record; make surgical
edits to the shared tier files; run on cadence, never as a daemon.

Ask only at a real fork — a verdict the entry's text and the live tree cannot settle.
