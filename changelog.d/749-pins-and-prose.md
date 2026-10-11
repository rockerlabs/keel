- **The installer's guards are pinned against the code as it now stands, and the adopter prose is swept.** dir #749
  (the last slice of spec 685 round 2) adds the missing fixtures behind guards the 0.15.0 audit could remove without a
  test noticing: the `bin/` product-directory guard, a copy-mode run over Keel's own stale links, the legacy `-`
  placeholder record (a dead link is Keel's, a live one is not), the `bin/keel` in-sync adopter link whose old record
  must be dropped, uninstall's anchored rails check (a prose-only `CLAUDE.md` is no longer a rails file), the doctor's
  provenance clauses for a dangling link, every `single_def_check` line of the self-doctor (deleted or given an
  `install.sh` exemption), the demo scripts' sandbox-escape rows (one override per run, and a `KEEL_HOME` fixture the
  resolver really reads), and the `$(type -P git) -C` detector's other spellings. Each pin names the mutation that turns
  it red. dir #723 corrects the removal lists (they omit the agent link and `bin/keel`; `uninstall.sh`'s header omits
  `agents/` and `docs/`), says the `templates/CLAUDE.md` map is at the top and where `docs/` goes, dates the
  `LEARNINGS.md` entry format and gives `IDEAS.md` its drop convention (so `docs/triage.md` agrees with both), drops the
  `REVIEW_HISTORY.md` name `docs/triage.md` used for a file nothing ships, restates the FRAMEWORK + PRINCIPLES figure in
  `docs/loading-and-cost.md` (~19.3K; its test now pins the sum to the line's own rounding, not just to ±10%), and lists
  the commands, tools and doc that `docs/reference.md` left out.
