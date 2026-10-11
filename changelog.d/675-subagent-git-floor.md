- **A subagent's literal git commands that change your repository are now refused.** dir #675: the pre-PR gate's Bash hook now
  denies a *subagent's* repository-mutating git command — `checkout`, `restore`, `reset`, `clean`, `stash`,
  `commit`, `push`, `rebase`, the write forms of `branch`, `tag`, `config`, `remote`, `worktree` and the other
  verbs that change the tree, the index or the refs (what it leaves open is in
  [`docs/delegation.md`](/docs/delegation.md)) — when it is aimed at the session's repository or any worktree of it, found through the payload cwd, the `cd`s before it, `-C`, `--git-dir`/`GIT_DIR` and
  `--work-tree`/`GIT_WORK_TREE`. Reads, and work in a scratch clone (`git -C <clone>`), are untouched; your own
  commands are never touched. It needs no installer re-run: a `git pull` is enough, in every session whose gate is
  wired. It needs git 2.31 or newer (an older git leaves the floor silently off), and `git fetch <remote> +src:<local-branch>` and other plumbing ref writers pass. It is a seatbelt, not a sandbox — a script, `sh -c`, an alias, a variable path or a plain `rm` are not
  seen. A subagent started with `isolation: "worktree"` is denied its own commits too.
  `KEEL_SUBAGENT_GIT_FLOOR=off` in the session environment switches it off; the PR and push rules stay.
