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
fake_ghost_md="$(key commands/ghostcmd .md)"

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
# doctor.sh's orchestrated checks (line ~861) unconditionally `bash`-exec these two files, so any
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

  # the only mention of tools/doctor.sh and $fake_widget — makes both "wired" (referenced + tested).
  # A real code line, not a `#`-comment (leading OR trailing): dir #242's ratchet fix requires a
  # tests/*.sh mention to survive comment-stripping before it counts as test coverage, closing the
  # exact loophole (a bare comment mention with no actual test) this fixture used to rely on.
  printf '#!/usr/bin/env bash\n: "smoke-references tools/doctor.sh and %s"\n' "$fake_widget" \
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

# one copy silently loses its end boundary — the exact widening dir #108 was fixed against
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

# --- 2b. slash-command reference -> GAP (dir #129, moved from tests/test_rails_honesty.sh) --------
# The mutation standard: mk_clean_repo's own commands/go.md and commands/polish.md give a real
# "shipped" case to contrast an unshipped one against, same as check 2's fixtures above.
d="$(mk_clean_repo)"
printf 'Run `/nosuchcmd` first.\n' > "$d/README.md"
( cd "$d" && git add -A && git commit -qm "unshipped slash command" )
run "$sd" "$d" --quiet
check_status "unshipped slash-command reference -> exit 1" 1 "$STATUS"
# built via key(), not a literal path — this file's own comments/assertions are themselves scanned
# by check 2's dead-reference class, and a bare literal here would false-GAP the real checkout's own
# self-audit (the fake_widget/fake_orphan fixtures above dodge it the same way).
check_contains "reports the unshipped command" "$OUT" "slash-command reference '/nosuchcmd' in README.md has no $(key commands/nosuchcmd .md)"

# a reference to a command that IS shipped must not false-GAP.
d="$(mk_clean_repo)"
printf 'Run `/go` to start.\n' > "$d/README.md"
( cd "$d" && git add -A && git commit -qm "shipped slash command" )
run "$sd" "$d" --quiet
check_status "a shipped slash-command reference -> exit 0" 0 "$STATUS"

# the harness_commands allowlist (dir #110): a Claude-Code-builtin-style name never shipped as a
# commands/*.md file must not false-GAP.
d="$(mk_clean_repo)"
printf 'Then run `/code-review high`.\n' > "$d/README.md"
( cd "$d" && git add -A && git commit -qm "harness-allowlisted command" )
run "$sd" "$d" --quiet
check_status "a harness-allowlisted command -> exit 0" 0 "$STATUS"

# the not_commands allowlist (dir #110): a token that only looks like a command (a filesystem path
# or an adopter's own pre-existing name) must not false-GAP.
d="$(mk_clean_repo)"
printf 'See `/tmp` for scratch files.\n' > "$d/README.md"
( cd "$d" && git add -A && git commit -qm "not-a-command allowlisted token" )
run "$sd" "$d" --quiet
check_status "a not_commands-allowlisted token -> exit 0" 0 "$STATUS"

# a multi-segment filesystem path is never captured at all — the regex's single-segment shape is the
# guard, not the allowlist.
d="$(mk_clean_repo)"
printf 'Installed under `/usr/bin` on most systems.\n' > "$d/README.md"
( cd "$d" && git add -A && git commit -qm "multi-segment filesystem path" )
run "$sd" "$d" --quiet
check_status "a multi-segment filesystem path is not captured -> exit 0" 0 "$STATUS"

# closing-backtick prose: the backtick right before the slash is a code span's CLOSING one, not an
# opening one — must not be read as a citation.
d="$(mk_clean_repo)"
printf 'See `CLAUDE.md`/git for details.\n' > "$d/README.md"
( cd "$d" && git add -A && git commit -qm "closing-backtick prose" )
run "$sd" "$d" --quiet
check_status "closing-backtick prose is not a false citation -> exit 0" 0 "$STATUS"

# scan surface reaches CORE.md, IDEAS.md and templates/*.md, not just README.md — the same files the
# original tests/test_rails_honesty.sh glob covered.
d="$(mk_clean_repo)"
mkdir -p "$d/templates"
printf 'Run `/nosuchcmd` first.\n' > "$d/templates/CLAUDE.md"
( cd "$d" && git add -A && git commit -qm "unshipped ref inside templates/" )
run "$sd" "$d" --quiet
check_status "an unshipped ref inside templates/ is caught too -> exit 1" 1 "$STATUS"
check_contains "reports it from the templates/ scan" "$OUT" "slash-command reference '/nosuchcmd'"

# check 2's own broader scan set (tests/*.sh, install.sh, tools/*.sh) is deliberately NOT part of
# this check's scan — those shell files are full of backticked `/word` text that is not a
# slash-command citation (a GitHub API path fragment, a Claude Code builtin like `/clear`).
fake_pulls_tool="$(key tools/pulls-example .sh)"
d="$(mk_clean_repo)"
printf '#!/usr/bin/env bash\n# an endpoint ending in `/pulls`\necho ok\n' > "$d/$fake_pulls_tool"
printf '#!/usr/bin/env bash\n: "smoke-references %s"\n' "$fake_pulls_tool" > "$d/tests/test_pulls_example.sh"
( cd "$d" && git add -A && git commit -qm "shell-only /pulls text stays out of scope" )
run "$sd" "$d" --quiet
check_status "shell-file-only /word text is out of the slash-command scan -> exit 0" 0 "$STATUS"

# a tracked file UNSTAGED-DELETED from the working tree (still in `git ls-files`, gone from disk)
# must not blind the whole batched scan — the single `grep -r` call across every scanned file fails
# its ENTIRE run if any one file operand is unreadable, so without an existence filter this would
# silently swallow a genuine unshipped reference in a DIFFERENT, still-present file too.
d="$(mk_clean_repo)"
printf '# readme\n' > "$d/README.md"
printf 'Run `/nosuchcmd` first.\n' > "$d/ADAPTING.md"
( cd "$d" && git add -A && git commit -qm "tracked README.md plus an unshipped ref in a second file" )
rm "$d/README.md"
run "$sd" "$d" --quiet
check_status "an unstaged-deleted tracked file doesn't blind the batched scan -> exit 1" 1 "$STATUS"
check_contains "the OTHER file's unshipped ref is still caught" "$OUT" "slash-command reference '/nosuchcmd' in ADAPTING.md"

# --- 3. orphan tool -> WARN (advisory); a NEW script with zero test coverage -> hard GAP -----------
# (the coverage ratchet, dir #142 — a mutation test on the class dir #100 was found only reactively:
# a script planted with no test coverage at all must fail the self-check, not merely warn about it.)
d="$(mk_clean_repo)"
printf '#!/usr/bin/env bash\necho orphan\n' > "$d/$fake_orphan"
( cd "$d" && git add -A && git commit -qm "orphan tool" )
run "$sd" "$d" --quiet
check_status "an untested new tool trips the coverage ratchet -> exit 1" 1 "$STATUS"
check_contains "still flags the orphan tool (that half stays advisory)" "$OUT" "orphan tool: no reference to $fake_orphan"
check_contains "flags the ratchet GAP for zero test coverage" "$OUT" "ratchet (dir #142): $fake_orphan"

