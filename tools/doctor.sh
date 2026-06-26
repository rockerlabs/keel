#!/usr/bin/env bash
# doctor — structural self-audit of a project's knowledge-base baseline.
#
# The baseline is the durable convention; this script is its current instance. It reports drift, it does
# not fix it. A GAP fails the audit (exit 1); a WARN is advisory (exit stays at the structural baseline).
#
# Usage:
#   doctor.sh [PROJECT_DIR ...]     audit each dir (default: current dir)
#   doctor.sh --quiet ...           print only GAP/WARN lines
#
# Checks per project:
#   GAP   not a git repo
#   GAP   no project CLAUDE.md
#   GAP   .gitignore does not ignore the private AI context (.claude/ or CLAUDE.md) — unless public fork
#   WARN  secret-guard not wired (no global core.hooksPath and no local pre-commit)
#   WARN  CLAUDE.md startup footprint over budget (KEEL_STARTUP_WARN_TOKENS, default 10000)
set -euo pipefail

QUIET=0
DIRS=()
for a in "$@"; do
  case "$a" in
    --quiet) QUIET=1 ;;
    *) DIRS+=("$a") ;;
  esac
done
[ "${#DIRS[@]}" -gt 0 ] || DIRS=(".")

WARN_TOKENS="${KEEL_STARTUP_WARN_TOKENS:-10000}"
exit_code=0

say()  { [ "$QUIET" = 1 ] || echo "$@"; }
gap()  { echo "  GAP  $1"; exit_code=1; }
warn() { echo "  WARN $1"; }

global_hooks="$(git config --global core.hooksPath 2>/dev/null || true)"

for d in "${DIRS[@]}"; do
  name="$(basename "$(cd "$d" 2>/dev/null && pwd || echo "$d")")"
  say "● $name ($d)"

  if [ ! -d "$d" ]; then gap "directory not found"; continue; fi

  if [ ! -d "$d/.git" ]; then
    gap "not a git repo (git init + a feature-branch flow — see FRAMEWORK.md)"
  fi

  if [ ! -f "$d/CLAUDE.md" ]; then
    gap "no project CLAUDE.md (copy templates/project-CLAUDE.md, or run init-project)"
  else
    chars="$(wc -c < "$d/CLAUDE.md" | tr -d ' ')"
    est=$(( chars / 4 ))
    if [ "$est" -gt "$WARN_TOKENS" ]; then
      warn "CLAUDE.md startup footprint ~${est} tokens > budget ${WARN_TOKENS} — move detail to the on-demand tier (P2/P3)"
    fi
  fi

  gi="$d/.gitignore"
  if [ -f "$gi" ] && grep -qE '(^|/)(\.claude/?|CLAUDE\.md)' "$gi"; then
    :  # private AI context ignored — good
  elif [ -f "$d/CLAUDE.md" ] && git -C "$d" ls-files --error-unmatch CLAUDE.md >/dev/null 2>&1; then
    say "       (CLAUDE.md is tracked — treating as a deliberate public fork; ensure no secrets/PII)"
  else
    gap ".gitignore does not ignore the private AI context (.claude/ or CLAUDE.md)"
  fi

  if [ -n "$global_hooks" ]; then
    :  # machine-global secret-guard assumed
  elif [ -x "$d/.git/hooks/pre-commit" ]; then
    :  # vendored
  else
    warn "secret-guard not wired (install-secret-guard.sh --global, or vendor into this repo)"
  fi
done

[ "$exit_code" = 0 ] && say "doctor: structural baseline OK"
exit "$exit_code"
