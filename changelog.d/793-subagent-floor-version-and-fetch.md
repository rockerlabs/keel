- The subagent git floor (dir #675) is no longer silently off on git < 2.31 and now sees ref-writing forms
  (dir #793). It resolved the session repository with `git rev-parse --path-format=absolute --git-common-dir`,
  which git < 2.31 rejects, so a subagent's `git commit`, `git push` and `git stash` in the session repository
  passed with no notice; it now resolves the common dir portably (`--git-common-dir`, then `cd … && pwd -P`).
  `git fast-import` and `git pack-refs` join the mutating verbs, and `git fetch` is denied when a refspec names
  a local `:dst` outside `refs/remotes/` (`git fetch origin +main:b`, `git fetch . a:b`); plain `git fetch`,
  `git fetch origin` and `git fetch origin main` stay allowed. `git subtree`, `git fetch --tags`,
  `fetch --set-upstream` and a refspec set only by config are named as blind spots in the gate header and
  `docs/delegation.md`.
