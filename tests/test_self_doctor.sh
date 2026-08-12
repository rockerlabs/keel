#!/usr/bin/env bash
# self/doctor.sh — its native checks (ship-skip sync, dead refs, tool wiring, CHANGELOG staleness)
# against a synthetic sandbox repo, plus --help/bad-args and a smoke test on the real checkout.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

sd="$REPO_ROOT/tools/self/doctor.sh"

# Fake paths this file's own source must never hold intact — self/doctor.sh scans tests/*.sh too
# (its check 3 relies on that), so a bare literal here would flag itself when THIS repo (not the
# sandbox) gets self-audited. Built via lib.sh's key() (the same join-to-avoid-a-whole-literal
# idiom it already provides for secret fixtures), not ad-hoc concatenation.
fake_widget="$(key tools/widget .sh)"
fake_orphan="$(key tools/orphan .sh)"
fake_nested="$(key commands/keel-go .md)"
fake_dead="$(key commands/does -not-exist.md)"
fake_ci_tool="$(key tools/ci-only .sh)"

# --- --help / bad args ---------------------------------------------------------------------------
run "$sd" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$sd" --bogus
check_status "unknown flag -> exit 2" 2 "$STATUS"
run "$sd" /no/such/dir
check_status "missing REPO_DIR -> exit 2" 2 "$STATUS"

# --- smoke test: the real keel checkout is clean --------------------------------------------------
run "$sd" --quiet
check_status "the real keel checkout is clean (no GAP)" 0 "$STATUS"

# --- synthetic sandbox: a minimal, fully-passing mini-repo; each test mutates a fresh copy --------
# Fixture scripts hold only what the checks under test actually need: doctor.sh's ship-skip check
# just greps for "NAME.md) continue" — the `for` wrapper is kept because a bare `continue` outside a
# loop is a shellcheck error (SC2105), and these are *.sh files self/doctor.sh's own shellcheck pass
# will lint when auditing the sandbox. A fixed old commit date on the baseline keeps the
# CHANGELOG-staleness check (timestamp-ordered) deterministic — a later commit in the same test
# always lands after it, never in the same second.
# doctor.sh's orchestrated checks (line ~214) unconditionally `bash`-exec these two files, so any
# sandbox repo doctor.sh runs against needs them present or it GAPs on missing files.
stub_orchestrated_tests() {
  local d="$1" f
  for f in test_doc_figures.sh test_core_wrapper_sync.sh; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/tests/$f"
  done
}

mk_clean_repo() {
  local d; d="$(new_repo)"
  mkdir -p "$d/commands" "$d/tools" "$d/tests"

  printf '#!/usr/bin/env bash\nfor x in "$@"; do\n  case "$x" in\n    polish.md) continue ;;\n  esac\ndone\n' \
    > "$d/install.sh"
  printf '#!/usr/bin/env bash\nfor x in "$@"; do case "$x" in polish.md) continue ;; esac; done\n' \
    > "$d/tools/doctor.sh"

  printf '# go\n' > "$d/commands/go.md"
  printf '# polish\n' > "$d/commands/polish.md"

  printf '#!/usr/bin/env bash\necho widget\n' > "$d/$fake_widget"

  # the only mention of tools/doctor.sh and $fake_widget — makes both "wired" (referenced + tested)
  printf '#!/usr/bin/env bash\n# smoke-references tools/doctor.sh and %s\n' "$fake_widget" \
    > "$d/tests/test_tools.sh"

  stub_orchestrated_tests "$d"

  printf '# Changelog\n\n## Unreleased\n- init\n' > "$d/CHANGELOG.md"
  ( cd "$d" && git add -A \
      && GIT_AUTHOR_DATE="2020-01-01T00:00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00" \
         git commit -q -m init )
  printf '%s' "$d"
}

d="$(mk_clean_repo)"
run "$sd" "$d" --quiet
check_status "clean sandbox -> exit 0" 0 "$STATUS"
check_absent "clean sandbox has no GAP/WARN output" "$OUT" "GAP"

# --- 1. install.sh <-> doctor.sh --install ship-skip list mismatch -> GAP -------------------------
d="$(mk_clean_repo)"
printf '#!/usr/bin/env bash\nfor x in "$@"; do case "$x" in other.md) continue ;; esac; done\n' \
  > "$d/tools/doctor.sh"
( cd "$d" && git add -A && git commit -qm mismatch )
run "$sd" "$d" --quiet
check_status "ship-skip mismatch -> exit 1" 1 "$STATUS"
check_contains "reports the ship-skip mismatch" "$OUT" "ship-skip list"

# a multi-name case arm must be read in full, not truncated to its last name.
d="$(mk_clean_repo)"
printf '#!/usr/bin/env bash\nfor x in "$@"; do case "$x" in polish.md|draft.md) continue ;; esac; done\n' \
  > "$d/install.sh"
