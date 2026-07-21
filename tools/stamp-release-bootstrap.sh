#!/usr/bin/env bash
# stamp-release-bootstrap — produce the release-asset copy of bootstrap.sh: same script, with
# KEEL_DEFAULT_REF stamped to a tag so that copy installs ITS OWN release by default instead of
# tracking main. The tracked bootstrap.sh always ships KEEL_DEFAULT_REF="" — only the stamped copy
# attached to a GitHub release carries a value.
#
# Usage:
#   tools/stamp-release-bootstrap.sh <tag> [OUT]
#
#   <tag>   the release tag to stamp in, e.g. v0.6.0 (must be non-empty, no quote/backslash/newline)
#   [OUT]   output path (default: stdout)
#
# Wire into a release:
#   tools/stamp-release-bootstrap.sh v0.6.0 /tmp/bootstrap.sh
#   gh release create v0.6.0 --notes-from-tag /tmp/bootstrap.sh
set -euo pipefail

tag="${1:?usage: stamp-release-bootstrap.sh <tag> [OUT]}"
out="${2:-}"

case "$tag" in
  # \ is also rejected: it's not a legal git ref character (git-check-ref-format), and awk -v applies
  # backslash-escape processing to its assignment value, so a literal \ in the tag would otherwise be
  # silently reinterpreted (e.g. \b as backspace) rather than copied through.
  *\"*|*$'\n'*|*\\*) echo "stamp-release-bootstrap: tag must not contain a quote, backslash, or newline: $tag" >&2; exit 1 ;;
esac

src="$(cd "$(dirname "$0")/.." && pwd)/bootstrap.sh"
[ -f "$src" ] || { echo "stamp-release-bootstrap: $src not found" >&2; exit 1; }

if ! grep -q '^KEEL_DEFAULT_REF=""$' "$src"; then
  echo "stamp-release-bootstrap: $src has no (or an already-stamped) KEEL_DEFAULT_REF=\"\" line — refusing to double-stamp or silently no-op" >&2
  exit 1
fi

# awk -v (not sed's regex substitution) so a tag containing sed-special characters (/, &, \ — all
# legal in a git ref) can't break the delimiter or get re-interpreted as a match-group backreference.
stamped="$(awk -v tag="$tag" '$0 == "KEEL_DEFAULT_REF=\"\"" { print "KEEL_DEFAULT_REF=\"" tag "\""; next } { print }' "$src")"

if [ -n "$out" ]; then
  printf '%s\n' "$stamped" > "$out"
  echo "stamp-release-bootstrap: wrote $out (KEEL_DEFAULT_REF=$tag)" >&2
else
  printf '%s\n' "$stamped"
fi
