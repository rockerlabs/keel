#!/usr/bin/env bash
# register-project — add project root(s) to the INSTANCE.md Projects registry, one table row each,
# so `doctor --registry` and cross-project sweeps can find them. The MECHANICAL half of the registry
# (name = dir basename, Path = absolute path); you still write each project's own CLAUDE.md and can
# refine the Tag afterward. Idempotent: a path already listed is skipped.
set -euo pipefail

# safe-write (dir #679) — REQUIRED: the row lands as an EDIT through it, so a dotfiles-managed
# INSTANCE.md stays a link and keeps its mode, and one linked into this checkout's templates/ never
# gets a private project path written into a tracked file. Refuse outright when it is missing.
here="$(cd "$(dirname "$0")" && pwd)"
if [ -s "$here/lib/safe-write.sh" ] && bash -n "$here/lib/safe-write.sh" 2>/dev/null; then
  # shellcheck source=tools/lib/safe-write.sh
  . "$here/lib/safe-write.sh"
else
  echo "register-project: tools/lib/safe-write.sh (the safe-write lib) is missing or corrupted — re-clone or re-download Keel and re-run" >&2
  exit 1
fi
KEEL_SAFE_WRITE_CHECKOUT="$(cd "$here/.." && pwd)"

# Where the registry lives: KEEL_INSTANCE wins, else <KEEL_HOME>/INSTANCE.md, else ~/.claude/INSTANCE.md.
INSTANCE="${KEEL_INSTANCE:-${KEEL_HOME:-${HOME:?set HOME, or pass KEEL_INSTANCE}/.claude}/INSTANCE.md}"

usage() {
  cat <<'EOF'
register-project — add project root(s) to the INSTANCE.md Projects registry.

Usage:
  register-project.sh <project-dir> [<project-dir> ...]
  register-project.sh -h | --help

Writes one row per path (name = dir basename, Path = absolute path) into the Projects table of
$KEEL_HOME/INSTANCE.md (default ~/.claude/INSTANCE.md; override the file with KEEL_INSTANCE).
Idempotent — a path already in the table is skipped. The Tag is left blank for you to fill.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "")        usage >&2; exit 2 ;;
  -*)        echo "register-project: unknown option '$1' (try --help)" >&2; exit 2 ;;
esac

[ -f "$INSTANCE" ] || { echo "register-project: $INSTANCE not found — run install.sh first (or set KEEL_HOME/KEEL_INSTANCE)" >&2; exit 2; }
grep -qE '^\| *Project *\| *Path *\|' "$INSTANCE" || { echo "register-project: no Projects table in $INSTANCE" >&2; exit 2; }

added=0
for dir in "$@"; do
  [ -d "$dir" ] || { echo "  !    not a directory, skipped: $dir" >&2; continue; }
  abs="$(cd "$dir" && pwd)"
  name="$(basename "$abs")"
  if grep -qF "| $abs |" "$INSTANCE"; then
    echo "  =    already registered: $abs"
    continue
  fi
  row="| $name | $abs | $abs/CLAUDE.md | - |"
  # Insert the row at the end of the FIRST Projects table (the run of '|' lines after its header). The
  # lib runs the awk itself (its command form) and renames the result only when awk succeeded, so a
  # refusal or a failed awk (one line either way) changes nothing: exit 1.
  keel_write_through "$INSTANCE" awk -v row="$row" '
    /^\| *Project *\| *Path *\|/ && !seen { seen=1; intab=1 }
    { lines[NR]=$0 }
    intab && /^\|/ { last=NR }
    intab && seen && !/^\|/ { intab=0 }
    END { for (i=1;i<=NR;i++) { print lines[i]; if (i==last) print row } }
  ' "$INSTANCE" || exit 1
  echo "  +    registered: $name -> $abs"
  added=$((added + 1))
done

echo "register-project: $added added to $INSTANCE"