# the same script, but LISTED in tools/self/legacy-untested.txt -> the soft-debt half of the ratchet:
# WARN, not a hard GAP.
d="$(mk_clean_repo)"
printf '#!/usr/bin/env bash\necho legacy\n' > "$d/$fake_orphan"
mkdir -p "$d/tools/self"
printf '# pre-existing debt\n%s\n' "$fake_orphan" > "$d/tools/self/legacy-untested.txt"
( cd "$d" && git add -A && git commit -qm "listed legacy-debt tool" )
run "$sd" "$d" --quiet
check_status "a listed legacy-debt tool is advisory only -> exit 0" 0 "$STATUS"
check_contains "flags it as listed debt" "$OUT" "listed debt (dir #142, tools/self/legacy-untested.txt): $fake_orphan"
check_absent "not also raised as a fresh ratchet GAP" "$OUT" "ratchet (dir #142): $fake_orphan"

# the installed `keel` CLI (install.sh's own make_link target) is part of the ratchet's inventory too
# per dir #142's definition ("what install.sh itself installs" plus tools/*.sh) — not just the
# tools/*.sh glob.
d="$(mk_clean_repo)"
printf '#!/usr/bin/env bash\necho keel\n' > "$d/keel"
( cd "$d" && git add -A && git commit -qm "keel cli, untested" )
run "$sd" "$d" --quiet
check_status "an untested keel CLI trips the ratchet too -> exit 1" 1 "$STATUS"
check_contains "flags the ratchet GAP for keel" "$OUT" "ratchet (dir #142): keel"

# an UNTRACKED file named 'keel' (e.g. a stray local build artifact) must not be swept into the
# inventory — only a tracked keel is a real shipped executable.
d="$(mk_clean_repo)"
printf '#!/usr/bin/env bash\necho untracked\n' > "$d/keel"
run "$sd" "$d" --quiet
check_status "an untracked keel file is not audited -> exit 0" 0 "$STATUS"
check_absent "no ratchet GAP for an untracked keel" "$OUT" "ratchet (dir #142): keel"

# a tool in a SUBDIRECTORY (e.g. the real tools/secret-guard/secret-scan.sh) must still be found
# and audited — a plain bash glob doesn't cross '/' and would silently skip it entirely.
fake_nested_tool="$(key tools/nested/tool .sh)"
d="$(mk_clean_repo)"
mkdir -p "$d/tools/nested"
printf '#!/usr/bin/env bash\necho nested\n' > "$d/$fake_nested_tool"
printf '#!/usr/bin/env bash\n: "references %s"\n' "$fake_nested_tool" > "$d/tests/test_nested_tool.sh"
( cd "$d" && git add -A && git commit -qm "nested tool dir" )
run "$sd" "$d"
check_status "a wired nested-dir tool is clean -> exit 0" 0 "$STATUS"
check_contains "the nested tool was actually audited" "$OUT" "$fake_nested_tool"

# dir #242's own ratchet tightening, mutation-proven: a tool whose ONLY tests/*.sh mention sits on a
# leading `#`-comment line must still GAP as uncovered — reverting the comment-stripping back to a
# bare substring match makes this fixture pass with no GAP, which is what proves the tightening is
# load-bearing rather than a change nothing in the suite actually exercises (found live by an
# operator-run cross-model second-opinion pass: the fixture edits elsewhere in this file only stopped
# RELYING on the loophole, they never asserted it was closed). This also doubles as the regression test
# for an earlier version of the fix (`grep -vE '^[[:space:]]*#'`, without `|| true`): a tests/*.sh file
# made ENTIRELY of comment lines made that `grep -v` exit 1 with no output, which aborted doctor.sh
# outright under `set -e` — a real comment-only mention like this fixture's, not a synthetic one, is
# exactly the shape that used to crash. The shipped fix uses `sed -E 's/(^|[[:space:]])#.*$//'`
# instead, which never fails on an all-comment input, so this fixture also stands as a live check that
# whatever stripping mechanism is used doesn't regress that crash.
fake_comment_only_tool="$(key tools/comment-only .sh)"
d="$(mk_clean_repo)"
printf '#!/usr/bin/env bash\necho comment-only\n' > "$d/$fake_comment_only_tool"
printf '#!/usr/bin/env bash\n# mentions %s but never actually runs or checks it\n' "$fake_comment_only_tool" \
  > "$d/tests/test_comment_only.sh"
( cd "$d" && git add -A && git commit -qm "comment-only mention of a tool" )
run "$sd" "$d" --quiet
check_status "a tool mentioned only in a tests/*.sh comment -> exit 1 (ratchet GAP, not a crash)" 1 "$STATUS"
check_contains "flags it as uncovered, not silently passed" "$OUT" "ratchet (dir #142): $fake_comment_only_tool"

# The trailing-comment half of the same loophole (found by the same cross-model second-opinion pass):
# `real-code # mentions tools/<x>.sh` must ALSO not count as coverage — a leading-comment-only strip
# would still let this pass, since the mention lives after a trailing `#` on an otherwise-real line.
fake_trailing_comment_tool="$(key tools/trailing-comment .sh)"
d="$(mk_clean_repo)"
printf '#!/usr/bin/env bash\necho trailing-comment\n' > "$d/$fake_trailing_comment_tool"
printf '#!/usr/bin/env bash\ntrue # mentions %s but never actually runs or checks it\n' \
  "$fake_trailing_comment_tool" > "$d/tests/test_trailing_comment.sh"
( cd "$d" && git add -A && git commit -qm "trailing-comment mention of a tool" )
run "$sd" "$d" --quiet
check_status "a tool mentioned only after a trailing # comment -> exit 1 (ratchet GAP)" 1 "$STATUS"
check_contains "flags it as uncovered too" "$OUT" "ratchet (dir #142): $fake_trailing_comment_tool"

# a tool referenced only from CI, not from any of commands/ or tests/ or install.sh or docs/, is
# still wired, not an orphan — ref_files must include .github/workflows/*.yml.
d="$(mk_clean_repo)"
mkdir -p "$d/.github/workflows"
printf '#!/usr/bin/env bash\necho ci-only\n' > "$d/$fake_ci_tool"
printf 'jobs:\n  x:\n    run: %s\n' "$fake_ci_tool" > "$d/.github/workflows/ci.yml"
( cd "$d" && git add -A && git commit -qm "ci-only tool" )
run "$sd" "$d" --quiet
check_absent "a CI-only-referenced tool is not flagged orphan" "$OUT" "orphan tool: no reference to $fake_ci_tool"
check_status "a CI reference isn't test coverage -- the ratchet still GAPs it -> exit 1" 1 "$STATUS"
check_contains "flags the ratchet GAP" "$OUT" "ratchet (dir #142): $fake_ci_tool"

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
for tool in awk basename bash cat chmod cut dirname git grep head printf sed sort tail tr wc env true false; do
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

# an IN FLIGHT claim marker that DOES mention a (merged) PR in its own tail — e.g. "blocked by
# PR #99" — must not be mistaken for an IN REVIEW tag either. An earlier regex, `— (⏳|IN REVIEW)`,
# matched the bare ⏳ glyph alone, which every real ⏳ IN FLIGHT heading also starts with — so it
# would conflate the two DIFFERENT statuses this project actually uses, ⏳ IN FLIGHT (claimed, being
# worked) and ⏳ IN REVIEW (this check's own target) (found by an independent reviewer's own pass).
d="$(mk_clean_repo)"
printf '### dir #30 — some ticket — R2 — ⏳ IN FLIGHT (2026-01-01, branch foo, blocked by PR #99)\n\nclaimed.\n' \
  > "$d/BACKLOG.md"