( cd "$d" && git add -A && git commit -qm "multi-name arm" )
run "$sd" "$d" --quiet
check_status "multi-name arm still trips the mismatch -> exit 1" 1 "$STATUS"

# a file with NO ") continue" line at all is a valid (empty) skip list, not a crash — grep
# legitimately exits 1 on zero matches, which must not kill the script under set -euo pipefail.
d="$(mk_clean_repo)"
printf '#!/usr/bin/env bash\necho nothing to skip here\n' > "$d/install.sh"
printf '#!/usr/bin/env bash\necho nothing to skip here\n' > "$d/tools/doctor.sh"
( cd "$d" && git add -A && git commit -qm "no skip lines at all" )
run "$sd" "$d" --quiet
check_status "no ship-skip lines at all doesn't crash -> exit 0" 0 "$STATUS"

# an unrelated ") continue" arm with no .md name (both files carry ones like this for real —
# tools/doctor.sh parses markdown tables and worktree lists) must not corrupt the comparison.
d="$(mk_clean_repo)"
printf '#!/usr/bin/env bash\nfor x in "$@"; do case "$x" in polish.md) continue ;; *) continue ;; esac; done\n' \
  > "$d/install.sh"
( cd "$d" && git add -A && git commit -qm "unrelated bare continue arm present too" )
run "$sd" "$d" --quiet
check_status "an unrelated bare continue arm doesn't corrupt the match -> exit 0" 0 "$STATUS"

# --- 1b. the core-@import pattern, hand-copied into three standalone scripts ----------------------
# The mutation standard: the check must FAIL when a copy drifts, not merely pass on today's tree.
core_re='(^|[[:space:]])@[^[:space:]]*keel/CORE\.md([[:space:]]|$)'
plant_import_re() {   # plant_import_re DIR PATTERN-FOR-UNINSTALL
  printf "has_core_import() { grep -qE '%s' \"\$1\"; }\n" "$core_re" >> "$1/install.sh"
  printf "grep -qE '%s' x\n" "$core_re" >> "$1/tools/doctor.sh"
  # the variable is read on the next line so self/doctor.sh's own shellcheck leg stays clean (SC2034)
  printf "#!/usr/bin/env bash\ncore_import_re='%s'\ngrep -qE \"\$core_import_re\" x\n" "$2" \
    > "$1/uninstall.sh"
}

d="$(mk_clean_repo)"; plant_import_re "$d" "$core_re"
( cd "$d" && git add -A && git commit -qm "import re in all three" )
run "$sd" "$d" --quiet
check_status "three identical copies -> exit 0" 0 "$STATUS"

# one copy silently loses its end boundary — the exact widening dir #108 was
d="$(mk_clean_repo)"; plant_import_re "$d" '(^|[[:space:]])@[^[:space:]]*keel/CORE\.md'
( cd "$d" && git add -A && git commit -qm "drifted import re" )
run "$sd" "$d" --quiet
check_status "a drifted copy -> exit 1" 1 "$STATUS"
check_contains "names the drift" "$OUT" "core-@import pattern differs"

# a copy deleted outright, rather than edited
d="$(mk_clean_repo)"; plant_import_re "$d" "$core_re"
printf '#!/usr/bin/env bash\necho no pattern here\n' > "$d/uninstall.sh"
( cd "$d" && git add -A && git commit -qm "import re dropped from uninstall" )
run "$sd" "$d" --quiet
check_status "a missing copy -> exit 1" 1 "$STATUS"
check_contains "names the file that lost it" "$OUT" "missing from: uninstall.sh"

# a repo that defines it nowhere has no rule to keep in sync — silent, not a GAP (mirrors check 1's
# empty-skip-list arm; mk_clean_repo's fixtures carry no pattern at all)
# Deliberately NOT --quiet: the silent-when-absent branch is invisible under --quiet (it suppresses
# `say`), so the assertion below would pass no matter what the check did.
d="$(mk_clean_repo)"
run "$sd" "$d"
check_status "no copies anywhere -> exit 0" 0 "$STATUS"
check_absent "and says nothing about the pattern" "$OUT" "core-@import"

# --- 1c. advised commands must carry the home they are about -------------------------------------
# Source-level on purpose: most of doctor's advice lives in findings that only fire on a BROKEN
# install, so an output sweep can't reach them.
# Appends one advice line to the fixture's install.sh. The variables are assigned first so the
# sandbox stays shellcheck-clean — self/doctor.sh lints it, and an SC2154 would GAP for the wrong
# reason and make every assertion below read as a pass or fail of this check when it isn't.
plant_advice() {   # plant_advice ADVICE-LINE DIR
  { printf 'home_flag=""; ihome=""; echo "$ihome$home_flag" >/dev/null\n'   # both read → no SC2034
    printf '%s\n' "$1"; } >> "$2/install.sh"
}

