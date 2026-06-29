#!/bin/sh
# Keel bootstrap — one-line install. Clones Keel into a temp dir, runs install.sh, cleans up.
#
#   curl -fsSL https://raw.githubusercontent.com/rockerlabs/keel/main/bootstrap.sh | sh
#
# Pass install.sh flags after `--`, e.g.  … | sh -s -- --no-hooks   (or --home DIR).
# Pin a ref with KEEL_REF (a tag/branch); point elsewhere with KEEL_REPO.
#
# POSIX sh (it's piped to `sh`); install.sh itself needs bash, checked below. Prefer reading this
# before piping a remote script to a shell — or use the clone path in the README if you'd rather.
set -eu

REPO="${KEEL_REPO:-https://github.com/rockerlabs/keel.git}"
REF="${KEEL_REF:-}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "keel: '$1' is required but not found" >&2; exit 1; }; }
need git
need bash   # install.sh and the git hooks have a bash shebang

tmp="$(mktemp -d "${TMPDIR:-/tmp}/keel.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT INT TERM

echo "keel: cloning $REPO${REF:+ @ $REF} …"
if [ -n "$REF" ]; then
  git clone -q --depth 1 --branch "$REF" "$REPO" "$tmp/keel"
else
  git clone -q --depth 1 "$REPO" "$tmp/keel"
fi

echo "keel: running install.sh …"
( cd "$tmp/keel" && ./install.sh "$@" )