run env PATH="$fake_gh_bin:$PATH" "$sd" "$d" --quiet
check_absent "an IN FLIGHT heading citing a merged PR isn't conflated with IN REVIEW" "$OUT" \
  "dir #30's heading cites"

# "IN REVIEW" or "⏳" appearing only as heading TITLE prose (not after the "— " tag separator) must
# not count as a real tag — same false-positive guard the tag-staleness loop already relies on
# (dir #17's own test case for that loop).
d="$(mk_clean_repo)"
printf '### dir #25 — decide whether IN REVIEW should replace ⏳ — R1\n\n✅ CLOSED (2026-01-01, PR #99) — done.\n' \
  > "$d/BACKLOG.md"
run env PATH="$fake_gh_bin:$PATH" "$sd" "$d" --quiet
check_absent "title prose mentioning IN REVIEW/⏳ isn't treated as a real tag" "$OUT" "dir #25's heading cites"

# a second, stricter false-positive shape (found by /polish's own independent review): the PR # AND
# the ⏳ glyph BOTH live in the heading line, but as title prose describing the convention, not as a
# real tag — the loose `— .*(⏳|IN REVIEW)` an earlier draft used would bridge an unrelated "— "
# elsewhere in the title across to this ⏳, treating discussion-about-the-convention as a real tag.
# The PR # has to be IN THE HEADING LINE for this to exercise the bug at all — dir #25 above puts its
# PR # in the body, which never reaches this code path.
d="$(mk_clean_repo)"
printf '### dir #26 — clarify whether ⏳ tickets citing PR #99 should auto-close — R1\n\nno status yet.\n' \
  > "$d/BACKLOG.md"
run env PATH="$fake_gh_bin:$PATH" "$sd" "$d" --quiet
check_absent "a PR # in title prose discussing the convention isn't treated as a real tag either" "$OUT" \
  "dir #26's heading cites"

# a heading whose TITLE names an earlier, unrelated PR before the real ⏳/IN REVIEW tag must check
# the PR the TAG actually cites, not the leftmost "PR #N" anywhere on the line (found by /code-review
# medium's own line-by-line pass — `[[ =~ ]]` against the whole line grabs the first match
# regardless of where the real tag sits). PR #100 (open, per fake_gh_bin) precedes the tag; the tag
# itself cites PR #99 (merged) — the correct, tag-scoped extraction must catch PR #99.
d="$(mk_clean_repo)"
printf '### dir #27 — follow-up to PR #100 — R2 — ⏳ IN REVIEW (PR #99)\n\nstill waiting.\n' \
  > "$d/BACKLOG.md"
run env PATH="$fake_gh_bin:$PATH" "$sd" "$d" --quiet
check_contains "checks the tag's own PR (#99), not the earlier title reference (#100)" "$OUT" \
  "dir #27's heading cites PR #99 as ⏳/IN REVIEW but gh reports it MERGED"

# the inverse, which is what would actually go WRONG under the leftmost-match bug: an earlier,
# unrelated MERGED PR in the title (#99) precedes the tag, but the tag itself cites a still-OPEN PR
# (#100) — the leftmost-match bug would wrongly warn about #99; the fix must stay silent, since the
# PR the tag actually names is still open.
d="$(mk_clean_repo)"
printf '### dir #28 — follow-up to PR #99 — R2 — ⏳ IN REVIEW (PR #100)\n\nstill waiting.\n' \
  > "$d/BACKLOG.md"
run env PATH="$fake_gh_bin:$PATH" "$sd" "$d" --quiet
check_absent "an earlier merged PR in the title doesn't cause a false flag for the tag's own open PR" \
  "$OUT" "dir #28's heading cites"

# `gh pr view` must run from the repo being audited, not wherever self/doctor.sh's own caller
# happens to sit — unlike every `git` call in this file, `gh` has no `-C` flag; it infers the target
# GitHub repo from the process's OWN cwd (found by /code-review medium's own line-by-line pass, which
# flagged the bare call as querying the wrong repo under a REPO_ARG invocation). This stub only
# answers MERGED when invoked with $PWD == $EXPECTED_PWD, so a bare (unscoped) `gh pr view` call —
# which would run from wherever this TEST FILE's own process cwd is, not `$d` — fails the PWD check
# and the warning never fires; only a genuinely `cd`'d call passes.
fake_gh_pwd_bin="$SANDBOX/fakebin-gh-pwd"
mkdir -p "$fake_gh_pwd_bin"
cat > "$fake_gh_pwd_bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "view" ] && [ "$PWD" = "$EXPECTED_PWD" ]; then
  echo MERGED
  exit 0
fi
exit 1
EOF
chmod +x "$fake_gh_pwd_bin/gh"

d="$(mk_clean_repo)"
printf '### dir #29 — some ticket — R2 — ⏳ IN REVIEW (PR #99)\n\nstill waiting.\n' > "$d/BACKLOG.md"
run env PATH="$fake_gh_pwd_bin:$PATH" EXPECTED_PWD="$(cd "$d" && pwd)" "$sd" "$d" --quiet
check_contains "gh runs from the repo under audit, not the caller's own cwd" "$OUT" \
  "dir #29's heading cites PR #99 as ⏳/IN REVIEW but gh reports it MERGED"

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

# `git tag -l` takes a GLOB, not a regex — a naive `v[0-9]*.[0-9]*.[0-9]*` pattern also matches a
# suffixed pre-release tag (`*` swallows the suffix too), which then can't match any CHANGELOG
# section and false-GAPs an otherwise-healthy repo (found by an independent reviewer's own pass; no
# real tag like this exists in this project yet, so it was latent, not yet triggered).
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n## [1.0.0] — 2026-01-01\n- first release\n' > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0, plus an RC tag" && git tag v1.0.0 && git tag v1.1.0-rc1 )
run "$sd" "$d" --quiet
check_status "a suffixed pre-release tag doesn't false-GAP a healthy repo -> exit 0" 0 "$STATUS"
check_absent "no reconciliation GAP from the RC tag" "$OUT" "GAP"

# a `## [x.y.z]`-shaped line inside a FENCED example (this file documents its own conventions, and an
# illustrative snippet is realistic future content) must not be misread as a real release section —
# same false-positive class check 5's BACKLOG.md scan already guards against, found here by /polish's
# own independent review when check 6 first shipped without the equivalent fence-blanking.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n## [1.0.0] — 2026-01-01\n- first release\n\nExample of how a section header looks:\n```\n## [9.9.9] — example\n- not a real release\n```\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0, plus a fenced illustrative example" && git tag v1.0.0 )
run "$sd" "$d" --quiet
check_status "a fenced-block example section isn't mistaken for a real one -> exit 0" 0 "$STATUS"
check_absent "no reconciliation GAP from the fenced example" "$OUT" "GAP"

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

