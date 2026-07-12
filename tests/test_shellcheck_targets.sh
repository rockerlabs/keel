#!/usr/bin/env bash
# tools/self/shellcheck-targets.sh — selects tracked *.sh files plus shebang-detected extensionless
# scripts, and nothing else. The canonical selection ci.yml's shellcheck job and
# tools/self/doctor.sh both call instead of each keeping its own copy.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

st="$REPO_ROOT/tools/self/shellcheck-targets.sh"

d="$(new_repo)"
printf '#!/usr/bin/env bash\necho hi\n' > "$d/script.sh"
printf '#!/usr/bin/env bash\necho hook\n' > "$d/a-hook"
chmod +x "$d/a-hook"
printf 'not a shell script\n' > "$d/notes.md"
( cd "$d" && git add -A && git commit -qm init )

run "$st" "$d"
check_status "runs clean -> exit 0" 0 "$STATUS"
check_contains "picks up a tracked *.sh file" "$OUT" "script.sh"
check_contains "picks up a shebang-detected extensionless file" "$OUT" "a-hook"
check_absent "skips a non-shell tracked file" "$OUT" "notes.md"

# default REPO_DIR is the current directory
run_in "$d" "$st"
check_status "defaults to cwd when REPO_DIR omitted -> exit 0" 0 "$STATUS"
check_contains "still finds script.sh from cwd" "$OUT" "script.sh"

summary
