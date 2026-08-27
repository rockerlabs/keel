#!/usr/bin/env bash
# init-project — scaffold a new project to the Keel baseline (born-compliant).
#
# Usage: init-project.sh [PROJECT_DIR]   (default: current dir)
#
# Idempotent: it never overwrites an existing CLAUDE.md, AGENTS.md, or .gitignore — it only fills gaps
# and reports.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
tpl_project="$root/templates/project-CLAUDE.md"

REGISTER=1
IMPACT=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
init-project — scaffold a new project to the Keel baseline (born-compliant).

Usage:
  init-project.sh [PROJECT_DIR]   scaffold PROJECT_DIR (default: current dir)
  init-project.sh --no-register   skip adding it to the INSTANCE.md Projects registry
  init-project.sh --no-impact     skip opting the project into impact tracking
  init-project.sh -h | --help

Idempotent: fills gaps (git, a .gitignore that hides private context, a project
CLAUDE.md, an AGENTS.md vendor sibling symlinked to it for Codex/Cursor), opts the
project into impact tracking (an external store entry, dir #251 — nothing is written
into the project's own tree), auto-registers the project in your INSTANCE.md, and
reports — it never overwrites a file you have.
EOF
      exit 0 ;;
    --no-register) REGISTER=0 ;;
    --no-impact)   IMPACT=0 ;;
    -*) echo "init-project: unknown option '$1' (try --help)" >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done

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
  grep -qxF "$pat" .gitignore && return 0
  # dir #85 (code audit, finding 5 — found in keel-impact.sh's own appender, fixed in BOTH): an
  # adopter's pre-existing .gitignore whose last line lacks a trailing newline would otherwise get our
  # rule GLUED onto it, silently destroying their rule and ours in one write. `tail -c1` returning
  # anything means the file does not end in a newline (command substitution strips a trailing one).
  # This helper runs against a brownfield .gitignore six times per init, so it is the likelier victim.
  if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore 2>/dev/null)" ]; then printf '\n' >> .gitignore; fi
  echo "$pat" >> .gitignore
  echo "  + .gitignore += $pat"
}
ensure_ignore "CLAUDE.md"
ensure_ignore "AGENTS.md"
ensure_ignore ".claude/"
ensure_ignore ".DS_Store"
ensure_ignore ".idea/"
# doctor's map-drift check (dir #39 T1): an accepted stale-path mention lands here, script-only read —
# gitignore it up front so a later `doctor.sh` WARN never tempts a `git add` of a per-checkout file.
ensure_ignore "/.keel/map-drift-baseline"

# 2b. Impact tracking — opt this project into an external store entry (dir #251) so guardrail hooks
# get recorded with no env needed. Delegated to keel-impact.sh enable: its resolver always targets the
# MAIN checkout's top, so scaffolding a project FROM a linked worktree still resolves the same store
# entry every other worktree does. Nothing is written into the project's own tree. Zero token cost;
# --no-impact to skip.
if [ "$IMPACT" = 1 ]; then
  "$here/keel-impact.sh" enable . | sed 's/^/  /'
fi

# 3. project CLAUDE.md from template
if [ -f CLAUDE.md ]; then
  echo "  = CLAUDE.md already exists (left untouched)"
elif [ -f "$tpl_project" ]; then
  # dir #85 (code audit, finding 20): NOT `sed "s/<Project name>/$name/"`. $name is a directory
  # basename, so it can legally contain sed's replacement metacharacters — `&` splices the whole match
  # back in ("AT&T-tools" → "AT<Project name>T-tools"), `\` starts an escape, `/` closes the s///
  # command outright. Same class the project already solved once in stamp-release-bootstrap.sh. Here
  # even `awk -v` is not enough: -v values go through awk's own escape processing (a `\t` in the name
  # would become a literal tab), which is exactly why install.sh's neighbouring rewriters use ENVIRON.
  # index/substr is a LITERAL scan — no regex, no replacement metacharacters — and terminates because
  # $rest strictly shrinks each pass even if the name itself contains the placeholder.
  KEEL_PROJECT_NAME="$name" awk '
    BEGIN { ph = "<Project name>"; name = ENVIRON["KEEL_PROJECT_NAME"] }
    { out = ""; rest = $0
      while ((n = index(rest, ph)) > 0) {
        out = out substr(rest, 1, n - 1) name
        rest = substr(rest, n + length(ph))
      }
      print out rest }
  ' "$tpl_project" > CLAUDE.md
  echo "  + CLAUDE.md created from template"
else
  echo "  ! template not found: $tpl_project" >&2
fi

# 3b. AGENTS.md — vendor sibling of CLAUDE.md (dir #75): a symlink, so it can never drift from it.
# Never-clobber, same idiom as the CLAUDE.md branch above. Only link if CLAUDE.md actually exists —
# step 3 above can fail to create it (missing template), and a symlink to nothing would print a
# success message for a dangling target.
if [ -e AGENTS.md ] || [ -L AGENTS.md ]; then
  echo "  = AGENTS.md already exists (left untouched)"
elif [ -f CLAUDE.md ]; then
  ln -s CLAUDE.md AGENTS.md
  echo "  + AGENTS.md created (symlink to CLAUDE.md)"
else
  echo "  ! AGENTS.md skipped: no CLAUDE.md to link to" >&2
fi

# Auto-register in the INSTANCE.md Projects index (best-effort; --no-register to skip). Capture
# register-project.sh's stderr rather than discarding it (dir #212): a present-but-unsuitable
# INSTANCE.md (no Projects table) exits 2 with a reason on stderr, and silencing it left the
# follow-up below indistinguishable from the "no INSTANCE.md yet" / "--no-register" cases.
registered=0
register_err=""
instance="${KEEL_INSTANCE:-${KEEL_HOME:-${HOME:-}/.claude}/INSTANCE.md}"
if [ "$REGISTER" = 1 ] && [ -f "$instance" ]; then
  if register_err="$("$here/register-project.sh" "$(pwd)" 2>&1 >/dev/null)"; then
    registered=1
  fi
fi

echo ""
echo "Next:"
echo "  - fill in CLAUDE.md (overview, stack, conventions, roadmap) — AGENTS.md mirrors it automatically"
echo "  - wire secret-guard:  install-secret-guard.sh --global   (or vendor into this repo)"
if [ "$registered" = 1 ]; then
  echo "  - added to your INSTANCE.md Projects registry — refine its Tag there"
elif [ -n "$register_err" ]; then
  echo "  - add to your INSTANCE.md registry:  register-project.sh \"$(pwd)\"  (previous attempt failed: $register_err)"
else
  echo "  - add to your INSTANCE.md registry:  register-project.sh \"$(pwd)\""
fi
echo "  - verify:  doctor.sh ."
