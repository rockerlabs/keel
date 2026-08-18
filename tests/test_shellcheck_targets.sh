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

# The exit status must not depend on which path happens to sort last (dir #170). The fixture above
# does NOT exercise that: `git ls-files` yields a-hook, notes.md, script.sh — the last one takes the
# `*.sh` arm and returns 0, so the repo looks healthy either way. `zz-last.md` is what makes this the
# real regression case: it sorts after script.sh, is not a script, and its failed shebang grep used to
# become the whole script's exit status through pipefail. Its own `run` too — re-asserting the
# $STATUS captured further up would pin nothing.
printf 'not a script\n' > "$d/zz-last.md"
( cd "$d" && git add -A && git commit -qm last )
run "$st" "$d"
check_status "a repo whose last tracked file is not a script still exits 0" 0 "$STATUS"
check_contains "and the selection is unaffected" "$OUT" "script.sh"
check_absent "the non-script last file is still excluded" "$OUT" "zz-last.md"

# A non-ASCII path must be emitted usably, not C-quoted — a quoted path matches no case arm and the
# file would drop out of the selection silently.
printf '#!/usr/bin/env bash\necho x\n' > "$d/résumé.sh"
# A backslash is the harder half: `core.quotePath=false` would still let git quote this one, so only
# the NUL-delimited enumeration keeps it in the selection. A script silently missing from here is a
# script CI never lints.
printf '#!/usr/bin/env bash\necho y\n' > "$d/w\\eird.sh"
( cd "$d" && git add -A && git commit -qm nonascii )
run "$st" "$d"
check_status "a non-ASCII path does not break the run -> exit 0" 0 "$STATUS"
check_contains "a non-ASCII *.sh path is emitted unquoted" "$OUT" "résumé.sh"
check_absent "and is not C-quoted" "$OUT" '\303'
check_contains "a backslash-named script stays in the selection" "$OUT" "w\\eird.sh"
check_absent "and it too is not C-quoted" "$OUT" '\\e'

# default REPO_DIR is the current directory
run_in "$d" "$st"
check_status "defaults to cwd when REPO_DIR omitted -> exit 0" 0 "$STATUS"
check_contains "still finds script.sh from cwd" "$OUT" "script.sh"

summary
