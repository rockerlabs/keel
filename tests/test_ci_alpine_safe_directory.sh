#!/usr/bin/env bash
# test_ci_alpine_safe_directory.sh (dir #246) — .github/workflows/ci.yml's alpine leg needs
# `git config --system --add safe.directory` ordered before `tests/run.sh`, or the leg's container-root
# reader hits "dubious ownership" on the bind-mounted checkout (project CLAUDE.md's third Alpine trap;
# dir #191). Nothing else pins that one line: it's YAML, so shellcheck never reaches it, prose-drift
# doesn't read workflow files, and doctor.sh's shellcheck mirror covers tracked *scripts*, not CI config
# (dir #246's own finding — reverting `--system` to `--global`, or reordering it after `tests/run.sh`,
# reds nothing locally). `--system`, not `--global`: `tests/lib.sh` sandboxes `GIT_CONFIG_GLOBAL` per
# test file (see its own fresh_home_env-style setup), which shadows a `--global` write outright — a
# "fix" that reverts to `--global` must fail this guard, not just fail to help.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

ci="$REPO_ROOT/.github/workflows/ci.yml"
check_file "ci.yml exists" "$ci"

# extract_alpine_step FILE — the alpine job's own step text (from its "Run test suite" step name up
# to, but excluding, the next job header), so a match elsewhere in the file (e.g. the plain
# ubuntu/macos job's own, safe.directory-free "Run test suite" step) can't satisfy this guard by
# accident. Two anchors, both structural rather than literal, per an independent /code-review pass:
# the start is anchored to the step-key position (6-space indent + `- name:`), not just the name text
# anywhere on a line, so a future comment that happens to quote this step's name in prose can't start
# capture early; the end is any next job header (2-space indent + `word:`), not a hardcoded `shellcheck:`
# literal, so inserting or renaming a job between `alpine:` and its current neighbor can't silently
# balloon the capture into unrelated job content. The end pattern is checked BEFORE the print rule, so
# the terminator line itself is excluded from the captured text (awk evaluates every pattern-action
# pair per record; ordering here is what keeps the boundary exclusive).
extract_alpine_step() {
  awk '
    /^      - name: Run test suite on Alpine\/busybox/ { f=1 }
    f && /^  [A-Za-z0-9_-]+:/ { exit }
    f { print }
  ' "$1"
}

# assert_alpine_guard TEXT — 0 (pass) only if TEXT carries the `--system` safe.directory write AND
# runs it, joined via `&&`, before `bash tests/run.sh`. Every condition below is load-bearing (a
# bare `--system`-presence check was removed here per an independent /code-review pass, once proven
# fully subsumed by the ordering check's own presence test on its narrower `before` prefix — a
# broader presence check can never be the deciding branch once the narrower one already runs).
# The `&&`/ordering pair is required explicitly (not just the prefix split alone): a
# `bash tests/run.sh`-less TEXT would otherwise make `${text%%bash tests/run.sh*}` return the whole
# string unchanged, silently degrading the ordering half into a duplicate of a presence check (found
# live by an independent cross-model second-opinion review); and requiring the literal
# `&& bash tests/run.sh` adjacency (not just "somewhere before") is what catches a `||`-joined write —
# `git config` almost always succeeds, so a `||` would silently short-circuit `bash tests/run.sh` out
# of the pipeline while still leaving both substrings present in order (found by an independent
# /code-review pass). Ordering via string-prefix, not just two greps, so a fixture that reorders the
# `&&`-chained one-liner (dir #246's own reproduction of the reds-nothing-locally failure mode) is
# caught, not just a fixture that removes the line outright. The explicit `--global` rejection below
# is the one condition NOT implied by the others — see the `stray_global` fixture, its dedicated
# proof — belt-and-suspenders against a stale `--global` write left alongside a correctly-added
# `--system` one, which the ordering check alone would not catch.
assert_alpine_guard() {
  local text="$1" before
  case "$text" in
    *'--global --add safe.directory'*) return 1 ;;
  esac
  case "$text" in
    *'&& bash tests/run.sh'*) : ;;
    *) return 1 ;;
  esac
  before="${text%%bash tests/run.sh*}"
  case "$before" in
    *'git config --system --add safe.directory'*) return 0 ;;
    *) return 1 ;;
  esac
}

# expect_guard_rejects FIXTURE LABEL DETAIL — mutation-proof idiom shared by the three fixture checks
# below (test_doc_figures.sh's local assert_* helpers are the repo's own precedent for factoring this
# out, per an independent /code-review pass): assert_alpine_guard must REJECT FIXTURE, or the guard
# itself is broken, not just the file under test.
expect_guard_rejects() {
  local fixture="$1" label="$2" detail="$3"
  if assert_alpine_guard "$fixture"; then
    fail "$label" "$detail"
  else
    pass "$label"
  fi
}

