#!/usr/bin/env bash
# tools/self/shellcheck-targets.sh — the tracked scripts shellcheck should lint: every *.sh plus any
# file whose shebang says it's a shell script (extensionless git hooks, etc.), so a new shell script can't slip
# past the gate. One canonical source for this selection — ci.yml's shellcheck job and
# tools/self/doctor.sh both call this instead of each keeping their own copy. That duplication is
# exactly the "two hand-maintained copies drift apart" shape self/doctor.sh's ship-skip-list check
# polices for install.sh/tools/doctor.sh; this file removes the risk here by construction instead of
# only detecting it after the fact.
#
# Usage: tools/self/shellcheck-targets.sh [REPO_DIR]   (default: current directory)
# Prints one repo-relative path per line.
set -euo pipefail
repo_dir="${1:-.}"
# `-z`, not plain `ls-files`: git C-quotes any path it cannot print literally, and such a string
# matches neither the `*.sh` arm (it ends in a quote) nor `head`'s idea of a filename, so the file was
# silently dropped from the selection — the one outcome this file exists to make impossible, and
# invisible because the output is a list nobody counts. `-c core.quotePath=false` covers only the
# non-ASCII half of that; a backslash or a double quote in a path is quoted regardless, so only the
# NUL-delimited form is a complete fix. (Both halves found by independent review of dir #170, which
# made this selection's completeness load-bearing for the first time.) The OUTPUT stays newline-
# delimited — ci.yml and tools/self/doctor.sh both consume it that way.
# `if … then … fi`, NOT `grep -q … && printf`: a non-match is the ORDINARY outcome here (most tracked
# files are not scripts), but as the last command of the loop body it becomes the `while`'s status,
# and through `pipefail` the pipeline's. This script's status was therefore a function of which path
# sorts last — 1 on any repo whose final tracked file is not a shell script, on a completely healthy
# tree. A trailing `exit 0` does NOT fix that: under `set -e` the failing pipeline exits the script
# before ever reaching it. Making each iteration succeed is what actually fixes it, and it keeps a
# real failure (an unreadable repo dir) visible.
git -C "$repo_dir" ls-files -z | while IFS= read -r -d '' f; do
  case "$f" in
    *.sh) printf '%s\n' "$f" ;;
    *) if head -1 -- "$repo_dir/$f" 2>/dev/null \
            | grep -qE '^#!.*[ /](ba|da|k)?sh([[:space:]]|$)'; then
         printf '%s\n' "$f"
       fi ;;
  esac
done
