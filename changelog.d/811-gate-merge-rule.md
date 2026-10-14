- **The pre-PR gate denies `gh pr merge` except to a release manager, pinned, as a merge commit** (dir #811,
  slice S2). `tools/pre-pr-gate.sh` gains a merge rule beside its `gh pr create` rule, reading the command the
  same way: a merge segment is denied unless the session is this repository's release manager, the main
  checkout's `CLAUDE.md` carries a `KEEL-MANAGER-MERGES` line, and the command carries `--merge` and
  `--match-head-commit <40-hex sha>` with none of `--squash`, `--rebase`, `--auto` or `--admin`. A subagent
  never merges, and `gh api …/pulls/<n>/merge` is denied to every session, since it carries no head pin; so
  is a merge the hook cannot place — gh not the command word (`timeout 60 gh pr merge …`, `sudo -u x gh
  …`), or a flag before the subcommand that may take a word as its value (`gh pr --admin merge`) — denied
  with "this merge cannot be read", as is a gh command holding unquoted `pr … merge` words that are not
  its subcommands, or an API call holding a merge-endpoint path it does not call: run gh as the command
  word, its subcommands right after it, quote a word `merge` that is text, and keep a merge-endpoint path
  out of a call that is not a merge. The
  manager file lists a session when it launches `/manage-release` (Claude's `Skill` call, or the operator's
  typed command), so `tools/install-pre-pr-gate.sh` widens the `UserPromptExpansion` matcher to
  `code-review|manage-release|keel-manage-release` and retires the old `code-review` entry first: re-run the
  installer and restart your sessions. A `settings.json` deny on `gh pr merge` still fires before any hook,
  so the rule takes over only where that deny is lifted, and only with jq installed (without jq the whole
  hook is inert). Fixtures:
  [`tests/test_pre_pr_gate_merge.sh`](/tests/test_pre_pr_gate_merge.sh); mutants:
  [`tests/mutants/pre-pr-gate-merge.tsv`](/tests/mutants/pre-pr-gate-merge.tsv). `SECURITY.md` names the rule.