# **These fixtures are the CODE leg of a doc↔code coupling (dir #157).** `docs/release-audit.md`'s
# phase 7 states the allowance's two conditions in prose, and `tests/test_release_audit_doc.sh` pins
# that prose. The conditions themselves are pinned HERE, behaviourally, rather than by grepping
# `tools/self/doctor.sh` for its expression shape. A first version of dir #157 DID grep it and was
# removed: it added no protection — deleting either conjunct already reds these fixtures (3 assertions
# for the version half, 4 for the position half, measured) — while pinning expression shape down to a
# trailing `&&`, so extracting the guard into a helper or reordering the conjuncts would red it with
# behaviour unchanged. That is a second source of truth about the code's shape, the same smell
# `_addon_label`'s header in `tools/pre-pr-gate.sh` rejects. **So if you change what the allowance
# accepts, update phase 7's prose in the same commit**; the doc drifted from the code once already,
# inside the single PR that wrote both.
#
# release-in-preparation allowance (dir #155): phase 7 cuts `## [x.y.z]` and lands it through a PR
# BEFORE the operator tags the merge commit, so the newest section is legitimately untagged for the
# life of that PR. Without this, the check reds the `self-check` CI job on the release-prep PR
# itself — found live by dir #155's own RC pass, the first release cut after this check shipped.
# Reverse-chronological order (newest first), the shape Keep a Changelog specifies and this repo uses.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] — 2026-01-02\n- cut, PR open, not tagged yet\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.1.0 ahead of its tag" && git tag v1.0.0 )
# One NON-quiet run carries all four assertions: `--quiet` suppresses only `say`, while `gap` prints
# unconditionally and the exit status is identical either way, so the absent-GAP check is just as
# strong here — and the announcement (a `say` line) is only observable without it. A second `--quiet`
# invocation would be a whole extra doctor.sh run for no added coverage, on a suite whose CI legs are
# job-capped for exactly this contention.
run "$sd" "$d"
check_status "the NEWEST section untagged (release in preparation) -> exit 0" 0 "$STATUS"
check_absent "no reconciliation GAP while the tag is still pending" "$OUT" "GAP"
check_contains "the pending section is announced, not silently tolerated" "$OUT" "cut but not tagged yet"
check_contains "and named specifically" "$OUT" "1.1.0"

# ...and the allowance is exactly one section wide: a SECOND untagged section is still drift. Both
# 1.1.0 and 1.2.0 lack tags; only the newest (1.2.0, first in file order) is exempt.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.2.0] — 2026-01-03\n- also untagged\n\n## [1.1.0] — 2026-01-02\n- untagged too\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "two untagged sections" && git tag v1.0.0 )
run "$sd" "$d" --quiet
check_status "a SECOND untagged section is still a GAP -> exit 1" 1 "$STATUS"
check_contains "names the one that isn't the newest" "$OUT" "1.1.0"
check_absent "and does not name the exempt newest one as missing a tag" "$OUT" "no matching release tag: 1.2.0"
# Discriminating assertion: the pre-allowance implementation ALSO exits 1 here and also names 1.1.0
# (its GAP lists both, `1.1.0, 1.2.0`, so even the check_absent above passes under it). Only the new
# code exempts 1.2.0 and therefore spells the untagged-newest term in the count GAP — without this,
# the two assertions above pin "not over-broad" but not "the allowance ran at all".
check_contains "the newest one is counted as pending, not as a missing section" "$OUT" "+ untagged-newest (1)"

# ...and being NEWEST BY POSITION is not enough on its own — the section's version must also sort
# above every tag. An independent high-depth review broke the position-only first draft with exactly
# this fixture: `## [0.9.0]` sitting at the top of the file while v1.0.0/v1.1.0 are tagged is a
# deleted/re-cut tag or a bad merge hoisting a stale section (the dir #115/PR #118 founding incident),
# and the position-only rule turned its two GAPs into a clean run announcing a "release in
# preparation" that is older than everything released.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [0.9.0] — 2026-01-04\n- untagged, and OLDER than every tag\n\n## [1.1.0] — 2026-01-02\n- second release\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "a stale untagged section hoisted to the top" \
  && git tag v1.0.0 && git tag v1.1.0 )
# NON-quiet, like the legit-pending fixture above and for the same reason: the announcement is a
# `say` line, which `--quiet` suppresses unconditionally — so asserting its ABSENCE under `--quiet`
# would pass against every possible implementation. Running full makes that assertion real.
run "$sd" "$d"
check_status "newest-by-position but OLDER than every tag -> still exit 1" 1 "$STATUS"
check_contains "names the stale section as missing its tag" "$OUT" "no matching release tag: 0.9.0"
check_absent "and does not excuse it as a release in preparation" "$OUT" "cut but not tagged yet"

# ...and position still matters too, independently of the version test: an untagged section BELOW a
# tagged one is the PR #118 drift shape from the other direction, and still GAPs. (Order-sensitive by
# construction — this block's fixtures are newest-first, the Keep a Changelog ordering the allowance
# assumes; the two older fixtures above are oldest-first, and reordering them would legitimately
# change their verdicts rather than expose a bug.)
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] — 2026-01-02\n- second release\n\n## [1.0.5] — 2026-01-02\n- never tagged\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "an untagged section buried below a tagged one" \
  && git tag v1.0.0 && git tag v1.1.0 )
run "$sd" "$d" --quiet
check_status "an untagged section below a tagged one -> exit 1" 1 "$STATUS"
check_contains "names the buried untagged section" "$OUT" "1.0.5"

# --- dir #156: bound the release-in-preparation allowance by commit distance -----------------------
# The two conditions above (newest heading, version above every tag) make a genuinely FORGOTTEN tag
# indistinguishable from one still pending — including a live recurrence of this check's own founding
# incident (dir #115/PR #118): delete a tag that was the topmost section's OWN, with no remaining tag
# above it, and the fixture above's exact shape results. Reproduced live during the design pass before
# any code was written (fixture D below is that reproduction). KEEL_PENDING_RELEASE_MAX_COMMITS=3 for
# A-D so a handful of `git commit --allow-empty` stand in for the shipped default of 40 (fixture F
# pins the real default separately, without manufacturing 41 commits).

# A: legitimately pending, distance 2, bound 3 -> still exempt. NON-quiet: the announcement is a `say`
# line, invisible under --quiet, so a presence assertion needs the full run.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] — 2026-01-02\n- cut, PR open, not tagged yet\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.1.0 ahead of its tag" && git tag v1.0.0 \
  && git commit -q --allow-empty -m "empty 1" && git commit -q --allow-empty -m "empty 2" )
KEEL_PENDING_RELEASE_MAX_COMMITS=3 run "$sd" "$d"
check_status "A: distance 2 within bound 3 -> exit 0" 0 "$STATUS"
check_absent "A: no reconciliation GAP while still within the bound" "$OUT" "GAP"
check_contains "A: pending announcement present" "$OUT" "cut but not tagged yet"
check_contains "A: names the version" "$OUT" "1.1.0"

# B: same shape, distance 4, bound 3 -> the tag was forgotten, not merely pending. NON-quiet, same
# reason as A — `check_absent` on the old announcement phrase needs it to be observable at all.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] — 2026-01-02\n- cut, then the tag was forgotten\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.1.0" && git tag v1.0.0 \
  && for i in 1 2 3 4; do git commit -q --allow-empty -m "empty $i"; done )
