# Session cost — what does a unit of work on this project actually cost?

**Keel-self-maintenance.** This document and the tools it describes
(`tools/lib/transcript-usage.sh`, `tools/self/session-cost.sh`) answer "what does OUR pipeline cost" —
they are never installed by `install.sh` and ship nothing adopter-facing. The adopter-facing capability
this investigation feeds — "where did my tokens go, and what should I do about it" — is a separate
product (dir #314), tracked in its own doc once it ships.

## The founding error, kept because the failure mode outlives the figure

This ticket (dir #313) was opened on a false premise: that a one-line ticket costs the same as a hard
one, based on two sessions read off the app's own context panel in PARALLEL — a panel delta covering
two overlapping sessions can never be attributed to either one alone, and the reading violated its own
stated "serial runs required" caveat. The transcripts said otherwise (roughly 2x apart on every axis).
**Two further, independent corrections landed after that retraction, both discovered mid-release by a
sibling design pass (dir #314) and both fixed at the source before this ticket's own tooling shipped:**

1. **The `requestId` dedupe.** One API response that carries a thinking block, a text block, and a
   tool_use block is logged as 2-3 separate transcript lines sharing one `requestId`, each stamped with
   the SAME cumulative token count. Summing usage naively multiplies it by the occurrence count — a
   ~1.89x inflation, independently reproduced twice (30,338,459 naive vs. 16,058,364 deduped on one
   session, exact agreement both times).
2. **The subagent blind spot.** Fan-out spend (a `/code-review` or `/simplify` subagent) lives in
   SIBLING FILES the parent transcript never references, and `isSidechain` — the field this ticket's
   first draft assumed would separate primary from fan-out — is `false` throughout every primary file
   and gives no signal there at all. Corpus-wide, subagent spend is roughly a fifth of everything;
   session-by-session it ranges from negligible to more than the primary session itself.

Both are structural correctness defects in the READING, not in the underlying token accounting, and
both are now fixed in `tools/lib/transcript-usage.sh` — the one shared reader this ticket's own
`tools/self/session-cost.sh` and dir #314's adopter-facing report both import, specifically so neither
defect can be silently reintroduced by a second, independent implementation.

## The method

**Cost per ticket, grouped by (R-tier, model) cell, on deduped tokens — never a single scalar across
the whole project, and never a mean.**

- **Unit of comparison:** a ticket's cost is the sum, over every session that touched it (a ticket can
  span a start/cancel/restart across several sessions), of `deduped(cache_read_input_tokens) +
  deduped(output_tokens)`, restricted to primary-session records. Subagent fan-out is reported as its
  own separate figure, never folded in — folding it in would re-obscure the per-pipeline-stage
  breakdown this project already extracts via `attributionSkill`.
- **Grouped by (R-tier, model):** mixing an opus session with a sonnet one in the same bucket implies a
  false equivalence (the two are priced roughly 5x apart per token). R-tier is a per-ticket heading tag
  this project's own backlog convention already carries; it is not derivable from a transcript, so the
  tool takes it as given rather than trying to mine it.
- **Median, not mean, per cell:** cell sizes are single digits today, and one unusually long session
  (a multi-day lifecycle with several review rounds) would otherwise dominate a mean.
- **Denominated in tokens, not USD:** this project runs on the same subscription model dir #314's
  adopter-facing tool assumes for adopters — no API price applies to either.

Two candidate metrics from the ticket's own body — **cost per confirmed defect** and **cost per
convergence round** — are documented as future work, not built: neither is computable from data on disk
today (no durable, structured findings-count record survives per session; `pre-pr-gate`'s own
convergence trace is an ephemeral `/tmp` sentinel that does not survive to be read back later).

## The corrected table

The eight sessions this ticket's own body first measured (2026-08-29/30), re-run through the deduped,
subagent-inclusive method above. `msgs` is now the count of distinct API turns (deduped by
`requestId`), not raw transcript lines; `ctx/msg` is cache-read per turn, the average conversation size
being re-sent every turn. The `subagent` column is new — this data did not exist under the old method.

| ticket | R-tier | model | msgs | output | cache-read | ctx/msg | subagent (turns / output / cache-read) |
|---|---|---|---|---|---|---|---|
| dir #183 | R1 | opus | 247 | 222,966 | 80,026,572 | 323,994 | 623 / 29,012 / 81,747,300 |
| dir #289 | R1 | sonnet | 281 | 223,133 | 96,865,274 | 344,716 | 183 / 15,603 / 17,035,483 |
| dir #299 | R3 | sonnet | 269 | 183,523 | 77,432,309 | 287,852 | 171 / 13,312 / 13,842,155 |
| dir #304 | R1 | sonnet | 256 | 150,777 | 71,111,007 | 277,777 | 135 / 23,580 / 10,413,866 |
| dir #296 | R1 | sonnet | 314 | 122,020 | 81,163,050 | 258,481 | 192 / 20,960 / 13,722,825 |
| dir #287 | R1 | sonnet | 171 | 71,890 | 30,427,700 | 177,939 | 122 / 11,346 / 8,174,134 |
| dir #298 | R1 | sonnet | 106 | 39,782 | 16,058,364 | 151,494 | — (no subagents spawned) |
| dir #301 | R1 | sonnet | 187 | 67,857 | 35,874,395 | 191,841 | 64 / 8,507 / 3,638,820 |

**(R-tier, model) cell medians, cost = cache-read + output:**

| tier | model | n | median cost (tokens) |
|---|---|---|---|
| R1 | opus | 1 | 80,249,538 |
| R1 | sonnet | 6 | 53,602,018 |
| R3 | sonnet | 1 | 77,615,832 |

**Four things this re-run settles that the original table could not:**

1. **The dedupe roughly halves every absolute figure** (dir #298's cache-read: 30.3M naive → 16.1M
   deduped, a 47% reduction) — the *shapes* the original body found (scaffolding share, `/wrap` as the
   second-largest stage, `/code-review` growing with difficulty) survive because they're ratios computed
   consistently the same wrong way on both sides of each comparison, but no absolute figure from the
   original table should be quoted again.
2. **Subagent spend is not a rounding error.** dir #183's fan-out (81.7M cache-read) is larger than its
   own deduped primary total (80.0M) — a `/code-review`-heavy ticket can spend as much on subagents as
   on the primary conversation driving them, invisible to any method that only opens the primary
   transcript.
3. **The two corrections partially cancel for a fan-out-heavy ticket, by coincidence, not by design.**
   dir #183's ORIGINAL naive figure (170.8M) and its corrected total (deduped primary 80.0M + subagent
   81.7M = 161.8M) land close to each other — dedupe pulls the number down, restoring the subagent total
   pulls it most of the way back up. Do not read this as validation of the old method: dir #298, which
   spawned no subagents, shows the full 47% drop with nothing to offset it.
4. **The R1/sonnet cell already shows the mean/median gap the method is meant to guard against**, even
   with only six data points: costs range from 16.1M to 97.1M, mean ≈55.4M, median 53.6M. The gap is
   modest here because this particular cell has no single outlier session yet — but the shape (n=6, one
   session more than 6x the smallest) is exactly the one a mean quietly lets dominate as more tickets
   accumulate in a cell, which is why the metric is fixed as a median now rather than switched to one
   later once a real outlier lands.

## Running it yourself

```
tools/self/session-cost.sh session ~/.claude/projects/<slug>/<session-uuid>.jsonl
tools/self/session-cost.sh ticket R1 sonnet <session-file> [<session-file>...]
tools/self/session-cost.sh table <manifest.tsv>
tools/self/session-cost.sh selfcheck <session-file>...
```

A manifest is a tab-separated file, one ticket per line: `TICKET<TAB>TIER<TAB>MODEL<TAB>FILE1[,FILE2,...]`.
Session files are resolved by hand today (`tools/lib/transcript-usage.sh`'s `tu_session_files` finds
every session belonging to a repo, including its worktrees; matching one to a ticket is a `gitBranch`
lookup dir #313's own body already worked out — see that ticket for the mechanism). `selfcheck` is the
visible guard against a transcript format that moves silently: it names any record type the reader has
never seen before, rather than absorbing it into "known, ignorable" without comment.

## Caveats, unchanged from the original investigation

- **Machine-local, untracked, no backup.** Transcripts live outside this repo
  (`~/.claude/projects/...`), survive worktree and branch deletion, but a disk or machine change loses
  them entirely; `cleanupPeriodDays` is a local retention setting, and an adopter's default may be far
  shorter than this machine's.
- **R-tier lookup is manual.** A ticket's (R-tier, model) cell comes from its own `BACKLOG.md` heading
  tag, read by hand into the manifest — this is mechanical but not automated; a heavily-cited ticket is
  worth double-checking against `git log` if its heading has since been edited.
- **Cost per confirmed defect** and **cost per convergence round** are named, not built (see "The
  method" above) — durable structured data for either does not exist yet.
- **The ledger join** (pairing this cost data against `tools/keel-impact.sh`'s own influence score,
  `influence(ticket) ÷ cost(ticket)`) needed a structured `ticket` column on the ledger that did not
  exist before this release (dir #406) — it now does; the join script itself is still unbuilt.

## See also

- `tools/lib/transcript-usage.sh` — the shared transcript reader (dedupe, subagent enumeration, path
  normalization), imported by this tool and by dir #314's adopter-facing report.
- `docs/keel-impact.md` — the ledger this ticket's `ticket` column (dir #406) now lets join against.
- dir #314 (this project's own backlog) — the adopter-facing capability this investigation feeds.
