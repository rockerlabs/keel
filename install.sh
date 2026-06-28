#!/usr/bin/env bash
# install — one-command bootstrap for Keel into your harness home.
#
# Copies the durable core into the harness home WITHOUT clobbering any file you already have,
# wires the secret-guard git hook machine-global (never over an existing hooksPath), seeds a
# private INSTANCE.md, and verifies the result. Re-running only fills gaps and re-verifies.
#
# Usage:
#   install.sh                 bootstrap into ${KEEL_HOME:-$HOME/.claude}
#   install.sh --home DIR      bootstrap into DIR (for a non-Claude-Code harness)
#   install.sh --no-hooks      skip the global secret-guard step (wire it yourself)
#   install.sh -h | --help
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"          # repo root (this script lives at the top level)

usage() {
  cat <<'EOF'
install — one-command bootstrap for Keel into your harness home.

Copies the durable core into the harness home WITHOUT clobbering any file you already
have, wires the secret-guard git hook machine-global (never over an existing hooksPath),
seeds a private INSTANCE.md, and verifies the result. Re-running only fills gaps.

Usage:
  install.sh                 bootstrap into ${KEEL_HOME:-$HOME/.claude}
  install.sh --home DIR      bootstrap into DIR (for a non-Claude-Code harness)
  install.sh --no-hooks      skip the global secret-guard step (wire it yourself)
  install.sh -h | --help
EOF
}

HOME_DIR="${KEEL_HOME:-}"          # --home overrides; the $HOME default is resolved AFTER parsing
DO_HOOKS=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --home) shift; HOME_DIR="${1:?--home needs a DIR}" ;;
    --no-hooks) DO_HOOKS=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# Default to $HOME/.claude only if neither KEEL_HOME nor --home was given — so those callers never
# need $HOME (and `set -u` won't abort when it's unset). Require $HOME only when we actually fall back.
: "${HOME_DIR:=${HOME:?install: set HOME, or pass --home DIR}/.claude}"

echo "Keel → $HOME_DIR"
mkdir -p "$HOME_DIR"

# 1. Durable core — copy each file only if the destination is absent (never clobber).
copy_gap() {
  local src="$1" dest="$2"
  if [ -f "$dest" ]; then
    echo "  =    $(basename "$dest") exists (left untouched)"
  elif [ -f "$src" ]; then
    cp "$src" "$dest.keeltmp.$$" && mv -f "$dest.keeltmp.$$" "$dest"   # atomic: no half-written dest
    echo "  +    $(basename "$dest")"
  else
    echo "  !    source missing: $src" >&2
    return 1
  fi
}

copy_gap "$root/templates/CLAUDE.md"    "$HOME_DIR/CLAUDE.md"
copy_gap "$root/templates/INSTANCE.md"  "$HOME_DIR/INSTANCE.md"
copy_gap "$root/templates/LEARNINGS.md" "$HOME_DIR/LEARNINGS.md"
copy_gap "$root/FRAMEWORK.md"           "$HOME_DIR/FRAMEWORK.md"
copy_gap "$root/PRINCIPLES.md"          "$HOME_DIR/PRINCIPLES.md"

# 2. Secret-guard — machine-global, but never clobber an existing global hooksPath.
# keel_hooks must match the path install-secret-guard.sh --global writes to (re-used by Verify below).
# Resolved only when hooks are in play, so --no-hooks never needs $HOME; a clear message (not a bare
# "unbound variable") if $HOME is unset while wiring hooks.
keel_hooks=""
if [ "$DO_HOOKS" = 1 ]; then
  keel_hooks="${HOME:?install: wiring hooks needs HOME set (or pass --no-hooks)}/.config/git/keel-hooks"
  existing="$(git config --global core.hooksPath 2>/dev/null || true)"
  if [ -z "$existing" ] || [ "$existing" = "$keel_hooks" ]; then
    # Non-fatal: a wiring failure must still fall through to the verify summary below
    # (which reports the hook state), not abort the whole bootstrap under `set -e`.
    if ! "$root/tools/install-secret-guard.sh" --global | sed 's/^/  /'; then
      echo "  !    secret-guard wiring failed — the verify step below will flag it" >&2
    fi
  else
    echo "  !    global core.hooksPath already set to '$existing' — not clobbering it."
    echo "       To protect a repo, vendor instead: tools/install-secret-guard.sh <repo>"
  fi
else
  echo "  =    secret-guard skipped (--no-hooks)"
fi

# 3. Verify the result — fail loudly if a core file or the hook wiring is missing.
echo "Verify:"
missing=0
for f in CLAUDE.md INSTANCE.md LEARNINGS.md FRAMEWORK.md PRINCIPLES.md; do
  if [ -f "$HOME_DIR/$f" ]; then
    echo "  OK   $f"
  else
    echo "  MISS $f" >&2; missing=1
  fi
done

if [ "$DO_HOOKS" = 1 ]; then
  hp="$(git config --global core.hooksPath 2>/dev/null || true)"
  if [ "$hp" = "$keel_hooks" ] && [ -x "$hp/pre-commit" ] && grep -q 'Keel secret-guard' "$hp/pre-commit" 2>/dev/null; then
    echo "  OK   secret-guard ($hp)"
  elif [ -n "$hp" ]; then
    # A foreign global hooksPath is set — we did NOT wire Keel's guard (and didn't clobber theirs).
    echo "  WARN secret-guard NOT wired — a foreign global core.hooksPath ('$hp') is set."
    echo "       Vendor per-repo instead: tools/install-secret-guard.sh <repo>"
  else
    echo "  WARN secret-guard not wired — run tools/install-secret-guard.sh --global"
  fi
fi

[ "$missing" = 0 ] || { echo "install: verification FAILED — core file(s) missing" >&2; exit 1; }

cat <<EOF

Done. Next:
  - edit  $HOME_DIR/CLAUDE.md  (replace the <placeholders>); keep  $HOME_DIR/INSTANCE.md  private
  - scaffold or audit a project:  tools/init-project.sh <dir>  ;  tools/doctor.sh <dir>
EOF