d="$(mk_clean_repo)"
plant_advice 'echo "re-run install.sh$home_flag to fix"' "$d"
( cd "$d" && git add -A && git commit -qm "advice carrying the marker" )
run "$sd" "$d" --quiet
check_status "advice carrying the home marker -> exit 0" 0 "$STATUS"

d="$(mk_clean_repo)"
plant_advice 'echo "re-run install.sh to fix"' "$d"
( cd "$d" && git add -A && git commit -qm "advice without the marker" )
run "$sd" "$d" --quiet
check_status "advice missing the home marker -> exit 1" 1 "$STATUS"
check_contains "names the offending line" "$OUT" "re-run install.sh to fix"

# An explicit --home counts as its own marker — the rule is "reaches the home", not "uses a variable".
d="$(mk_clean_repo)"
plant_advice 'echo "run keel uninstall --home \"$ihome\" to remove it"' "$d"
( cd "$d" && git add -A && git commit -qm "advice with an explicit --home" )
run "$sd" "$d" --quiet
check_status "an explicit --home also satisfies it -> exit 0" 0 "$STATUS"

# uninstall.sh must not match install.sh as a substring — it would be reported as advice about a
# command the line never gave. (An earlier `[^u]install\.sh` spelling of this guard excluded nothing:
# the character before `install.sh` inside `uninstall.sh` is `n`.)
d="$(mk_clean_repo)"
plant_advice 'echo "  Re-run uninstall.sh --yes to confirm."' "$d"
( cd "$d" && git add -A && git commit -qm "advice naming uninstall.sh" )
run "$sd" "$d" --quiet
check_status "uninstall.sh is not reported as install.sh advice -> exit 0" 0 "$STATUS"

# Structural scope, not a phrase list: a comment or a usage line naming the same command is not advice.
d="$(mk_clean_repo)"
printf '#!/usr/bin/env bash\n# re-run install.sh to fix\ncat <<EOF\n  install.sh --home DIR   bootstrap into DIR\nEOF\n' >> "$d/install.sh"
( cd "$d" && git add -A && git commit -qm "comment and usage text only" )
run "$sd" "$d" --quiet
check_status "a comment / usage line naming the command is not advice -> exit 0" 0 "$STATUS"

# --- 1d. FRAMEWORK.md / PRINCIPLES.md identifier leak -> GAP (dir #114, M4-1) ----------------------
# Absence of both files is the sandbox's default (mk_clean_repo creates neither) and must stay clean.
d="$(mk_clean_repo)"
run "$sd" "$d" --quiet
check_status "neither file present -> exit 0" 0 "$STATUS"

d="$(mk_clean_repo)"
printf '# Framework\nNothing personal here.\n' > "$d/FRAMEWORK.md"
( cd "$d" && git add -A && git commit -qm "clean FRAMEWORK.md" )
run "$sd" "$d" --quiet
check_status "clean FRAMEWORK.md -> exit 0" 0 "$STATUS"

d="$(mk_clean_repo)"
printf '# Framework\nSee /Users/exampleuser/repo for the layout.\n' > "$d/FRAMEWORK.md"
( cd "$d" && git add -A && git commit -qm "leaked home path" )
run "$sd" "$d" --quiet
check_status "leaked home path in FRAMEWORK.md -> exit 1" 1 "$STATUS"
check_contains "names the leak" "$OUT" "leaked host path"

d="$(mk_clean_repo)"
printf '# Principles\nContact person@example-corp.com with questions.\n' > "$d/PRINCIPLES.md"
( cd "$d" && git add -A && git commit -qm "leaked email" )
run "$sd" "$d" --quiet
check_status "leaked non-safe email in PRINCIPLES.md -> exit 1" 1 "$STATUS"
check_contains "names the leak" "$OUT" "leaked personal/corporate email"

# a safe-listed email (the shared allowlist) must not false-GAP
d="$(mk_clean_repo)"
printf '# Principles\nCo-Authored-By: Claude <noreply@anthropic.com>\n' > "$d/PRINCIPLES.md"
( cd "$d" && git add -A && git commit -qm "safe-listed email" )
run "$sd" "$d" --quiet
check_status "safe-listed email -> exit 0" 0 "$STATUS"

# --- 2. dead internal reference -> GAP -------------------------------------------------------------
d="$(mk_clean_repo)"
printf 'See `%s` for details.\n' "$fake_dead" > "$d/README.md"
( cd "$d" && git add -A && git commit -qm "dead ref" )
run "$sd" "$d" --quiet
check_status "dead reference -> exit 1" 1 "$STATUS"
check_contains "reports the dead reference" "$OUT" "dead reference '$fake_dead'"

