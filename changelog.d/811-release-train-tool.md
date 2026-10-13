- **Release trains are built by a tool, not hand-typed git (dir #811 slice S3).** `tools/self/release-train.sh`
  (keel-self-maintenance; git only, never pushes) turns a list of `N=SHA` frozen heads into one train branch:
  `build` creates its own worktree, refuses an existing branch, a non-empty worktree path or an unknown sha
  before any git write, checks every pair of heads with `git merge-tree`, merges each `--no-ff` as
  `train: #N (sha)` in the given order and prints the seam list; `build --continue` appends the rest after
  a hand-resolved conflict or a moved head; `body` prints the train PR body from the branch's own
  first-parent walk (table never retyped, hand-resolved merges and integration commits listed wherever
  they sit); `check` names every constituent whose live head moved. `tests/test_release_train.sh` pins it.
