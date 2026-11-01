#!/usr/bin/env bash
# The "not a symlink or a directory" carve-out is the advice phrase that tells an adopter when --force is
# safe. It is hand-typed at four sites across three files and two shell dialects: install.sh (twice),
# tools/doctor.sh (W-CLI-UNWIRED) and the extensionless keel script. Each site's own pin checks it
# against a literal, so four passing pins say nothing about whether the four still agree. This file
# asserts the agreement itself: every site carries the same clause, and there are exactly four sites.
# dir #374 (the cheap end: equality between sites, no shared-constant mechanism).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

# Every tracked file carrying the clause, not a hardcoded list: a new site anywhere in the tree is counted.
# This file itself is excluded (it spells the pattern out). Clause: from "a real file" through "backed up first".
all="$(git -C "$REPO_ROOT" grep -h -o -E 'a real file, not a symlink or a directory, [^()]*backed up first' -- . ':!tests/test_advice_carveout.sh')"

# Four sites: install.sh x2, tools/doctor.sh x1, keel x1. A site dropped, re-typed, or added elsewhere
# moves this count, which is the point — update it deliberately when a site is added.
check_eq "dir #374: the carve-out clause appears at all four advice sites" "4" "$(printf '%s\n' "$all" | grep -c .)"

# All four must be the same string: one distinct clause across every site.
check_eq "dir #374: the four carve-out clauses are identical to each other" "1" "$(printf '%s\n' "$all" | sort -u | grep -c .)"

summary