# a false-positive guard: a path nested inside a longer, unrelated one (e.g. a test's sandbox
# install target) must NOT be flagged as a dead repo-root reference.
d="$(mk_clean_repo)"
printf 'check_file "x" "$HOME/.claude/%s"\n' "$fake_nested" > "$d/tests/test_nested_path.sh"
( cd "$d" && git add -A && git commit -qm "nested path" )
run "$sd" "$d" --quiet
check_absent "nested path is not a false-positive dead ref" "$OUT" "$fake_nested"

# a false-negative guard: a genuine bare dead reference must still be caught even when the SAME
# path also appears nested elsewhere in the same file — one occurrence must not vouch for the other.
d="$(mk_clean_repo)"
printf 'nested: "$HOME/.claude/%s"\nbare: %s\n' "$fake_nested" "$fake_nested" > "$d/tests/test_mixed.sh"
( cd "$d" && git add -A && git commit -qm "mixed nested and bare" )
run "$sd" "$d" --quiet
check_status "bare occurrence alongside a nested one still -> exit 1" 1 "$STATUS"
check_contains "still catches the bare occurrence" "$OUT" "dead reference '$fake_nested'"

# --- 3. orphan tool + no test coverage -> WARN only (not GAP) --------------------------------------
d="$(mk_clean_repo)"
printf '#!/usr/bin/env bash\necho orphan\n' > "$d/$fake_orphan"
( cd "$d" && git add -A && git commit -qm "orphan tool" )
run "$sd" "$d" --quiet
check_status "orphan tool is advisory only -> exit 0" 0 "$STATUS"
check_contains "flags the orphan tool" "$OUT" "orphan tool: no reference to $fake_orphan"
check_contains "flags missing test coverage" "$OUT" "no test coverage: $fake_orphan"

# a tool in a SUBDIRECTORY (e.g. the real tools/secret-guard/secret-scan.sh) must still be found
# and audited — a plain bash glob doesn't cross '/' and would silently skip it entirely.
fake_nested_tool="$(key tools/nested/tool .sh)"
d="$(mk_clean_repo)"
mkdir -p "$d/tools/nested"
printf '#!/usr/bin/env bash\necho nested\n' > "$d/$fake_nested_tool"
printf '#!/usr/bin/env bash\n# references %s\n' "$fake_nested_tool" > "$d/tests/test_nested_tool.sh"
( cd "$d" && git add -A && git commit -qm "nested tool dir" )
run "$sd" "$d"
check_status "a wired nested-dir tool is clean -> exit 0" 0 "$STATUS"
check_contains "the nested tool was actually audited" "$OUT" "$fake_nested_tool"

# a tool referenced only from CI, not from any of commands/ or tests/ or install.sh or docs/, is
# still wired, not an orphan — ref_files must include .github/workflows/*.yml.
d="$(mk_clean_repo)"
mkdir -p "$d/.github/workflows"
printf '#!/usr/bin/env bash\necho ci-only\n' > "$d/$fake_ci_tool"
printf 'jobs:\n  x:\n    run: %s\n' "$fake_ci_tool" > "$d/.github/workflows/ci.yml"
( cd "$d" && git add -A && git commit -qm "ci-only tool" )
run "$sd" "$d" --quiet
check_absent "a CI-only-referenced tool is not flagged orphan" "$OUT" "orphan tool: no reference to $fake_ci_tool"
check_contains "still flags it as untested (CI reference isn't test coverage)" "$OUT" "no test coverage: $fake_ci_tool"

# --- 4. CHANGELOG staleness -> WARN only ------------------------------------------------------------
d="$(mk_clean_repo)"
printf '# go (touched)\n' >> "$d/commands/go.md"
( cd "$d" && git add -A && git commit -qm "product change, no changelog entry" )
run "$sd" "$d" --quiet
check_status "changelog staleness is advisory only -> exit 0" 0 "$STATUS"
check_contains "flags the stale CHANGELOG" "$OUT" "CHANGELOG.md predates"

# a repo where CHANGELOG.md/commands/tools/install.sh were NEVER committed: `git log -1 -- <path>`
# exits 0 with EMPTY stdout (not an error) for an untouched pathspec, so the `|| echo 0` fallback
# never fires and the two _ts vars end up empty rather than "0" — `[ "" -gt "" ]` must not blow up
# with a stray "integer expression expected" on stderr (which `run`'s 2>&1 would capture).
d="$(new_repo)"
mkdir -p "$d/tests"
printf '# README\n' > "$d/README.md"
stub_orchestrated_tests "$d"
( cd "$d" && git add -A && git commit -qm "readme only, no changelog/commands/tools/install.sh ever" )
run "$sd" "$d" --quiet
check_absent "no 'integer expression expected' crash on unhistoried paths" "$OUT" "integer expression expected"
check_status "unhistoried CHANGELOG/product paths don't crash -> exit 0" 0 "$STATUS"

