#!/usr/bin/env bash
# init-project — scaffold a new project to the Keel baseline (born-compliant).
#
# Usage: init-project.sh [PROJECT_DIR]   (default: current dir)
#
# Idempotent: it never overwrites an existing CLAUDE.md or .gitignore — it only fills gaps and reports.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
tpl_project="$root/templates/project-CLAUDE.md"

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
init-project — scaffold a new project to the Keel baseline (born-compliant).

Usage:
  init-project.sh [PROJECT_DIR]   scaffold PROJECT_DIR (default: current dir)
  init-project.sh -h | --help

Idempotent: fills gaps (git, a .gitignore that hides private context, a project
CLAUDE.md) and reports — it never overwrites a file you already have.
EOF
    exit 0 ;;
  -*) echo "init-project: unknown option '$1' (try --help)" >&2; exit 2 ;;
esac

dir="${1:-.}"
mkdir -p "$dir"
cd "$dir"
name="$(basename "$(pwd)")"
echo "init-project: scaffolding $(pwd)"   # make the target explicit — the cwd default is never silent

# 1. git
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git init -q
  echo "  + git initialized"
else
  echo "  = git already initialized"
fi

# 2. .gitignore — ensure the private AI context + common noise are ignored
ensure_ignore() {
  local pat="$1"
  touch .gitignore
  grep -qxF "$pat" .gitignore || { echo "$pat" >> .gitignore; echo "  + .gitignore += $pat"; }
}
ensure_ignore "CLAUDE.md"
ensure_ignore ".claude/"
ensure_ignore ".DS_Store"
ensure_ignore ".idea/"

# 3. project CLAUDE.md from template
if [ -f CLAUDE.md ]; then
  echo "  = CLAUDE.md already exists (left untouched)"
elif [ -f "$tpl_project" ]; then
  sed "s/<Project name>/$name/" "$tpl_project" > CLAUDE.md
  echo "  + CLAUDE.md created from template"
else
  echo "  ! template not found: $tpl_project" >&2
fi

echo ""
echo "Next:"
echo "  - fill in CLAUDE.md (overview, stack, conventions, roadmap)"
echo "  - wire secret-guard:  install-secret-guard.sh --global   (or vendor into this repo)"
echo "  - add the project to your INSTANCE.md Projects registry"
echo "  - verify:  doctor.sh ."
