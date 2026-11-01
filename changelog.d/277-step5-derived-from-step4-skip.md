- `/polish` step 5 is no longer receipted for `skip`, and the gate now binds a `skip` unlock to the commit
  being shipped in every repo (dir #277). The gate derives `polish.5-review skip` from step 4's own skip
  receipt (`receipt` stamps it with the commit it was decided against, dir #236), so the contentless step-5
  write, and the forgotten-receipt class it caused, is gone; writing it by hand is still accepted and
  changes nothing. A new intact deny, `skip-stale-commit`, fires when that stamp is not the commit being
  shipped, or when step 4's skip carries no stamp at all. It closes a hole in UNARMED repos, which had no
  per-commit binding on a skip (a skip decided at commit A, then a fix commit, still unlocked); ARMED repos
  are unchanged, since they already needed a `dialog:skip` at HEAD. The stamp, and the `--recover`
  narrowing that reads it, stay: recovery withholding is the early signal that sends a convergence round
  back to step 4. To clear the deny, write step 4's receipt fresh for the current HEAD; no `init`.
