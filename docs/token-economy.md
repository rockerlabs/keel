# Token economy: where your tokens went, and what to do about it

Third in the line after [`docs/loading-and-cost.md`](loading-and-cost.md) ("what will Keel cost me")
and [`docs/verification-economics.md`](verification-economics.md) ("when has verification stopped
paying") — and the first with a tool behind it. Those two answer questions about Keel itself; this one
answers a question about *your own* agent sessions, on any project, whether or not Keel is involved.

**Run it:** `keel tokens` (dispatches to `tools/token-report.sh`).

```
keel tokens                      # this project (cwd -> repo top), every session on disk
keel tokens --session <uuid|path>  # one session, plus its own subagents
keel tokens --since <YYYY-MM-DD>   # sessions with a turn on/after that date (whole sessions, not a
                                    # partial-session slice)
keel tokens --json                 # machine-readable
```

It reads Claude Code's own per-session transcript files (`~/.claude/projects/**/*.jsonl`) — nothing is
instrumented, collected, or sent anywhere. All parsing goes through `tools/lib/transcript-usage.sh`
(the shared reader built for dir #313, this project's own cost-per-ticket method); this tool never
re-derives the dedupe or subagent-discovery logic that lib exists to centralize.

## A number is not advice

Where earlier tools stopped at totals, `keel tokens` names three patterns instead — the parts of a
token bill nothing else currently shows you:

- **Fan-out.** What share of a session's spend went to subagents, invisible in the session's own
  transcript because it lives in sibling files (`<session>/subagents/agent-*.jsonl`) the transcript
  never references.
- **Cold resumes.** Pauses that outlived the prompt cache, forcing the next turn to re-pay for the
  whole context instead of reading it from cache.
- **Repeated reads.** Which file got re-read the most across a session or a project — the same file,
  loaded again and again, is the plainest form of avoidable spend this data can show.

## Sample output

The numbers below are illustrative — a run against your own project prints your own figures, with the
moment it read stamped in the header (a live corpus never holds still, see "What this report is, and
isn't" below):

```
keel tokens — myproject        42 session(s) · 2026-08-01T09:00:00.000Z … 2026-09-06T18:00:00.000Z (read 2026-09-06T18:45:43Z)

  WHERE THE TOKENS WENT                        tokens      weighted*
    new input                                 253044        253044
    cache writes                          245823685     491647370
    cache reads                        13123531029    1312353103
    output                                 25093276               —
    ------------------------------------------------------------------
    input-side total                                    2057253517

  WHAT DRIVES IT — 3 patterns
    fan-out          21.8% of your spend is subagent work (1242 agents
                     across 111 session(s)). Your session transcript does not
                     show this; it lives in <session>/subagents/.
                     Worst: 8b573f87-fe7a-4d45-9820-7f8d04c27c36 — 7 agent(s), 79.7% of that session.
                     (R7: this cannot say whether the fan-out was worth it — only its size.)

    cold resumes     113 pause(s) outlived the prompt cache and re-paid for the
                     whole context: 35037123 tokens, 3.9% of the input-side bill.
                     25 of them were in the 55-90 min band — minutes, not hours,
                     past the line.
                     (R6: heuristic — a gap >=55min whose next turn rewrites more than it
                     reads. A compaction or /clear can look the same; this cannot tell them
                     apart on its own.)

    repeated reads   BACKLOG.md was read 653 time(s) across these sessions.
                     Worst single session: 47 reads of tools/keel-impact.sh.

  * weighted = a fixed comparison vector (new input 1.0, cache write 2.0, cache
    read 0.1). It is NOT a price. ...
```

## What this report is, and what it is not

Seven refusals, each earned by something measured while building this tool (per the house style set by
[`docs/keel-impact.md`](keel-impact.md)):

- **No money.** Tokens only — no API key exists on a subscription plan. The weighted column is a
  labelled comparison ruler (new input 1.0, cache write 2.0, cache read 0.1 — overridable via
  `KEEL_TOKENS_WEIGHTS="input,write,read"`), printed with "NOT a price" on every run. The read ratio
  matches the cache-hit figure in `docs/loading-and-cost.md`; the write ratio is this tool's own
  assumption, not independently vendor-confirmed — if you can confirm it against a published rate,
  that closes an open item, it does not change how the tool behaves.
- **No context composition.** It cannot tell you "83 MCP tools cost you 36.6k every turn." The
  transcripts carry no system prompt, no tool definitions, no MCP schemas, no memory or skill content —
  only the harness's own context panel shows that.
- **Claude Code only.** The transcript format is one harness's. On a machine with no Claude Code
  transcripts at all, the report says so plainly rather than printing a confidently empty answer.
- **Not available on an ephemeral install.** Like the `keel` CLI and the `/polish` gate installer
  before it, this needs a kept checkout (`tools/` is never copied by the one-line bootstrap install —
  see `install.sh`'s own disclaimer for what to do instead).
- **Volume is not waste.** The report names patterns; it never scores a session as good or bad, and it
  never ranks one session against another. A session that spent more may simply have done more.
- **The cold-resume line is a labelled heuristic, not a fact.** A pause classified as "cold" is a gap of
  at least 55 minutes whose next turn rewrites more of the context than it reads from cache — but a
  compaction or a `/clear` can produce the exact same signature with no pause at all. The report prints
  the rule inline, not only here.
- **Fan-out attribution stops at the session.** It can say a session spent 21.6% on subagents; it
  cannot say whether that fan-out was worth what it found. That needs structured review findings this
  data source does not carry.

**The corpus is live, and a run against your own history is measuring a file it is still writing.**
Two runs minutes apart can report slightly different totals — the report stamps the moment it read
(shown in the header) so a number is never presented as more final than it is. Transcript retention is
also an adopter setting (`cleanupPeriodDays` in Claude Code), so the report states the window it
actually found rather than implying it has your whole history.

## Isolation

- `KEEL_TOKENS_PROJECTS_DIR` overrides where transcripts are read from (default:
  `${KEEL_HOME:-$HOME/.claude}/projects`, matching `tools/lib/transcript-usage.sh`'s own resolution).
- `KEEL_TOKENS_WEIGHTS="input,write,read"` overrides the default comparison vector `1.0,2.0,0.1`. A
  malformed value is ignored with a warning rather than silently corrupting every figure downstream.

## When a pause is expensive

The report's cold-resume line answers a question worth a little more context: the prompt cache is a
TTL'd asset (about an hour on this harness, refreshed by every request). A pause that outlives it means
the next turn re-pays for the *entire* accumulated context at full price instead of the roughly 10% a
cache read costs — measured here at a sharp cliff between a 45-55 minute gap (about 11% classified
cold) and a 55-65 minute one (about 82%).

Three ways to think about that gap, in order of how much machinery each needs:

- **An unconditional keep-alive daemon — rejected.** Pinging a session on a fixed schedule to keep the
  cache warm pays a small cost (about a tenth of a full re-price) to avoid a *possible* full re-price
  later, but it pays that cost through every idle stretch, including ones that end in a hard usage-quota
  lockout where the ping cannot even help (the request will not process, and the cache expires
  regardless). Keel ships no scheduler and no daemon, so this stays a rejected idea, not a built one.
- **A bounded, condition-gated keep-alive — the felt case, and positive-value in a narrow band.** If a
  session is blocked waiting on a human's answer, quota is comfortably above the spend, and the wait is
  not already a hard lockout, a handful of pings (2-3, each at the roughly-10% cost) can cover the
  "stepped away for just over an hour" case that a single cold resume would otherwise re-price in full.
  Measured here: this addressable band is about 1.1% of the input-side bill corpus-wide — real, but
  small, and it needs machinery Keel does not ship: an *operator-installed* external watcher (a
  scheduled task or script) that notices a session idle-on-a-question past the TTL and injects a small
  message. **The human installs the watcher; the agent never schedules its own keep-alive** — an agent
  optimizing its own warm-ups has no way to know when the human will actually return, while a human
  installing a bounded watcher does.
- **Planned absence (the overnight case).** For a known, longer absence — a wave of work left running
  overnight, say — the right number of pings is derived from the known return time rather than fixed at
  2-3, and the arithmetic favors pinging further out (a cold resume does not just re-read the context,
  it re-*writes* the cache at a premium over plain input, pushing the real break-even well past ten
  hours of idle time).

One sharp edge if you build a watcher of your own: the cache discount applies to *input* only. A
keep-alive ping must ask for a no-op, one-word reply ("keep-alive, reply ok, take no action") — a ping
phrased as "check status" triggers real tool turns and re-prices the whole context per turn, turning the
warmer into the very thing it was meant to avoid.

## See also

- [`docs/loading-and-cost.md`](loading-and-cost.md) — what Keel's own always-loaded files cost.
- [`docs/session-cost.md`](session-cost.md) — this project's own cost-per-ticket method, built on the
  same shared transcript reader.
- [`docs/keel-impact.md`](keel-impact.md) — the house style for "what this measures, and what it does
  not" that this doc follows.
