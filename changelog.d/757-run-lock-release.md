- **`install.sh` no longer leaves its run lock behind when it stops early.** Every exit after the lock is
  taken and its pid recorded now releases it — a refused write, a failed check, a missing library, a
  `set -u` abort, Ctrl-C or `kill` — through one exit trap in the completion-marker form, so an abort is
  still reported as a failure, never as success; Ctrl-C and `kill` exit 130 and 143. A run removes the
  lock only while it still names that run, so a lock another install has taken over is left alone. A
  missing `tools/lib/safe-write.sh` is now caught before the home is created, so that refusal leaves
  nothing behind. Only a crash no handler can follow (`kill -9`, a power loss) still leaves the lock,
  which the next run reclaims as before (dir #757, dir #756).
