- **A draft test section sourced without `tests/lib.sh` now stops before its first git call.** A worker's scratch
  fixture sourced in a plain shell has no `new_repo`, so `git -C "" config …` wrote the repository the shell stood
  in (once, the main checkout's shared `.git/config`, which broke git in every worktree). `tests/section-guard.sh`,
  sourced as a draft's first line, exits the shell unless `tests/lib.sh`'s sandbox is loaded, and
  `docs/delegation.md` carries the rail ("Draft test sections"); `tests/test_section_guard.sh` pins both. dir #758.
