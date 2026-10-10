- **`tools/doctor.sh`'s secret-guard checks stop saying OK when the guard is not whole.** dir #747:
  Keel's `pre-push` absent or not executable beside a working `pre-commit` — and a `secret-scan.sh` absent beside Keel's hooks — is now a
  `W-GUARD-UNWIRED` / stale finding in `--install` and the per-repo audit (a commit made with hooks bypassed used to
  reach the remote while doctor said OK; a user's own hooks dir keeps its old bar). An EMPTY or valueless
  `core.hooksPath` is named, with the way out per scope (the old advice was refused by the installer), a
  worktree-scope setting gets `--worktree` advice, and `--install` checks the `artifact-cksum.sh` and `safe-write.sh`
  libs that `install.sh` and `uninstall.sh` require (`G-REQUIRED-LIB`). The env-file floor now scans a project whose own
  root is named `build`/`dist`/`out`/`vendor`/`target`, and also reports `*.env.bak`-style backups and upper-case
  `*.ENV`.
