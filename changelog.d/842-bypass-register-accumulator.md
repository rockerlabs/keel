- **A guard's known-bypass register now counts real sightings.** The pre-PR gate's header and its subagent floor
  carry 12 <!-- claim: matches '\[bypass:' tools/pre-pr-gate.sh --> `[bypass:<class>]` keys, one on each command-reading entry
  they list today, and `tools/self/known-bypass-shapes.tsv` holds
  one detection pattern per key. `tools/self/bypass-scan.sh` reads Claude Code's session transcripts, lists the
  candidate commands per class and per parent session (a subagent's command counts under its parent) into a
  scratch file outside every repository, and prints the `accumulate.sh new-class` lines that register the classes
  in the guards' own data dir. The groom's G0 gains the step that runs the scan, adjudicates each candidate,
  closes promoted classes and files whatever `accumulate.sh due --owner guards` lists, so a shape a real session
  writes twice in 90 days (once, for a guard whose miss leaks or destroys data) becomes a ticket on its own. This
  finishes dir #842 slice 4; `tests/test_bypass_scan.sh` pins each listed entry's key and each key's shape row (a command-reading
  entry added later without a key is not yet caught by it) and runs the scan and the accumulator's ageing on
  fixtures.