# --- 5. --quiet suppresses OK lines but keeps GAP/WARN -----------------------------------------------
d="$(mk_clean_repo)"
run "$sd" "$d"
check_contains "non-quiet shows OK lines" "$OUT" "  OK "
run "$sd" "$d" --quiet
check_absent "quiet suppresses OK lines" "$OUT" "  OK "

# --- 6. BACKLOG.md heading/status drift (dir #87) ---------------------------------------------------
# BACKLOG.md is gitignored — mk_clean_repo never creates one, so its absence must be a clean pass,
# not a crash or a false GAP.
d="$(mk_clean_repo)"
run "$sd" "$d" --quiet
check_status "no BACKLOG.md at all -> exit 0" 0 "$STATUS"

# a sixth /code-review medium round found an unreadable (but present) BACKLOG.md aborted the
# ENTIRE doctor.sh run under set -euo pipefail, not just this one check — root always reads
# regardless of chmod, so this only proves anything as non-root (same guard this project's own
# CLAUDE.md documents for a similar Alpine/root trap elsewhere).
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  d="$(mk_clean_repo)"
  printf '### dir #16 — some ticket — R1\n\n✅ CLOSED (2026-01-01, PR #16) — done.\n' > "$d/BACKLOG.md"
  chmod 000 "$d/BACKLOG.md"
  run "$sd" "$d" --quiet
  check_status "an unreadable BACKLOG.md doesn't abort the whole run -> exit 0" 0 "$STATUS"
  chmod 644 "$d/BACKLOG.md"
fi

# a heading with no ✅/⏳/RETRACTED tag whose own body already records closure -> WARN, not GAP:
# operator-run /code-review medium found this bug class is explicitly documented as low-severity
# by the ticket that implements it (dir #87 itself), and a hard GAP would fail this very smoke
# test (and block /polish step 7) the moment ANY dir-ticket heading anywhere goes stale.
d="$(mk_clean_repo)"
printf '### dir #1 — some ticket — R2\n\n✅ CLOSED (2026-01-01, PR #1) — done.\n' > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_status "stale heading tag is advisory only -> exit 0" 0 "$STATUS"
check_contains "reports the stale ticket id" "$OUT" "dir #1's heading tag looks stale"

# the SAME heading already carrying its own tag (✅/⏳/RETRACTED) is not re-flagged even though the
# body also says CLOSED — the tag is the thing being checked, not a ban on the word appearing twice.
d="$(mk_clean_repo)"
printf '### dir #2 — some ticket — R4 — ✅ CLOSED (2026-01-01, PR #2)\n\nCLOSED — done.\n' > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_absent "already-tagged heading is not flagged" "$OUT" "dir #2's heading tag looks stale"

# operator-run /code-review medium: a heading whose TITLE merely contains "RETRACTED" as prose
# (not a real status tag) must not be treated as already-tagged — the tag check needs the same
# \b word boundary the body check already has, or it silently swallows a genuinely stale heading.
d="$(mk_clean_repo)"
printf '### dir #6 — investigate whether the RETRACTED ticket process needs revisiting — R1\n\n✅ CLOSED (2026-01-01, PR #6) — done.\n' \
  > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_contains "RETRACTED as title prose doesn't count as a tag" "$OUT" "dir #6's heading tag looks stale"

# a sixth /code-review medium round found the same gap was never extended to ✅/⏳: a heading
# whose TITLE merely contains one of those glyphs as prose must not count as already-tagged either.
d="$(mk_clean_repo)"
printf '### dir #17 — decide on ✅ emoji conventions for status tags — R1\n\nRETRACTED (2026-01-01) — done.\n' \
  > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_contains "a bare ✅ in title prose doesn't count as a tag either" "$OUT" "dir #17's heading tag looks stale"

# an untagged heading whose body only mentions CLOSED/DONE/RETRACTED inside inline code (a prose
# example of the pattern itself, not a real status note — dir #87's own body does exactly this)
# must NOT be flagged.
d="$(mk_clean_repo)"
printf '### dir #3 — some ticket — R1\n\nsee `✅ CLOSED (PR #…)` for the shape; also `RETRACTED`.\n' \
  > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_status "backtick-quoted example text is not a false positive -> exit 0" 0 "$STATUS"

# Documented, accepted limitation (a fifth /code-review medium round found the same-line "dir #N"
# filter tried for this exact case introduced two worse bugs — a set -e abort when it filtered out
# an entire body, and a false negative on a ticket's own closure note that legitimately co-cites a
# sibling ticket it also closed — so the filter was reverted, not iterated on again). A body line
# that merely cross-references a DIFFERENT ticket's status DOES produce a WARN; pinned here as
# known/accepted rather than silently undocumented.
d="$(mk_clean_repo)"
printf '### dir #12 — some ticket, not closed — R1\n\nblocked by dir #40 (✅ CLOSED) for context; not related.\n' \
  > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_contains "cross-referencing another ticket's closed status is a known, accepted false positive" "$OUT" "dir #12's heading tag looks stale"

