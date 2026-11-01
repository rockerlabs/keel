- `tools/lib/ledger.sh` is now sourced behind the same `[ -s ] && bash -n` guard as the other libs, at all four
  sites (`install.sh`, `uninstall.sh`, `tools/install-pre-pr-gate.sh` twice). A corrupted or truncated copy used to
  abort the run at parse time with a raw bash trace. Now each site prints one line and skips only its
  discovery-index write or prune (exit 0). `doctor --install` reports the gap with matching wording (dir #378).
