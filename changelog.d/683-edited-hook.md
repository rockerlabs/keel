- **`install-secret-guard.sh` no longer overwrites a Keel hook you edited.** A hook was Keel's whenever its second
  line was the marker, so a pre-commit or pre-push that you had extended after install (marker kept, your own steps
  added) was replaced by the next plain re-install, with no backup and no prompt. It is now Keel's to refresh only when
  its whole body is one of the versions this repo has shipped (`tools/secret-guard/shipped-hook-sums`, one POSIX
  `cksum` line per version shipped so far); anything else behind the marker is treated as yours: a plain install
  refuses and names why, and `--force` first saves it to `<hook>.pre-keel.bak` like any other foreign hook. An older
  shipped version is still refreshed without `--force`. The list has to grow with the hooks: a test fails until the
  next hook change adds its line (dir #683).
