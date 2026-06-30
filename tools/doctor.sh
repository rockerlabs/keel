#!/usr/bin/env bash
# doctor — structural self-audit of a project's knowledge-base baseline.
#
# The baseline is the durable convention; this script is its current instance. It reports drift, it does
# not fix it. A GAP fails the audit (exit 1); a WARN is advisory (exit stays at the structural baseline).
#
# Usage:
#   doctor.sh [PROJECT_DIR ...]     audit each dir (default: current dir)
#   doctor.sh --registry FILE       audit every project in an INSTANCE.md Projects table (the Path column)
#   doctor.sh --quiet ...           print only GAP/WARN lines
#
# Checks per project:
#   GAP   not a git repo
#   GAP   no project CLAUDE.md
#   GAP   .gitignore does not ignore the private AI context (.claude/ or CLAUDE.md) — unless public fork
#   WARN  secret-guard not wired (no global core.hooksPath and no local pre-commit)
#   WARN  a local core.hooksPath override carries no guard — it silently bypasses the machine-global one
#   WARN  CLAUDE.md startup footprint over budget (KEEL_STARTUP_WARN_TOKENS, default 10000)
set -euo pipefail

QUIET=0
REGISTRY=""
DIRS=()
usage() {
  cat <<'EOF'
doctor — audit a project's Keel knowledge-base baseline (a GAP fails, a WARN advises).

Usage:
  doctor.sh [DIR ...]          audit DIR(s) for the baseline (default: .)
  doctor.sh --registry FILE    audit every project in an INSTANCE.md Projects table
  doctor.sh --quiet            print only GAP/WARN lines
  doctor.sh -h | --help

Example:  doctor.sh ~/code/my-project
EOF
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1 ;;
    --registry) shift; REGISTRY="${1:?--registry needs a FILE}" ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "doctor: unknown option '$1' (try --help)" >&2; exit 2 ;;
    *) DIRS+=("$1") ;;
  esac
  shift
done

# Pull project paths from the Path column of an INSTANCE.md Projects table.
# Skips the header, the separator, and unfilled placeholder rows; expands a leading ~.
if [ -n "$REGISTRY" ]; then
  [ -f "$REGISTRY" ] || { echo "doctor: registry not found: $REGISTRY" >&2; exit 2; }
  while IFS='|' read -r _lead _col1 col_path _rest; do
    path="$(printf '%s' "$col_path" | tr -d '`' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$path" in
      ""|Path|*"<"*) continue ;;        # header / blank / placeholder
    esac
    path="${path/#\~/$HOME}"
    DIRS+=("$path")
  done < <(awk 'BEGIN{f=0} /^[[:space:]]*(```|~~~)/{f=!f;next} !f' "$REGISTRY" \
            | grep -E '^[[:space:]]*\|' | grep -vE '^[[:space:]]*\|[-:| ]+\|?[[:space:]]*$')
fi

[ "${#DIRS[@]}" -gt 0 ] || DIRS=(".")

WARN_TOKENS="${KEEL_STARTUP_WARN_TOKENS:-10000}"
case "$WARN_TOKENS" in ''|*[!0-9]*) WARN_TOKENS=10000 ;; esac   # non-numeric → default (no `[: integer expected`)
exit_code=0

say()  { [ "$QUIET" = 1 ] || echo "$@"; }
gap()  { echo "  GAP  $1"; exit_code=1; }
warn() { echo "  WARN $1"; }

global_hooks="$(git config --global core.hooksPath 2>/dev/null || true)"

