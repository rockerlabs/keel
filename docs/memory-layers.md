# Memory layers — does Keel do memory, and what do I do about staleness?

*For adopters. Read it when you ask "what does Keel do about memory?" or when an assistant keeps
acting on something that stopped being true. Nothing here loads into a session by itself.*

Short answer: Keel does **not** build a memory store — your assistant's harness already has one. It
organizes what goes *into* that store, and it ships the one thing a store never does for itself:
**noticing what should be forgotten.** That check is [`tools/doctor.sh`](../tools/doctor.sh), and it only
reports — it never deletes or rewrites a memory file. Cleanup is always your action.

## 1. The five layers, and where Keel stands on each

The vocabulary is the one cognitive-science-flavoured agent papers use (§5). The table maps it onto files
you already have.

| Layer | The question it answers | Keel artifact | Who maintains it | Watched by |
|---|---|---|---|---|
| **Working** | What does the assistant hold in mind right now? | the always-loaded core + the project's `CLAUDE.md`; the session's own context | you, by keeping them small | `doctor` `H-FOOTPRINT` (startup size) |
| **Episodic** | What happened, and when? | git history, `CHANGELOG.md`, closed backlog tickets, `LEARNINGS.md` | git and `/wrap` — append-only | nothing, by design (history is the product, not a cache) |
| **Semantic** | What is true about this project / this person? | the harness's memory files and their `MEMORY.md` index; one file = one topic | the assistant writes, you review | `doctor` `W-MEMORY-ORPHAN`, `W-MEMORY-DANGLING` |
| **Procedural** | How do we do things here? | `commands/*.md`, `docs/*.md`, the rails in the core — versioned by git, promoted when a lesson repeats | you, through reviewed changes | nothing, by design (git is the audit) |
| **Forgetting** | What should stop being believed? | the three operations in §3 | **you** — Keel only finds candidates | `doctor` `W-MEMORY-SUPERSEDED`, `H-MEMORY-STALE`, `H-MEMORY-DIR-UNRESOLVED` |

Four of the five layers were already covered by files Keel ships. Forgetting was the gap: a store that
only ever grows serves stale facts with the same confidence as fresh ones, and a confidently wrong
memory is worse than none (PRINCIPLES.md P1, P2).

## 2. What Keel deliberately does NOT build, and why

Each line is a thing the next playbook will suggest. Each is ruled out by a principle, not by taste.

- **A memory store** (a database, a JSONL log, a vector index). The harness owns storage and will keep
  changing it; a mechanism built on today's store is depreciating capital (P0). Keel reports on the
  files the harness already writes.
- **A retrieval layer** (embeddings, ranked recall). Recall quality is the harness's job; a second
  retriever adds a layer that can be wrong without telling you (P1) and one more thing to keep current (P0).
- **A TTL on episodic memory.** Expiring history by age throws away the thing that is cheapest to keep
  and most expensive to recover. Only *claims about the present* go stale, and those live in semantic
  memory (P2: noise comes from stale facts, not from old events).
- **Automatic supersession** (a tool that decides which of two memories wins and rewrites the loser).
  Deciding which fact is true is a judgment call; a tool that guesses silently manufactures confident
  errors (P1). `doctor` flags; a person decides.
- **An ontology schema** (typed entities, relations, required fields). No felt problem has asked for one
  (P4), and a schema is the first thing a harness upgrade invalidates (P0).
- **A token-saving memory budget.** The scarce resource is the reasoner's attention on the right fact,
  not the visible token meter (P3). `doctor` deletes noise because noise misleads, not to save tokens.

If a vendor reports big savings from one of these, treat the figure as a claim by the party selling it;
it says nothing about whether the memory was *correct*.

## 3. The three forgetting operations

You run these by hand; `doctor` points at the candidates.

**Expire — a note nobody can reach, or that outlived its subject.**
- A file the index never links is unreachable: no session recalls it. `doctor` reports
  `W-MEMORY-ORPHAN`. Add its index line if it still matters, otherwise delete the file.
