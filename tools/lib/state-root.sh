# shellcheck shell=bash
# tools/lib/state-root.sh — the ONE resolver for keel's own durable state (dir #637): every store lives
# under a single root per machine, `$HOME/.keel`, independent of any harness. Before this file the
# impact store and the read-trace store lived inside the HARNESS home (`${KEEL_HOME:-$HOME/.claude}/.keel`),
# which a harness migration (2026-08-24) and an `rm -r ~/.claude` (2026-09-22, dir #627/#630) each took
# with them, stores included.
#
# Sourced, not executed — no shebang requirement, no `set -e` (inherits the caller's), no `set -u`
# assumption. Same conventions as tools/lib/impact-store.sh.
#
# `KEEL_HOME` names the harness home keel installs INTO (the always-on file, commands, hooks, install
# manifests); keel's own state lives in `$HOME/.keel`. The variable keeps that delivery role; its old
# second role as keel's state root is retired. Only `keel_legacy_store_root` below still reads it for
# state, to find a store that has not been moved yet.
#
# No override variable for the root itself: tests already redirect `$HOME` (tests/lib.sh), so `$HOME/.keel`
# follows the sandbox for free. A per-store override exists only where a real need was shown — today one:
# KEEL_MACHINE_WATCH_STORE (keel_machine_watch_store below), which tests/lib.sh points into the sandbox and
# tools/lib/impact-store.sh's IMPACT_ISOLATION_VARS names, so a store resolver cannot read it unisolated.
#
# Names under the state root — each name once, here (B6). A new name joins this list in the PR that
# introduces it:
#   in use:    tmp          (tools/lib/gate-paths.sh gate_state_root: the gate's rendezvous files)
#              impact       (tools/lib/impact-store.sh impact_store_root)
#              read-trace   (tools/lib/read-trace.sh read_trace_store_root)
#              machine-watch, machine-watch.paths   (tools/machine-watch.sh: the baseline store, and the
#                           user-authored extra-paths file; dir #437 PR2)
#   reserved:  config, config.d                      (dir #257)
# Stays per harness, under `${KEEL_HOME:-$HOME/.claude}/.keel/`, unchanged by dir #637:
# `install-manifest.*`, `foreign-core.*`, the install scratch and `doctor-accept` — they describe ONE
# install and are moot once its home is gone.
#
# Every function prints WITHOUT a trailing newline (the convention of impact_store_root) and prints
# nothing on failure.

# keel_state_root — `$HOME/.keel`; rc 1 and no output when `$HOME` is unset or empty.
keel_state_root() {
  [ -n "${HOME:-}" ] || return 1
  printf '%s/.keel' "$HOME"
}

# keel_legacy_store_root NAME [HARNESS_HOME] — the retired address of store NAME:
# `${HARNESS_HOME:-${KEEL_HOME:-$HOME/.claude}}/.keel/NAME`. The one spelling of it: the transition
# rung below, the store-migration tool (dir #637 PR2) and doctor's W-STATE-LEGACY all call it.
# rc 1 and no output when no harness home can be named (no argument, no KEEL_HOME, no HOME).
keel_legacy_store_root() {
  local name="$1" base="${2:-${KEEL_HOME:-}}"
  if [ -z "$base" ]; then
    [ -n "${HOME:-}" ] || return 1
    base="$HOME/.claude"
  fi
  printf '%s/.keel/%s' "$base" "$name"
}

# keel_legacy_store_entries NAME [HARNESS_HOME] — the entries of a legacy store still to be moved: every
# direct child of keel_legacy_store_root that is a real directory (symlinks and files are skipped — a
# symlink is what a finished migration leaves behind), dot-names included, one per line. Prints nothing
# when the root is absent or holds none. The one definition of "an entry": tools/state-root-migrate.sh
# moves exactly what it lists, and doctor's W-STATE-LEGACY warns on exactly what it lists.
keel_legacy_store_entries() {
  local root e
  root="$(keel_legacy_store_root "$@")" || return 0
  for e in "$root"/* "$root"/.[!.]* "$root"/..?*; do
    if [ -d "$e" ] && [ ! -L "$e" ]; then printf '%s\n' "$e"; fi
  done
}

# keel_machine_watch_store — the machine-global watcher's baseline store (dir #437 PR2): $KEEL_MACHINE_WATCH_STORE
# when set (tests, an operator's own location), else keel_store_root machine-watch. The one definition both
# tools/machine-watch.sh and tools/install-machine-watch.sh call, so the dir the installer pre-creates is the
# dir the watcher reads — the watcher reads the store's absence as a removal.
keel_machine_watch_store() {
  if [ -n "${KEEL_MACHINE_WATCH_STORE:-}" ]; then printf '%s' "$KEEL_MACHINE_WATCH_STORE"; return 0; fi
  keel_store_root machine-watch
}

# keel_store_root NAME — where store NAME lives. Rungs, in order, R = keel_state_root's output:
#   1. keel_state_root fails            → print nothing, return 1.
#   2. R/NAME is a directory            → R/NAME   (`-d` follows a symlink: a moved store whose old
#                                          address is a compat link, or a new root that is itself a link)
#   3. the legacy store is a directory  → it       (the TRANSITION rung: between an upgrade and the move
#                                          by install.sh, link-mode hooks already run this code against
#                                          data that has not moved yet — a hard cut would split every
#                                          read-trace history and read impact as `moved`)
#   4. otherwise                        → R/NAME   (a fresh machine; the first write creates it)
# The test is per store, never on R itself: `$HOME/.keel` already exists wherever `tmp` is in use. A
# dangling legacy symlink fails `-d`, so it falls through to rung 4.
keel_store_root() {
  local name="$1" root legacy
  root="$(keel_state_root)" || return 1
  if [ -d "$root/$name" ]; then printf '%s/%s' "$root" "$name"; return 0; fi
  # HOME is non-empty here (rung 1), so the legacy address always resolves.
  legacy="$(keel_legacy_store_root "$name")"
  if [ -d "$legacy" ]; then printf '%s' "$legacy"; return 0; fi
  printf '%s/%s' "$root" "$name"
}
