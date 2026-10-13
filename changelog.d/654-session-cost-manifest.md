- **A release's session cost is two commands, not a hand step** (dir #654). `tools/self/session-cost.sh manifest`
  turns a ledger's `TICKET<TAB>TIER<TAB>MODEL<TAB>BRANCH` lines into the manifest `table` reads, finding each
  worker's session files by the exact `gitBranch` its transcripts record (new `tu_files_for_branch` in
  `tools/lib/transcript-usage.sh`) rather than by worktree directory or modification time; a branch no session
  records prints as `# UNMATCHED:` and exits 1 instead of vanishing. `session-cost.sh weighted` sums a manifest
  at the estimate's weights, the vector `keel tokens` uses (`--weights input,write,read`, else
  `KEEL_TOKENS_WEIGHTS`, else `1.0,2.0,0.1`), primary and subagent shown apart. The release-management doc's
  R7 and the grooming doc's G5 point at the commands instead of naming a hand step.