real_step="$(extract_alpine_step "$ci")"
if [ -z "$real_step" ]; then
  fail "alpine job's 'Run test suite on Alpine/busybox' step found in ci.yml" "step text was empty — job renamed or removed?"
else
  pass "alpine job's 'Run test suite on Alpine/busybox' step found in ci.yml"
fi

if assert_alpine_guard "$real_step"; then
  pass "ci.yml: alpine leg runs --system safe.directory before tests/run.sh"
else
  fail "ci.yml: alpine leg runs --system safe.directory before tests/run.sh" \
    "expected 'git config --system --add safe.directory' ordered before 'bash tests/run.sh' in the alpine step"
fi

# --- mutation-proof the guard itself (dir #242's lesson: a coverage check that can't fail is not one) --
# Skipped whenever real_step is empty (step renamed/removed, already flagged above) — building
# fixtures from an empty string would otherwise add spurious, misleading failures on top of the real
# one (found live by an independent cross-model second-opinion review).
if [ -n "$real_step" ]; then
  # config_call is EXTRACTED from real_step, not hand-typed, so every fixture below stays derived —
  # a hand-typed copy would silently test stale prose the moment ci.yml's exact wording changes (a
  # hand-typed copy is exactly the kind of copy-paste-with-variation this repo's own /simplify pass
  # flags elsewhere; an earlier version of this file hand-typed this one literal, missed by the same
  # review that first asked for fixtures to be derived).
  config_call="$(printf '%s' "$real_step" | grep -oE 'git config --system --add safe\.directory "[^"]*"')"

  # The regex above assumes double-quoted safe.directory (ci.yml's actual style, line 59). If that
  # style ever changes, extraction yields empty and every fixture built from it would otherwise fail
  # for the wrong reason — misleadingly blaming the guard rather than naming the real cause (found
  # live by an independent cross-model second-opinion review).
  if [ -z "$config_call" ]; then
    fail "extracted the safe.directory config-call literal from real_step" \
      "grep found no 'git config --system --add safe.directory \"...\"' in real_step — did ci.yml's quoting style change?"
  else
    reverted="${real_step//git config --system --add safe.directory/git config --global --add safe.directory}"
    expect_guard_rejects "$reverted" "guard catches a --system -> --global revert" \
      "guard passed a fixture with --global instead of --system"

    missing="${real_step//"$config_call" && /}"
    expect_guard_rejects "$missing" "guard catches the safe.directory write missing entirely" \
      "guard passed a fixture with no safe.directory write at all"

    # Move the write from before `bash tests/run.sh` to right after it, splitting $missing on that
    # anchor rather than assuming a trailing quote to strip and re-append — works the same whether or
    # not real_step's tail happens to be a closing quote.
    before_run="${missing%%bash tests/run.sh*}"
    after_run="${missing#*bash tests/run.sh}"
    reordered="${before_run}bash tests/run.sh && ${config_call}${after_run}"
    expect_guard_rejects "$reordered" "guard catches safe.directory moved after tests/run.sh" \
      "guard passed a fixture with the write reordered after the test run"

    # A stray --global write left in place ALONGSIDE a correctly-added --system one (e.g. a half-done
    # migration) is the one case the explicit --global rejection exists for — the ordering check alone
    # would pass this, since the --system write is still present and still correctly ordered.
    stray_global_write="git config --global --add safe.directory \"*\" && ${config_call}"
    stray_global="${real_step//"$config_call"/$stray_global_write}"
    expect_guard_rejects "$stray_global" "guard catches a stray --global write left alongside a correct --system one" \
      "guard passed a fixture with both a stale --global write and a correctly-ordered --system write"

    # The `&& bash tests/run.sh` adjacency check has no fixture of its own without this one — every
    # OTHER fixture above happens to get caught by an earlier check first (reverted/stray_global by
    # the --global/--system checks, missing/reordered by the ordering split), so removing the
    # adjacency check entirely would leave this file's own mutation-proof suite green. This fixture
    # isolates it: same write, same position, `||` instead of `&&`.
    or_joined="${real_step//"$config_call" && /$config_call || }"
    expect_guard_rejects "$or_joined" "guard catches a ||-joined write short-circuiting the test run" \
      "guard passed a fixture where || would skip bash tests/run.sh entirely"
  fi
fi

summary