for d in "${DIRS[@]}"; do
  name="$(basename "$(cd "$d" 2>/dev/null && pwd || echo "$d")")"
  say "● $name ($d)"

  if [ ! -d "$d" ]; then gap "directory not found"; continue; fi

  if ! git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    gap "not a git repo (git init + a feature-branch flow — see FRAMEWORK.md)"
  fi

  if [ ! -f "$d/CLAUDE.md" ]; then
    if git -C "$d" check-ignore -q CLAUDE.md 2>/dev/null; then
      # CLAUDE.md is gitignored (a private-fork or a "mechanism" repo like Keel itself), so a fresh
      # clone legitimately has none — advise, don't fail.
      warn "no project CLAUDE.md in this checkout — it's gitignored (private/mechanism repo); create it locally"
    else
      gap "no project CLAUDE.md (copy templates/project-CLAUDE.md, or run init-project)"
    fi
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

  # A machine-global core.hooksPath covers this repo — UNLESS the repo sets its own LOCAL core.hooksPath,
  # which silently overrides the global one (git runs the local path, so the global guard never fires here).
  # So when a local override exists, verify it actually carries the guard before trusting it.
  local_hooks="$(git -C "$d" config --local core.hooksPath 2>/dev/null || true)"
  if [ -n "$local_hooks" ]; then
    case "$local_hooks" in /*) lhd="$local_hooks" ;; *) lhd="$d/$local_hooks" ;; esac
    if [ -f "$lhd/secret-scan.sh" ] || [ -x "$lhd/pre-commit" ] || [ -x "$lhd/pre-push" ]; then
      :  # the local override carries the guard — fine
    else
      warn "local core.hooksPath ('$local_hooks') overrides the machine-global secret-guard but carries no hook — the global guard is silently bypassed for this repo (vendor the guard into the override dir, or unset it)"
    fi
  elif [ -n "$global_hooks" ]; then
    :  # machine-global secret-guard covers it (no local override)
  elif ( cd "$d" 2>/dev/null && p="$(git rev-parse --git-path hooks/pre-commit 2>/dev/null)" && [ -x "$p" ] ); then
    :  # vendored (resolve the real hooks dir — a worktree/submodule isn't .git/hooks)
  else
    warn "secret-guard not wired (install-secret-guard.sh --global, or vendor into this repo)"
  fi

  # Publication-bound projects (those with a .public-audit config) shouldn't commit with a real
  # personal/corporate email — it ends up in public history. Nudge toward a noreply address.
  if [ -f "$d/.public-audit" ]; then
    email="$(git -C "$d" config user.email 2>/dev/null || true)"
    if [ -n "$email" ] && ! printf '%s' "$email" | grep -qE 'noreply|@example\.|\.invalid'; then
      warn "git commit email '$email' is not a noreply address — it lands in public history (run public-audit.sh)"
    fi
  fi

  # Dependency pinning (FRAMEWORK "Dependency versioning") — WARN on a floating version of a pinnable dep:
  # a Docker/compose image :latest tag, or a major-only GitHub Action @vN tag. A *-latest CI runner label
  # is NOT flagged — a managed alias, not a pinnable artifact.
  # find+grep, not `grep -r --include=…`: busybox grep (Alpine) has no --include, so the option errored
  # and this check silently never fired there. find's -name globs are portable across GNU/BSD/busybox.
  dep="$(find "$d" -type f \( -name 'Dockerfile*' -o -name '*compose*.yml' -o -name '*compose*.yaml' \) \
           -exec grep -InE '^[^#]*(FROM|image:)[[:space:]]+[^[:space:]]+:latest' {} + 2>/dev/null | head -1 || true)"
  if [ -z "$dep" ] && [ -d "$d/.github/workflows" ]; then
    dep="$(grep -rInE 'uses:[[:space:]]+[^[:space:]]+@v[0-9]+([[:space:]]|$)' "$d/.github/workflows" 2>/dev/null | head -1 || true)"
  fi
  if [ -n "$dep" ]; then
    warn "floating dependency version — pin it (no image :latest / Action @vN; FRAMEWORK 'Dependency versioning')"
  fi
done

[ "$exit_code" = 0 ] && say "doctor: structural baseline OK"
exit "$exit_code"
