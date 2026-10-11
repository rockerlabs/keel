- **A draft test section that sources `tests/section-guard.sh` now stops before its first git call unless `tests/lib.sh`'s sandbox is loaded.** A worker's scratch
  fixture sourced in a plain shell has no `new_repo`, so `git -C "" config …` wrote the repository the shell stood
  in (once, the main checkout's shared `.git/config`, which broke git in every worktree). `tests/section-guard.sh`,
  sourced right after a draft's `lib.sh` line, exits the shell unless `tests/lib.sh`'s sandbox is loaded, and
  refuses outright under any shell that is not bash (`lib.sh` half-loads under zsh and still returns 0).
  `docs/delegation.md` carries the rail ("Draft test sections"), written for any project's test harness with
  Keel's own form marked; `tests/test_section_guard.sh` pins both. dir #758.