# Locks in what the revert fixed: a body whose ONLY line mentions another ticket must not abort
# the whole doctor.sh run (the reverted filter's `grep -v` matched nothing and, under set -e,
# killed the script entirely rather than just this check).
d="$(mk_clean_repo)"
printf '### dir #13 — some ticket — R1\n\nSee dir #2 for full context.\n' > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_status "a body that's entirely a cross-reference doesn't abort the whole run" 0 "$STATUS"

# Locks in the other half: a ticket's OWN closure note that also legitimately co-cites a sibling
# ticket it closed together ("also closes dir #N" — a real, already-used convention in this
# project's own BACKLOG.md) must still be detected, not silently dropped.
d="$(mk_clean_repo)"
printf '### dir #14 — some ticket — R2\n\n✅ CLOSED (2026-01-01, PR #14 merged; also closes dir #15).\n' \
  > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_contains "own closure note co-citing a sibling ticket is still detected" "$OUT" "dir #14's heading tag looks stale"

# operator-run /code-review medium: the same false-positive guard must hold for a MULTI-LINE
# fenced ``` code block quoting the pattern (a spec-heavy ticket documenting its own convention),
# not just single-line backtick spans.
d="$(mk_clean_repo)"
printf '### dir #7 — some ticket — R1\n\nsee the shape below:\n\n```\n✅ CLOSED (PR #…)\n```\n' \
  > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_status "fenced-code-block example text is not a false positive -> exit 0" 0 "$STATUS"

# a second /code-review medium round found the inverse gap: a `##`/`###`-prefixed line living
# INSIDE a fenced code block (a bash comment, a markdown snippet) was still read as a real section
# boundary by heading/boundary detection (which scanned the raw file, not the fence-blanked copy),
# truncating the body span before a genuinely stale heading's own closure marker was ever reached.
d="$(mk_clean_repo)"
printf '### dir #8 — some ticket — R1\n\nexample:\n\n```\n## this is a bash comment\n```\n\n✅ CLOSED (2026-01-01, PR #8) — done.\n' \
  > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_contains "a ##-prefixed line inside a fenced block isn't read as a real boundary" "$OUT" "dir #8's heading tag looks stale"

# a third /code-review medium round found the same gap for an INDENTED fence marker (e.g. inside a
# bulleted list item) — the fence regex must match tools/doctor.sh's own established
# `^[[:space:]]*(\`\`\`|~~~)` pattern (indented + tilde fences too), not just column-0 backticks.
d="$(mk_clean_repo)"
printf '### dir #9 — some ticket — R1\n\n- example:\n\n  ```\n## this is a bash comment\n### dir #999 fake ticket\n  ```\n\n✅ CLOSED (2026-01-01, PR #9) — done.\n' \
  > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_contains "an indented fence marker isn't read as a real boundary either" "$OUT" "dir #9's heading tag looks stale"

# body text below an untagged heading must not leak past a `## ` section boundary into a LATER
# heading's own body span.
d="$(mk_clean_repo)"
printf '### dir #4 — untagged ticket — R1\n\nnothing closed here.\n\n## Recently closed\n\n- ✅ 2026-01-01 dir #4 CLOSED — done.\n' \
  > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_absent "a ## section boundary stops the body scan" "$OUT" "dir #4's heading tag looks stale"

# a BACKLOG.md with NO trailing newline on its last line must neither crash (an unguarded `while
# read` drops an unterminated last line, desyncing the line-number and content arrays) nor silently
# miss a stale heading whose own closure marker sits on that dropped last line.
d="$(mk_clean_repo)"
printf '### dir #5 — some ticket — R1\n\n✅ CLOSED (2026-01-01, PR #5) — done.' > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_status "no trailing newline doesn't crash -> exit 0" 0 "$STATUS"
check_contains "still catches the stale heading from the no-trailing-newline file" "$OUT" "dir #5's heading tag looks stale"

