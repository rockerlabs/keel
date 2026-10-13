- **The pre-PR gate denies `gh pr merge` except to a release manager, pinned, as a merge commit** (dir #811,
  slice S2). `tools/pre-pr-gate.sh` gains a merge rule beside its `gh pr create` rule, reading the command the
  same way: a merge segment is denied unless the session is this repository's release manager, the main
  checkout's `CLAUDE.md` carries a `KEEL-MANAGER-MERGES` line, and the command carries `--merge` and
  `--match-head-commit <40-hex sha>` with none of `--squash`, `--rebase`, `--auto` or `--admin`. A subagent
  never merges, and `gh api …/pulls/<n>/merge` is denied to every session, since it carries no head pin. The
  manager file lists a session when it launches `/manage-release` (Claude's `Skill` call, or the operator's
  typed command), so `tools/install-pre-pr-gate.sh` widens the `UserPromptExpansion` matcher to
  `code-review|manage-release|keel-manage-release` and retires the old `code-review` entry first: re-run the
  installer and restart your sessions. A `settings.json` deny on `gh pr merge` still fires before any hook,
  so the rule takes over only where that deny is lifted. Fixtures:
  [`tests/test_pre_pr_gate_merge.sh`](/tests/test_pre_pr_gate_merge.sh); mutants:
  [`tests/mutants/pre-pr-gate-merge.tsv`](/tests/mutants/pre-pr-gate-merge.tsv). `SECURITY.md` names the rule.
