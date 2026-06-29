#!/usr/bin/env bash
# init-project — scaffolds a born-compliant project; a second run never clobbers existing files.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

init="$REPO_ROOT/tools/init-project.sh"

# scaffold a fresh project
d="$SANDBOX/fresh-proj"
run "$init" "$d"
check_status "init fresh → exit 0" 0 "$STATUS"
check_dir  "creates a git repo" "$d/.git"
check_file "creates CLAUDE.md" "$d/CLAUDE.md"
check_file "creates .gitignore" "$d/.gitignore"

claude="$(cat "$d/CLAUDE.md")"
check_contains "CLAUDE.md is named for the project" "$claude" "fresh-proj"
check_absent  "placeholder is substituted away" "$claude" "<Project name>"

gi="$(cat "$d/.gitignore")"
check_contains ".gitignore ignores CLAUDE.md" "$gi" "CLAUDE.md"
check_contains ".gitignore ignores .claude/" "$gi" ".claude/"

# idempotency: a second run preserves an edited CLAUDE.md and adds no duplicate .gitignore lines
printf '\nMY-EDIT\n' >> "$d/CLAUDE.md"
before_lines="$(wc -l < "$d/.gitignore")"
run "$init" "$d"
check_status "init re-run → exit 0" 0 "$STATUS"
check_contains "re-run preserves the user edit" "$(cat "$d/CLAUDE.md")" "MY-EDIT"
check_contains "re-run reports CLAUDE.md untouched" "$OUT" "already exists"
after_lines="$(wc -l < "$d/.gitignore")"
check_status "re-run adds no duplicate .gitignore lines" "$before_lines" "$after_lines"

# --help prints usage and exits 0 (a newcomer's reflex must not look like a crash); an unknown flag
# is a usage error, not silently treated as a directory to scaffold.
run "$init" --help
check_status "--help → exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$init" --bogus
check_status "unknown flag → exit 2" 2 "$STATUS"

# auto-registers the scaffolded project in INSTANCE.md (when one exists) — no second command needed
inst="$SANDBOX/INSTANCE.md"; cp "$REPO_ROOT/templates/INSTANCE.md" "$inst"
ap="$SANDBOX/auto-reg-proj"
run env KEEL_INSTANCE="$inst" "$init" "$ap"
check_status "init with a registry → exit 0" 0 "$STATUS"
check_contains "row added to INSTANCE.md" "$(cat "$inst")" "| $ap |"
check_contains "reports the auto-registration" "$OUT" "INSTANCE.md Projects registry"

# --no-register opts out (and a non-existent registry is simply skipped, not fatal)
inst2="$SANDBOX/INSTANCE2.md"; cp "$REPO_ROOT/templates/INSTANCE.md" "$inst2"
np="$SANDBOX/no-reg-proj"
run env KEEL_INSTANCE="$inst2" "$init" --no-register "$np"
check_status "--no-register → exit 0" 0 "$STATUS"
check_absent "--no-register adds no row" "$(cat "$inst2")" "| $np |"

summary