# --- 7. BACKLOG.md heading check resolves the MAIN checkout from a worktree invocation (dir #135) ---
# BACKLOG.md is gitignored and lives ONLY at the main checkout root (this project's own convention) —
# a linked worktree never gets its own copy. Before this fix, self_dir/../.. (repo_root) was whatever
# checkout self/doctor.sh was INVOKED against, so a worktree invocation resolved repo_root to the
# WORKTREE and silently "skipped, no readable BACKLOG.md" every time — exactly where /polish's step 7
# self-check actually runs. `git worktree add` only checks out TRACKED content, so writing BACKLOG.md
# into the main checkout $d before adding the worktree reproduces the real split precisely: $d has it,
# $wt does not.
d="$(mk_clean_repo)"
printf '### dir #1 — some ticket — R2\n\n✅ CLOSED (2026-01-01, PR #1) — done.\n' > "$d/BACKLOG.md"
wt="$SANDBOX/wt135"
( cd "$d" && git worktree add -q -b wt135-branch "$wt" )
run "$sd" "$wt" --quiet
check_status "a worktree invocation is still advisory-only when it finds the main checkout's stale heading -> exit 0" 0 "$STATUS"
check_contains "a worktree invocation finds the main checkout's BACKLOG.md, not silently skipped" "$OUT" "dir #1's heading tag looks stale"

# --- 8. a ⏳/IN REVIEW BACKLOG.md heading citing a MERGED PR (dir #135) ---------------------------
# `gh` is stubbed via PATH so these tests never make a real network call. `pr view <n> --json state
# -q .state` is the only invocation self/doctor.sh makes; the stub just echoes a canned state per PR
# number and ignores the rest of the arguments.
fake_gh_bin="$SANDBOX/fakebin-gh"
mkdir -p "$fake_gh_bin"
cat > "$fake_gh_bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  case "$3" in
    99)  echo MERGED ;;
    100) echo OPEN ;;
    101) exit 1 ;;   # simulates gh failing: offline, no auth, no such PR
    *)   echo OPEN ;;
  esac
  exit 0
fi
exit 1
EOF
chmod +x "$fake_gh_bin/gh"

d="$(mk_clean_repo)"
printf '### dir #20 — some ticket — R2 — ⏳ IN REVIEW (PR #99)\n\nstill waiting on review.\n' > "$d/BACKLOG.md"
run env PATH="$fake_gh_bin:$PATH" "$sd" "$d" --quiet
check_status "a merged PR cited as still IN REVIEW is advisory only -> exit 0" 0 "$STATUS"
check_contains "flags the heading citing the merged PR" "$OUT" \
  "dir #20's heading cites PR #99 as ⏳/IN REVIEW but gh reports it MERGED"

# a PR that's still genuinely open must not be flagged
d="$(mk_clean_repo)"
printf '### dir #21 — some ticket — R2 — ⏳ IN REVIEW (PR #100)\n\nstill waiting on review.\n' > "$d/BACKLOG.md"
run env PATH="$fake_gh_bin:$PATH" "$sd" "$d" --quiet
check_absent "an open PR is not flagged" "$OUT" "dir #21's heading cites"

# gh failing (offline / no auth / unknown PR) must degrade gracefully — no crash, no false flag
d="$(mk_clean_repo)"
printf '### dir #22 — some ticket — R2 — ⏳ IN REVIEW (PR #101)\n\nstill waiting on review.\n' > "$d/BACKLOG.md"
run env PATH="$fake_gh_bin:$PATH" "$sd" "$d" --quiet
check_status "a failing gh call doesn't crash the run -> exit 0" 0 "$STATUS"
check_absent "and doesn't false-flag" "$OUT" "dir #22's heading cites"

# gh entirely absent from PATH must also degrade gracefully. A non-executable shim does NOT prove
# this (bash's `command -v` skips a non-executable match and keeps searching PATH) — build a PATH
# that genuinely never resolves `gh` at all, carrying only the tools self/doctor.sh itself invokes.
no_gh_bin="$SANDBOX/fakebin-nogh"
mkdir -p "$no_gh_bin"
for tool in awk basename bash cat chmod cut dirname git grep head printf sed sort tail wc env true false; do
  t="$(command -v "$tool" 2>/dev/null)" && ln -sf "$t" "$no_gh_bin/$tool"
done
d="$(mk_clean_repo)"
printf '### dir #23 — some ticket — R2 — ⏳ IN REVIEW (PR #99)\n\nstill waiting on review.\n' > "$d/BACKLOG.md"
run env PATH="$no_gh_bin" "$sd" "$d" --quiet
check_status "no gh on PATH at all doesn't crash the run -> exit 0" 0 "$STATUS"
check_absent "and doesn't false-flag" "$OUT" "dir #23's heading cites"

# a tagged heading with no PR # at all (e.g. the ⏳ IN FLIGHT claim marker `/go` writes) must not
# attempt a gh call, let alone flag anything.
d="$(mk_clean_repo)"
printf '### dir #24 — some ticket — R2 — ⏳ IN FLIGHT (2026-01-01, branch foo)\n\nclaimed.\n' > "$d/BACKLOG.md"
run env PATH="$fake_gh_bin:$PATH" "$sd" "$d" --quiet
check_status "an IN FLIGHT claim marker with no PR # is untouched -> exit 0" 0 "$STATUS"
check_absent "no gap/warn for it" "$OUT" "dir #24's heading cites"