KEEL_PENDING_RELEASE_MAX_COMMITS=3 run "$sd" "$d"
check_status "B: distance 4 past bound 3 -> exit 1" 1 "$STATUS"
check_contains "B: dedicated GAP names the version" "$OUT" "'## [1.1.0]' was cut"
check_contains "B: dedicated GAP names the bound" "$OUT" "bound: 3"
check_absent "B: no longer excused as a release in preparation" "$OUT" "cut but not tagged yet"

# C: distance exactly AT the bound -> still exempt. Pins `>`, not `>=` (a boundary off-by-one would
# red this fixture alone, not A/B/D).
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] — 2026-01-02\n- cut, right at the bound\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.1.0" && git tag v1.0.0 \
  && for i in 1 2 3; do git commit -q --allow-empty -m "empty $i"; done )
KEEL_PENDING_RELEASE_MAX_COMMITS=3 run "$sd" "$d" --quiet
check_status "C: distance exactly at the bound (3) stays exempt -> exit 0 (pins > not >=)" 0 "$STATUS"

# D: THE residual-case-2 fixture — a deleted tag that was the topmost section's OWN, no remaining tag
# above it, reproduced live during dir #156's design pass before any code existed. Proves the founding
# incident (dir #115/PR #118) is closed: without the bound, this reads as a clean "release in
# preparation" forever (byte-identical to the real thing by construction). NON-quiet, same reason as
# A/B.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] — 2026-01-01\n- cut and tagged, then the tag was deleted\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.1.0" && git tag v1.1.0 && git tag -d v1.1.0 >/dev/null \
  && for i in 1 2 3 4; do git commit -q --allow-empty -m "empty $i"; done )
KEEL_PENDING_RELEASE_MAX_COMMITS=3 run "$sd" "$d"
check_status "D: founding-incident class (dir #115/PR #118) is closed -> exit 1" 1 "$STATUS"
check_contains "D: dedicated GAP fires on the deleted-topmost-tag shape" "$OUT" "'## [1.1.0]' was cut"
check_absent "D: no longer waved through as a release in preparation" "$OUT" "cut but not tagged yet"

# E: the bound is UNRESOLVABLE — a section cut in the working tree but never committed, so the exact
# heading text never appears anywhere in CHANGELOG.md's tracked history and the pickaxe genuinely
# returns empty (verified live during the design pass — a bare non-existent string was already known
# to return empty; an uncommitted file was the TO VERIFY case). Fails OPEN: keep the allowance, say so.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] — 2026-01-02\n- cut but never committed\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
run "$sd" "$d"
check_status "E: bound unresolvable (uncommitted section) -> exit 0, allowance held" 0 "$STATUS"
check_contains "E: announcement says the bound was not computed" "$OUT" "bound not computed"
check_contains "E: still announced as pending, not silently tolerated" "$OUT" "cut but not tagged yet"

# F: default-value pin — extract the shipped default (40) out of tools/self/doctor.sh itself, the same
# eval-out-of-source idiom tests/test_keel_impact.sh:606-618 uses for _LEDGER_COLS, rather than
# manufacturing 41 real commits just to watch the default kick in.
default_line="$(grep -nF 'pending_max_commits="${KEEL_PENDING_RELEASE_MAX_COMMITS:-40}"' "$sd" | head -1 | cut -d: -f1)"
if [ -z "$default_line" ]; then
  fail "F: KEEL_PENDING_RELEASE_MAX_COMMITS default located in tools/self/doctor.sh" \
    "no line matching the expected assignment found in $sd"
else
  unset KEEL_PENDING_RELEASE_MAX_COMMITS
  eval "$(sed -n "${default_line}p" "$sd")"
  # shellcheck disable=SC2154  # pending_max_commits is assigned by the eval just above, not statically
  if [ "$pending_max_commits" = 40 ]; then
    pass "F: shipped default for KEEL_PENDING_RELEASE_MAX_COMMITS is 40"
  else
    fail "F: shipped default for KEEL_PENDING_RELEASE_MAX_COMMITS is 40" "found: $pending_max_commits"
  fi
fi

# G: a version number CUT, then REVERTED (folded back into [Unreleased]), then LATER genuinely re-cut
# fresh with the SAME number (found by an operator-run `/code-review high` pass on this ticket,
# reproduced live). Locks in TWO fixes together: (1) `_pending_release_intro_commit` must resolve the
# FRESH re-introduction, not the stale original cut — an earlier `tail -1` version measured distance
# from the wrong, much older commit and would false-GAP this fixture; (2) resolving it via `git log -S
# ... | head -1` (an earlier version of the fix for (1)) reproducibly CRASHED THE WHOLE SCRIPT under
# `set -o pipefail` (`head` closing its read end early SIGPIPEs `git log`, and pipefail turns that into
# a script-ending failure) — `-n 1` on the git invocation itself has no such pipe to break. Non-quiet:
# the announcement's distance figure is the whole point of this fixture.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] — 2026-01-02\n- cut\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.1.0" && git tag v1.0.0 )
printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0] — 2026-01-01\n- first release\n' > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "revert 1.1.0, folded back into Unreleased" \
  && for i in 1 2; do git commit -q --allow-empty -m "filler $i"; done )
printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] — 2026-01-08\n- re-cut fresh\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "re-cut 1.1.0 fresh" )
KEEL_PENDING_RELEASE_MAX_COMMITS=3 run "$sd" "$d"
check_status "G: script does not crash (SIGPIPE-under-pipefail regression) -> exit 0" 0 "$STATUS"
check_absent "G: no reconciliation GAP for the freshly re-cut section" "$OUT" "GAP"
check_contains "G: distance measured from the FRESH re-cut (0 commits), not the stale original" "$OUT" \
  "0 commit(s) since cut"
check_contains "G: pending announcement present" "$OUT" "cut but not tagged yet"

# H (dir #194): `git log -S` has no concept of "inside a fence" — a commit that only adds a FENCED
# example reusing the SAME version-heading text must not be mistaken for the section's real
# introduction. Built from the ticket's own described shape: the real section is cut and left pending
# long enough to exceed the bound (would GAP), then — much closer to HEAD — a fenced example
# illustrating the CHANGELOG.md convention reuses the same version number. A naive "newest pickaxe hit"
# resolution would measure distance from the decoy (small, still exempt) instead of the real cut
# (large, past the bound) and silently hide a genuinely forgotten tag.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] — 2026-01-02\n- cut, decoy-fence regression\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.1.0" && git tag v1.0.0 \
  && for i in 1 2 3 4 5; do git commit -q --allow-empty -m "empty $i"; done )
printf '\n## Conventions\n\n```\n## [1.1.0] — YYYY-MM-DD\n- illustrative example entry\n```\n' >> "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "document the heading convention with a fenced example" \
  && git commit -q --allow-empty -m "empty 6" && git commit -q --allow-empty -m "empty 7" )
KEEL_PENDING_RELEASE_MAX_COMMITS=3 run "$sd" "$d"
check_status "H: a fenced decoy is not mistaken for the real intro -> exit 1 (forgotten, not pending)" 1 "$STATUS"
check_contains "H: dedicated GAP fires, measured from the real (older) intro, not the decoy" "$OUT" \
  "'## [1.1.0]' was cut 8 commits ago"
check_absent "H: no longer waved through as a release in preparation" "$OUT" "cut but not tagged yet"

