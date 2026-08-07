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

  for f in test_doc_figures.sh test_core_wrapper_sync.sh; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/tests/$f"
  done

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

# an untagged heading whose body only mentions CLOSED/DONE/RETRACTED inside inline code (a prose
# example of the pattern itself, not a real status note — dir #87's own body does exactly this)
# must NOT be flagged.
d="$(mk_clean_repo)"
printf '### dir #3 — some ticket — R1\n\nsee `✅ CLOSED (PR #…)` for the shape; also `RETRACTED`.\n' \
  > "$d/BACKLOG.md"
run "$sd" "$d" --quiet
check_status "backtick-quoted example text is not a false positive -> exit 0" 0 "$STATUS"

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

summary