# "IN REVIEW" or "⏳" appearing only as heading TITLE prose (not after the "— " tag separator) must
# not count as a real tag — same false-positive guard the tag-staleness loop already relies on
# (dir #17's own test case for that loop).
d="$(mk_clean_repo)"
printf '### dir #25 — decide whether IN REVIEW should replace ⏳ — R1\n\n✅ CLOSED (2026-01-01, PR #99) — done.\n' \
  > "$d/BACKLOG.md"
run env PATH="$fake_gh_bin:$PATH" "$sd" "$d" --quiet
check_absent "title prose mentioning IN REVIEW/⏳ isn't treated as a real tag" "$OUT" "dir #25's heading cites"

# --- 9. CHANGELOG.md <-> git release-tag reconciliation (dir #139) ---------------------------------
# Each fixture builds its own small CHANGELOG.md + tag history directly, independent of this repo's
# OWN real release history.

# a clean repo where every tag has a section and every section has a tag -> exit 0, no GAP
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n## [1.0.0] — 2026-01-01\n- first release\n' > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
run "$sd" "$d" --quiet
check_status "every tag has a section and vice versa -> exit 0" 0 "$STATUS"
check_absent "no reconciliation GAP" "$OUT" "GAP"

# the exact PR #118 accident: a released section gets deleted by a LATER commit, its tag still exists
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n## [1.0.0] — 2026-01-01\n- first release\n\n## [1.1.0] — 2026-01-02\n- second release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0 and 1.1.0" && git tag v1.0.0 && git tag v1.1.0 )
printf '# Changelog\n\n## [Unreleased]\n- init\n\n## [1.1.0] — 2026-01-02\n- second release\n' > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "PR #118: accidentally clobbers the 1.0.0 heading" )
run "$sd" "$d" --quiet
check_status "a tag whose section got clobbered by a later commit -> exit 1" 1 "$STATUS"
check_contains "names the orphaned tag" "$OUT" "release tag(s) with no matching CHANGELOG.md"
check_contains "and names it specifically" "$OUT" "1.0.0"

# the inverse: a CHANGELOG section with no matching tag (a version cut in the file but never tagged)
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n## [1.0.0] — 2026-01-01\n- first release\n\n## [1.1.0] — 2026-01-02\n- never actually tagged\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "1.0.0 tagged, 1.1.0 written but not" && git tag v1.0.0 )
run "$sd" "$d" --quiet
check_status "a section with no matching tag -> exit 1" 1 "$STATUS"
check_contains "names the untagged section" "$OUT" "section(s) with no matching release tag"
check_contains "and names it specifically" "$OUT" "1.1.0"

# section-count invariant: a DUPLICATED heading (e.g. a bad merge). Both directional checks pass —
# every tag NAME has a matching section and vice versa, since `sort -u` dedupes the name lists — so
# only the raw section-count invariant, comparing sections found to tags + Unreleased, catches the
# extra copy at all.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n## [1.0.0] — 2026-01-01\n- first release\n\n## [1.0.0] — 2026-01-01\n- duplicated by a bad merge\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0, duplicated by a bad merge" && git tag v1.0.0 )
run "$sd" "$d" --quiet
check_status "a duplicated heading -> exit 1" 1 "$STATUS"
check_contains "names the count mismatch" "$OUT" "CHANGELOG.md section count"
check_absent "the directional checks alone see no missing name (dedup hides the duplicate)" "$OUT" \
  "no matching CHANGELOG.md"
check_absent "and no missing tag either" "$OUT" "no matching release tag"

# no CHANGELOG.md at all -> clean skip, not a crash or a GAP
d="$(mk_clean_repo)"
rm "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "no changelog" )
run "$sd" "$d" --quiet
check_status "no CHANGELOG.md at all -> exit 0" 0 "$STATUS"

# a shallow clone must degrade to a silent skip, not a false GAP — the whole point of dir #139's own
# `is-shallow-repository` guard: a shallow checkout (CI's own default, absent the fetch-depth: 0 this
# same ticket adds to ci.yml) has few or none of the tags this check needs even though the working
# tree itself is perfectly fine.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n## [1.0.0] — 2026-01-01\n- first release\n\n## [1.1.0] — 2026-01-02\n- second release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0 and 1.1.0" && git tag v1.0.0 && git tag v1.1.0 )
shallow="$SANDBOX/shallow139"
git clone -q --depth 1 "file://$d" "$shallow"
run "$sd" "$shallow" --quiet
check_status "a shallow clone skips the reconciliation rather than false-GAPing -> exit 0" 0 "$STATUS"
check_absent "no reconciliation GAP on a shallow clone" "$OUT" "CHANGELOG.md section"

summary