# I (dir #213): an unborn HEAD (no commits at all yet) must not silently abort the whole doctor.sh run.
# `_pending_release_intro_commit`'s `git log -S` was the loop's FIRST git call reachable with zero
# commits; on an unborn HEAD `git log` exits 128 rather than printing nothing, which — bare inside a
# `$( )` assignment, its `2>/dev/null` swallowing the `fatal:` line — used to abort the entire run
# under `set -euo pipefail` with no GAP, no WARN, no summary at all (A/B-proven live against the
# unguarded code, delta audit S5/S8). CHANGELOG.md is read from the working tree directly (fence-blank
# scans don't need history), so a heading is visible even with nothing committed yet.
d="$(new_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] — 2026-01-01\n- cut before any commit exists\n' \
  > "$d/CHANGELOG.md"
run "$sd" "$d"
check_status "I: an unborn HEAD does not crash the whole run" 1 "$STATUS"
check_contains "I: the bound degrades to unresolvable rather than aborting" "$OUT" "bound not computed"
check_contains "I: still announced as pending, not silently swallowed" "$OUT" "cut but not tagged yet"
# the run must reach the orchestrated-checks section, several checks after the reconciliation one that
# used to abort it — proof it did not silently stop mid-run (the pre-fix crash produced NO output past
# "slash-command references", well before this point)
check_contains "I: the run reaches the orchestrated checks, proving it did not abort mid-run" "$OUT" \
  "orchestrated checks"

# J (dir #195): the dead-slash-command-reference scan's `grep -F ... | head -1 | cut -d: -f1` risked the
# same SIGPIPE-under-`set -o pipefail` shape dir #156 fixed elsewhere in this file — `head` can close
# its read end before `grep` finishes writing a long match list, and under `pipefail` that non-zero
# exit status becomes the WHOLE doctor.sh run aborting. A single adopter-facing doc citing one dead
# slash command thousands of times (all sharing one raw_hits scan) reliably overflows the pipe buffer
# before `head` reads its one line and closes — reproduced live (exit 141, SIGPIPE) against the
# unguarded `| head -1`, and again (still exit 141) against a `grep -m 1` fix piped from a live
# `printf` writer (the early stdin-close just moved the SIGPIPE one stage left) — clean only once
# `grep -m 1 ... <<< "$raw_hits"` reads from a here-string instead of a piped writer process.
d="$(mk_clean_repo)"
awk 'BEGIN { for (i = 1; i <= 20000; i++) printf "See `/ghostcmd` for details, line %d.\n", i }' \
  > "$d/IDEAS.md"
( cd "$d" && git add -A && git commit -qm "20000 citations of one dead slash command" )
run "$sd" "$d" --quiet
check_status "J: a huge single-name citation count does not SIGPIPE the whole run -> exit 1" 1 "$STATUS"
check_contains "J: the dead-reference GAP still fires normally" "$OUT" \
  "slash-command reference '/ghostcmd' in IDEAS.md has no $fake_ghost_md"

# K (dir #194, blocking finding from an independent cross-model review of this very ticket): the
# fence-aware presence check inside `_pending_release_intro_commit` first shipped piping
# `blank_fenced_blocks <(...) | grep -qF ...` directly — `grep -q` exits at its first match, and on a
# CHANGELOG.md whose content past the heading exceeds the pipe buffer (~64KB), that early close SIGPIPEs
# the awk writer, and under `set -o pipefail` the pipeline reads as "heading NOT present" even when it
# plainly is (reproduced live against this repo's own 300KB+ CHANGELOG.md before the fix: `PIPESTATUS`
# 141, the presence check silently false). The fix captures `blank_fenced_blocks`'s output into a
# variable first, then greps a `<<<` here-string — no live writer left for grep to signal. This fixture
# pads the newest, untagged, pending section's CHANGELOG.md well past the pipe-buffer threshold so a
# reintroduced piped-grep-q bug would misfire here even though every OTHER fixture in this file (all a
# few hundred bytes) stays far too small to trigger it.
d="$(mk_clean_repo)"
{
  printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] — 2026-01-02\n- cut, large-file regression\n\n'
  awk 'BEGIN { for (i = 1; i <= 3000; i++) printf "padding line %d to push this file past the pipe buffer.\n", i }'
  printf '\n## [1.0.0] — 2026-01-01\n- first release\n'
} > "$d/CHANGELOG.md"
[ "$(wc -c < "$d/CHANGELOG.md")" -gt 65536 ] || fail "K: fixture setup" "CHANGELOG.md padding is not actually past the pipe-buffer threshold"
( cd "$d" && git add -A && git commit -qm "cut 1.1.0" && git tag v1.0.0 \
  && for i in 1 2 3 4 5; do git commit -q --allow-empty -m "empty $i"; done )
KEEL_PENDING_RELEASE_MAX_COMMITS=3 run "$sd" "$d"
check_status "K: a large CHANGELOG.md doesn't false-negative the presence check -> exit 1 (forgotten tag)" 1 "$STATUS"
check_contains "K: dedicated GAP fires, correctly resolving the intro commit on a large file" "$OUT" \
  "'## [1.1.0]' was cut 5 commits ago"
check_absent "K: not silently waved through as unresolvable" "$OUT" "bound not computed"
check_absent "K: not silently waved through as a release in preparation" "$OUT" "cut but not tagged yet"

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

# a DUPLICATED `[Unreleased]` heading evades the general count invariant entirely: both sides of the
# comparison (total sections, and the Unreleased count baked into "expected") increment together on
# the extra copy, staying balanced (found by an independent reviewer's own pass, empirically
# reproduced against the pre-fix code — no GAP fired). Needs its own explicit "at most 1" check.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n## [Unreleased]\n- duplicate, different accident\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0, duplicate Unreleased heading" && git tag v1.0.0 )
run "$sd" "$d" --quiet
check_status "a duplicated [Unreleased] heading -> exit 1" 1 "$STATUS"
check_contains "names the Unreleased-count mismatch" "$OUT" "'## [Unreleased]' headings, expected at most 1"

# ZERO bracketed `[Unreleased]` headings (this repo's own base sandbox fixture is exactly this shape
# — a plain "## Unreleased" with no brackets) must NOT false-GAP: "at most 1", not "exactly 1" — a
# CHANGELOG.md that never adopted the bracket convention at all is a separate, softer question this
# check takes no position on; only a genuine duplicate is unambiguous enough to flag.
d="$(mk_clean_repo)"
run "$sd" "$d" --quiet
check_status "zero bracketed Unreleased headings doesn't false-GAP -> exit 0" 0 "$STATUS"
check_absent "no reconciliation GAP from the missing bracket convention" "$OUT" "GAP"

# a legitimate, non-version `## [...]` heading (this project's CHANGELOG.md never uses one, but
# nothing stops a future entry from doing so) must not inflate the section count and false-GAP an
# otherwise perfectly healthy repo (found by an independent reviewer's own pass, empirically
# reproduced against the pre-fix code — a bare `grep -cE '^## \['` counted it, with no tag or
# Unreleased bump to balance it against).
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n## [Deprecated]\n- some non-version bracket heading\n\n## [1.0.0] — 2026-01-01\n- first release\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0, plus a non-version bracket heading" && git tag v1.0.0 )
run "$sd" "$d" --quiet
check_status "a non-version bracket heading doesn't false-GAP a healthy repo -> exit 0" 0 "$STATUS"
check_absent "no reconciliation GAP from the non-version heading" "$OUT" "GAP"

