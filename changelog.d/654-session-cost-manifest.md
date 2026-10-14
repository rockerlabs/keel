- **A release's session cost is two commands, not a hand step** (dir #654). `tools/self/session-cost.sh manifest`
  turns a ledger's `TICKET<TAB>TIER<TAB>MODEL<TAB>BRANCH` lines into the manifest `table` reads, finding each
  worker's session files by the exact `gitBranch` its transcripts record (new `tu_files_for_branches` in
  `tools/lib/transcript-usage.sh`, one scan of the transcripts for the whole ledger) rather than by worktree
  directory or modification time. A branch no session records prints as `# UNMATCHED:`, and a session that
  recorded two ledger branches (it would be priced twice) as `# SHARED:`; either makes `manifest` exit 1. A
  branch listed twice, or a comma in a matched session path, is refused with exit 2 before any row prints.
  `session-cost.sh weighted` sums a manifest at the estimate's weights, the vector `keel tokens` uses
  (`--weights input,write,read`, else `KEEL_TOKENS_WEIGHTS`, else `1.0,2.0,0.1`), primary and subagent shown
  apart, and exits 1 over a manifest carrying either marker. The release-management doc's R7 and the grooming
  doc's G5 point at the commands instead of naming a hand step.
