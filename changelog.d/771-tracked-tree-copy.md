- Three install/core-ownership tests (`test_install_symlink_policy.sh`, `test_install_product_dirs.sh`,
  `test_core_marker_anchor.sh`) now build their scratch checkout with `tracked_tree_copy` (the tracked
  top-level entries) instead of copying the whole working tree, so a run from the main checkout no longer
  drags `.git/`, `private/` and every `.claude/worktrees/` tree into the sandbox (dir #771).