# no CHANGELOG.md at all -> clean skip, not a crash or a GAP
d="$(mk_clean_repo)"
rm "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "no changelog" )
run "$sd" "$d" --quiet
check_status "no CHANGELOG.md at all -> exit 0" 0 "$STATUS"

# an UNREADABLE (but present) CHANGELOG.md must not abort the whole doctor.sh run either — the same
# `-r` guard check 5's BACKLOG.md read already carries, which this check's condition was found to be
# missing (found by /code-review medium's own line-by-line pass: it only inherited the `-f` half).
# root always reads regardless of chmod, so this only proves anything as non-root (same guard this
# project's own CLAUDE.md documents for the identical Alpine/root trap elsewhere).
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  d="$(mk_clean_repo)"
  printf '# Changelog\n\n## [Unreleased]\n- init\n\n## [1.0.0] — 2026-01-01\n- first release\n' > "$d/CHANGELOG.md"
  ( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
  chmod 000 "$d/CHANGELOG.md"
  run "$sd" "$d" --quiet
  check_status "an unreadable CHANGELOG.md doesn't abort the whole run -> exit 0" 0 "$STATUS"
  chmod 644 "$d/CHANGELOG.md"
fi

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

# --- 9. commit dir #N tickets vs CHANGELOG.md [Unreleased] section (dir #237) -----------------------
# A cut-and-tagged v1.0.0 section, kept in every fixture below, so check 6's own tag-reconciliation
# GAP stays clean and only THIS check's finding shows through — isolating the assertion.
ct_v1_section='## [1.0.0] — 2026-01-01
- first release'

# A synthetic tools-only diff carrying a `dir #N` in its commit message, with the [Unreleased]
# section silent about that ticket, must fire — the ticket's own acceptance bar. WARN, never a GAP.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #900 tweak the widget tool" )
run "$sd" "$d" --quiet
check_status "an unreferenced ticket in a commit message is advisory only -> exit 0" 0 "$STATUS"
check_contains "flags the missing ticket" "$OUT" "dir #900"
check_contains "names the convention's remedy" "$OUT" "absent from CHANGELOG.md's [Unreleased] section"

# the same ticket IS referenced in [Unreleased] -> silent.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- dir #900: tweak the widget tool\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #900 tweak the widget tool" )
run "$sd" "$d" --quiet
check_absent "a ticket referenced in [Unreleased] is not flagged" "$OUT" "dir #900"
check_status "still exit 0" 0 "$STATUS"

# PR #244's miss shape: the check must ENUMERATE, not sample the tail — a later, UNRELATED
# CHANGELOG.md commit landing after the miss must not clear it (check 4's timestamp signal would
# have gone quiet here; this check must not).
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #244 change commands/polish.md-equivalent content" )
printf '# Changelog\n\n## [Unreleased]\n- dir #901: unrelated bookkeeping\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "dir #901 unrelated CHANGELOG bookkeeping" )
run "$sd" "$d" --quiet
check_contains "a later unrelated CHANGELOG.md commit doesn't clear an earlier real miss" "$OUT" "dir #244"

# PR #249's miss shape: a PR that DOES touch CHANGELOG.md, but for a DIFFERENT ticket than its own,
# still trips it — per-TICKET, not per-file.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
printf '# Changelog\n\n## [Unreleased]\n- dir #245: some passenger ticket\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "dir #249 closes its own ticket but only writes dir #245's entry" )
run "$sd" "$d" --quiet
check_contains "a PR touching CHANGELOG.md for a different ticket still trips it" "$OUT" "dir #249"

# a ticket already released in an earlier version section, cited only there (not re-entered under
# [Unreleased]) must not vouch for a DIFFERENT, still-open ticket with the same convention text.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n## [1.0.0] — 2026-01-01\n- dir #700: shipped already\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #701 a new, still-open ticket" )
run "$sd" "$d" --quiet
check_contains "an already-released ticket's citation doesn't vouch for a different open one" "$OUT" "dir #701"
check_absent "the released ticket itself isn't re-flagged" "$OUT" "dir #700"

# the SAME ticket, cited only in an already-tagged section, must NOT vouch for a fresh reference to
# ITSELF in a later, un-entered commit — the exact case the heading-version parse bug (found by an
# operator-run /code-review medium pass) let slip through: `gsub(/^## \[|\]$/, "", ver)` only
# stripped the leading bracket (real headings carry a trailing " — DATE", so `\]$` never matched),
# leaving `grabbing` stuck on past every already-tagged section down to EOF — so an already-released
# ticket's own citation leaked into "unreleased" and silently vouched for its own re-citation. Every
# fixture above this one only ever referenced a ticket ONCE in the whole file, so the leak never
# changed an assertion's outcome; this one is the discriminating case.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n## [1.0.0] — 2026-01-01\n- dir #700: shipped already\n' \
  > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #700 a follow-up change, no fresh [Unreleased] entry" )
run "$sd" "$d" --quiet
check_contains "a re-cited already-released ticket is still flagged, not vouched for by its own old entry" "$OUT" "dir #700"

# a commit-message dir #N that is only test/comment-shaped work stays a WARN, not a GAP — exit code
# must stay 0 even with a miss reported (the ticket's own advisory-only acceptance bar).
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #902 test-only change, no entry needed" )
run "$sd" "$d" --quiet
check_status "a missing ticket stays advisory (WARN), never a hard GAP/deny -> exit 0" 0 "$STATUS"

# A release cut BEFORE the tag is placed (the operator's own action, per the git rails — same window
# check 6's "release in preparation" allowance above covers): /wrap moves every ticket out of
# [Unreleased] into a fresh, still-untagged `## [x.y.z]` section. Bounding this check to [Unreleased]
# alone would false-positive on every ticket in the wave on the very PR that files them correctly
# (found live by a cross-model second-opinion review, dir #237) — the pending section must count too.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #950 change entering the pending release" )
printf '# Changelog\n\n## [Unreleased]\n\n## [1.1.0] — 2026-02-01\n- dir #950: change entering the pending release\n\n%s\n' \
  "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.1.0 (not yet tagged)" )
run "$sd" "$d" --quiet
check_absent "a ticket filed under a pending, not-yet-tagged section is not flagged" "$OUT" "dir #950"
check_status "still exit 0" 0 "$STATUS"

# no release tag at all (first-ever release): widens to the whole history rather than skipping.
d="$(new_repo)"
mkdir -p "$d/commands" "$d/tools" "$d/tests"
stub_orchestrated_tests "$d"
printf '# Changelog\n\n## [Unreleased]\n- init\n' > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "dir #903 no prior release tag yet" )
run "$sd" "$d" --quiet
check_contains "no prior release tag widens to the whole history" "$OUT" "dir #903"
check_contains "names the repo's start, not a tag, as the range" "$OUT" "since the repo's start"