- An index line whose file is gone is `W-MEMORY-DANGLING`. Remove the line or restore the file.
- A note older than the code it describes is suspect. `H-MEMORY-STALE` lists them (opt-in, below).
  Re-check the claim against the code, then refresh the note or delete it.

**Supersede — a newer fact replaces an older one.** Write the correction **into the existing file**
and delete the old record. Never create a second file ("auth-v2") and never append "UPDATE: …" — both
leave two answers and make the reader pick one. Marking a line `SUPERSEDED` or `RETRACTED` is a fine
intermediate step, and it is exactly what `W-MEMORY-SUPERSEDED` fires on: the delete is still owed, and a
dead record is loaded into every session until you do it.

**Contradiction — two memories disagree.** Do not let the assistant, or a script, resolve it. Put the
conflict in front of a person, decide which holds, then apply *supersede*. A silent pick is a
confident answer with nothing behind it (P1).

### Running the checks

```bash
keel doctor                 # orphan / dangling / superseded findings
keel doctor --memory-age    # also list notes older than the code they name
```

- The checks read Claude Code's layout: `projects/<project path, every / and . written as ->/memory`
  under your Claude home (`KEEL_HOME`, else `~/.claude`). Set `KEEL_MEMORY_DIR` to point at any other
  directory. `doctor` prints which directory it read. If it finds none, your Claude home does have a
  projects directory, **and** your path contains a character it cannot encode (an underscore, a space),
  it says so (`H-MEMORY-DIR-UNRESOLVED`) rather than quietly checking nothing. On a harness with its own store (Codex, for one) the checks stay silent
  by design — that is no claim that such a store needs no care.
- Every ID can be accepted per project in `.keel/doctor-accept`, like any other `doctor` finding.
- `H-MEMORY-STALE` compares a note's date (its last git commit if the memory directory is a repository,
  else a `modified:` line in its frontmatter, else the file's modification time) with the newest commit
  on any existing path the note names in backticks. It is **opt-in**: on Keel's own memory
  directory it flagged most notes, because notes that name `CHANGELOG.md` or a whole folder are always
  "older than the code". A check that fires on most files trains you to skip it. Use the flag for a
  periodic sweep, not as a standing gate.

## 4. Four ten-minute memory tests

Run them against your own setup. Each takes two sessions or one careful one.

1. **Amnesia.** In session 1, state a project fact and ask the assistant to remember it. In a fresh
   session 2, ask for it. *Exercises:* the harness's write path and the `MEMORY.md` index. A miss usually
   means the file was written but never indexed — run `keel doctor` and look for `W-MEMORY-ORPHAN`.
2. **Contradiction.** Add two memories that disagree (say, two test commands). Ask the assistant to run
   the tests. *Good:* it notices the conflict and asks. *Bad:* it picks one without comment. *Exercises:*
   the one-file-one-topic rule in `FRAMEWORK.md` and the contradiction operation above.
3. **Staleness.** Write a memory describing a script, then change the script and commit. Ask something
   the memory answers. *Good:* the assistant re-checks the code first. *Exercises:* the "Staleness check"
   paragraph in `FRAMEWORK.md`; then `keel doctor --memory-age` should list the note.
4. **Isolation.** Record a fact that belongs to project A, then open a session in project B and ask
   about it. It must not surface. Then record a *cross-project* preference (from the global knowledge
   base) and confirm it does surface everywhere. *Exercises:* the cwd-silo rule in `FRAMEWORK.md` — project
   facts in the project's memory, cross-project facts in a global file.

A test that fails is a finding about your setup, not about the assistant: fix the file, the index, or the
rule, and run it again.

## 5. Sources

- The five-layer vocabulary comes from Sumers, Yao, Narasimhan and Griffiths, "Cognitive Architectures
  for Language Agents" (arXiv:2309.02427) — cited for its terms, not for any result.
- Keel's design pass also read an independent practitioner compilation on agent memory. Its storage
  recipes are application-level and not adopted here; the figures it quotes are vendor-reported and are
  deliberately not repeated on this page. Keel's own tests are §4.
