- **`/polish` stops for `/compact` when the session's context is already large (dir #739).**
  The per-PR `/polish` tail tracks the primary session's context × turns: windows opened at 250k or more tokens of context carried 442M
  of the 582M measured over 46 closed windows. Step 1 now runs the new `tools/token-report.sh --context` (also
  `keel tokens --context`), which prints one line, `context: <N> threshold: <M> verdict: <compact|stay>`, from the
  session's last turn (`$CLAUDE_CODE_SESSION_ID`'s own transcript; `unknown … verdict: stay` when that cannot be
  read, never a guess). On `verdict: compact` the guide's § Step 1 "Compaction stop" commits all work, writes a
  hand-over file outside the repo, and ends the turn with two paste-ready lines for the operator: `/compact`, then
  a `/polish … after a compaction stop` invocation that reloads the procedure and reads the file. A run that says
  `after a compaction stop` never stops again. The threshold is `KEEL_POLISH_COMPACT_TOKENS` (default 250000; a
  malformed value exits 2, and a huge value such as 999999999 turns the stop off). `tools/self/doctor.sh`'s
  slash-command check allowlists the harness builtin `/compact`. `commands/polish.md` shrinks by one word
  (2,993 → 2,992).