# dir #273 gap 2: a commit message's shorthand ticket list ("dir #910, #911, #912" — one `dir` prefix,
# then bare `#N` for the rest, PR #267's own real shape) must not defeat the extraction. Every ticket
# in the list is genuinely absent from [Unreleased] here (mutation-proof: red before the fix, since
# `grep -oE 'dir #[0-9]+'` alone only ever surfaced #910 and left #911/#912 outright invisible to the
# candidate set, not merely unflagged).
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #910, #911, #912 shorthand ticket list" )
run "$sd" "$d" --quiet
check_contains "shorthand list: first ticket flagged" "$OUT" "dir #910"
check_contains "shorthand list: second (bare #N) ticket flagged too" "$OUT" "dir #911"
check_contains "shorthand list: third (bare #N) ticket flagged too" "$OUT" "dir #912"

# same shorthand commit list, but all three are properly entered under [Unreleased] (spelled out in
# full there, as convention requires) -> none flagged. Proves the tightened extraction doesn't just
# widen the candidate set, it also matches correctly against a fully-spelled [Unreleased] body.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- dir #910, dir #911, dir #912: shorthand ticket list\n\n%s\n' \
  "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #910, #911, #912 shorthand ticket list" )
run "$sd" "$d" --quiet
check_absent "shorthand list, all three entered: none flagged" "$OUT" "absent from CHANGELOG.md's [Unreleased] section"
check_status "still exit 0" 0 "$STATUS"

# dir #274: the same class of gap dir #273 closed for comma/whitespace lists, but for the four
# remaining real-precedent shapes — "and", ";", "/" (all three separators between explicit numbers,
# so every ticket resolves) and a numeric range (`#N-M`, an EXPANSION: `dir #104-107` names four
# tickets while writing only two numbers, so a fix that just pulled the two endpoints would silently
# lose the middle — worse than today's visible drop, because it would look complete). Mutation-proved
# per shape, not one fixture standing in for all four (a single shared fixture is exactly the
# one-layer-up version of the defect dir #274 exists to close).
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #920 and #921 two-way and-list" )
run "$sd" "$d" --quiet
check_contains "\"and\"-list: first ticket flagged" "$OUT" "dir #920"
check_contains "\"and\"-list: second ticket flagged too" "$OUT" "dir #921"

d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #922; #923 semicolon-separated list" )
run "$sd" "$d" --quiet
check_contains "semicolon-list: first ticket flagged" "$OUT" "dir #922"
check_contains "semicolon-list: second (bare #N) ticket flagged too" "$OUT" "dir #923"

# real precedent for this exact shape: commit 1515d7a's own title, "...dir #208/#211/#212...".
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #924/#925/#926 slash-separated list" )
run "$sd" "$d" --quiet
check_contains "slash-list: first ticket flagged" "$OUT" "dir #924"
check_contains "slash-list: second ticket flagged too" "$OUT" "dir #925"
check_contains "slash-list: third ticket flagged too" "$OUT" "dir #926"

# range shape: real precedent (f4109e72 "dir #100-103", 21e984bfd9a "dir #104-107"). Every ticket IN
# the range must surface, not just its two written endpoints — the middle ticket (#928) is the
# discriminating assertion an endpoints-only fix would still pass.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #927-929 batch range close" )
run "$sd" "$d" --quiet
check_contains "range: first (written) endpoint flagged" "$OUT" "dir #927"
check_contains "range: middle ticket flagged (not just the two written endpoints)" "$OUT" "dir #928"
check_contains "range: second (written) endpoint flagged" "$OUT" "dir #929"

# wrapped shorthand list: a shorthand list split across a commit-message line break (a trailing
# comma right before the `\n`) must not defeat extraction the same way a same-line comma list
# doesn't — grep is inherently line-based, so this needs an explicit line-join first.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "$(printf 'dir #930,\n#931 wrapped shorthand list')" )
run "$sd" "$d" --quiet
check_contains "line-wrapped list: first ticket flagged" "$OUT" "dir #930"
check_contains "line-wrapped list: second (wrapped) ticket flagged too" "$OUT" "dir #931"

# over-matching guard: a bare `#N` that follows a `dir #N` reference through ordinary prose (not a
# comma/semicolon/slash/whitespace-only run) must NOT be swept in as a continuation — an unrelated PR
# or issue number mentioned in the same commit message stays uncredited, not invented as a ticket.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- dir #932: fixes bug\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #932 fixes bug, see PR #933 for context" )
run "$sd" "$d" --quiet
check_absent "an unrelated PR number in prose isn't swept in as a ticket" "$OUT" "dir #933"

# malformed-range edge cases (a peer review of this same fix, dir #274): a typo'd/reversed range
# ("#107-104") must not silently drop both tickets by looping lo..hi backwards into nothing — treated
# as two bare references instead, both surface.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #934-933 typo'd reversed range" )
run "$sd" "$d" --quiet
check_contains "reversed range: first written endpoint still flagged" "$OUT" "dir #934"
check_contains "reversed range: second written endpoint still flagged" "$OUT" "dir #933"

# an absurdly wide range (over the 500-ticket cap) must not silently truncate to a single endpoint —
# that would look complete while dropping every other ticket in the span, the exact class of defect
# this whole chain exists to kill. It must surface loudly instead: a deliberately unmatchable marker
# line that always shows as "missing" in the WARN, prompting a human to look.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #1-99999 absurdly wide range" )
run "$sd" "$d" --quiet
check_contains "over-cap range surfaces loudly rather than silently truncating" "$OUT" "range too large to expand"

# a spaced hyphen after a ticket number is ordinary prose, not a range — must not misparse into a
# wild expansion or a parse failure.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- dir #935: fixed the extraction\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "dir #935 - fixed the extraction" )
run "$sd" "$d" --quiet
check_status "a spaced hyphen after a ticket number doesn't crash the check" 0 "$STATUS"
check_absent "a spaced hyphen after a ticket number isn't misread as a range" "$OUT" "range too large"

# cross-commit stitching (found live by an independent review pass on this same fix, dir #274):
# `git log --format=%B` inserts a BLANK line between commit bodies, not a hard reset by itself — a
# buffered trailing-comma line that merely absorbs the blank line (still ending in ", " after the
# merge) rides straight through it and stitches onto the NEXT, unrelated commit's leading token. Two
# real commits, oldest first: an older one whose message starts with a bare "#941" (no "dir " prefix,
# so on its own it is not a ticket citation at all), then a newer one ending in a genuine trailing-
# comma ticket citation. Without the blank-line flush, "dir #940," would ride through the blank
# separator and glue onto "#941", fabricating a "dir #941" citation nothing in the repo ever made.
d="$(mk_clean_repo)"
printf '# Changelog\n\n## [Unreleased]\n- init\n\n%s\n' "$ct_v1_section" > "$d/CHANGELOG.md"
( cd "$d" && git add -A && git commit -qm "cut 1.0.0" && git tag v1.0.0 )
( cd "$d" && git commit -q --allow-empty -m "$(printf '#941 an older, unrelated commit starting with a bare number')" )
{ printf '#!/usr/bin/env bash\necho tool\n'; } >> "$d/$fake_widget"
( cd "$d" && git add -A && git commit -qm "$(printf 'dir #940 fixes bug,')" )
run "$sd" "$d" --quiet
check_contains "cross-commit: the real trailing-comma ticket is still flagged" "$OUT" "dir #940"
check_absent "cross-commit: an unrelated older commit's bare number isn't fabricated into a ticket" "$OUT" "dir #941"

summary
