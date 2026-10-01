#!/usr/bin/env bash
# test_git_env_guard.sh — dir #647: a keel script that names a repository itself (an argument, a hook
# payload's cwd, its own checkout, a scratch fixture) still runs git against whatever an inherited
# GIT_DIR points at. The cure is one inline line at the top of every git-reaching script — byte-identical
# to the unset line in tools/lib/repo-arg-guard.sh — and THIS test is the census that turns red on any
# future git-reaching script without it (precedent: tests/test_lib_source_guard.sh layer 1; dir #644's
# census was a literal grep for the variable NAME `repo`, which is how this class regrew).
#
#   B1 — a SCRIPT is every tracked (or not-yet-tracked, not ignored) file whose first line is a `#!`
#        naming sh or bash, except tests/test_*.sh and tests/lib.sh (covered by the unset at the top of tests/lib.sh). Each
#        git-reaching script carries the B2 line before its first git-reaching line.
#   B3 — git-reaching = a non-comment line where `git` is a word followed by whitespace or end of line,
#        or a source line naming a git-reaching LIB (derived here as a fixed point, never hard-coded).
#   B4 — the hook carve-out: secret-scan.sh keeps every inherited variable in its hook modes (git's own
#        GIT_DIR/GIT_INDEX_FILE for the commit being scanned) and drops them only inside selftest().
#   B5 — no lib gains the line: a lib-level unset changes every sourcer's behaviour.
#
# The census is a function over a root dir: it runs once on this repo and, per case, on a sandbox tree
# this file builds (a scratch `git init` holding copies), so the detector's own non-vacuity is asserted.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

echo "git-env guard census (dir #647)"

# `git` as a word, then whitespace or end of line (leg 1 of the spec's review: the earlier 30-subcommand
# list missed `git clone`, `git --no-optional-locks`, `git add`).
GW='(^|[^A-Za-z0-9_./-])git([[:space:]]|$)'
GUARD="$(grep -m1 '^unset GIT_DIR' "$REPO_ROOT/tools/lib/repo-arg-guard.sh")"
case "$GUARD" in
  "unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE") pass "the lib's unset line is the four-variable line (the one source of the list)" ;;
  *) fail "the lib's unset line is the four-variable line" "tools/lib/repo-arg-guard.sh's first '^unset GIT_DIR' line reads: $GUARD" ;;
esac

# The allowlist — one reason per entry, each with a mode. `exempt`: never demanded a guard.
# `selftest-only`: the line sits inside selftest(), never at top level (B4).
allow_mode() {
  case "$1" in
    tools/secret-guard/ci-scan.sh) echo exempt ;;        # bare git in its cwd only, in CI: an inherited value is the caller's own choice of repo
    tools/secret-guard/pre-commit) echo exempt ;;        # a git hook stub; reaches no git today, listed so a future git line does not demand a guard
    tools/secret-guard/pre-push) echo exempt ;;          # same
    tools/secret-guard/secret-scan.sh) echo selftest-only ;; # hook modes run under git's own GIT_DIR/GIT_INDEX_FILE; selftest() writes into a real repo
    *) echo "" ;;
  esac
}

# first_reach FILE SRC_RE — line number of the first non-comment line that is git-reaching (GW, or a
# source line matching SRC_RE); empty if none. Strings, heredocs and messages count (stricter, never
# weaker).
first_reach() {
  awk -v gw="$GW" -v src="$2" '
    /^[[:space:]]*#/ { next }
    $0 ~ gw || $0 ~ src { print NR; exit }
  ' "$1"
}

# src_re LIBS — an ERE for a source line naming any lib in the newline-separated LIBS ("." escaped as
# a bracket: awk -v would process a backslash).
src_re() {
  local alt="" b
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    alt="${alt:+$alt|}${b//./[.]}"
  done <<< "$1"
  printf '^[[:space:]]*([.]|source)[[:space:]].*/(%s)' "${alt:-NO_SUCH_LIB}"
}

# guard_line FILE — number of the first line equal to GUARD (column 0); empty if none.
guard_line() { awk -v g="$GUARD" '$0 == g { print NR; exit }' "$1"; }

# census ROOT — sets C_REACH (git-reaching B1 scripts), C_LIBS (git-reaching libs), C_OFF (one
# "<file>|<rule>|<why>" per offender), all newline-separated strings (a 0-element bash-3.2 array under
# `set -u` crashes, so no arrays).
census() {
  local root="$1" f b l libs reach_libs changed
  C_REACH="" C_LIBS="" C_OFF=""
  libs="$(cd "$root" && ls tools/lib/*.sh tools/secret-guard/range-lib.sh 2>/dev/null)"
  reach_libs=""
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    [ -n "$(first_reach "$root/$l" "$(src_re "")")" ] && reach_libs="${reach_libs:+$reach_libs
}$(basename "$l")"
  done <<< "$libs"
  changed=1
  while [ "$changed" = 1 ]; do
    changed=0
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      b="$(basename "$l")"
      case "
$reach_libs
" in *"
$b
"*) continue ;; esac
      if [ -n "$(first_reach "$root/$l" "$(src_re "$reach_libs")")" ]; then
        reach_libs="${reach_libs:+$reach_libs
}$b"
        changed=1
      fi
    done <<< "$libs"
  done
  C_LIBS="$reach_libs"
  local re mode first g body bfirst bguard
  re="$(src_re "$reach_libs")"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$root/$f" ] || continue
    case "$f" in tests/test_*.sh | tests/lib.sh) continue ;; esac
    [ "$(head -c 2 "$root/$f")" = "#!" ] || continue
    head -1 "$root/$f" | grep -Eq '(^|[^A-Za-z0-9_])(ba)?sh([^A-Za-z0-9_]|$)' || continue
    first="$(first_reach "$root/$f" "$re")"
    [ -n "$first" ] || continue
    C_REACH="${C_REACH:+$C_REACH
}$f"
    mode="$(allow_mode "$f")"
    g="$(guard_line "$root/$f")"
    case "$mode" in
      exempt) continue ;;
      selftest-only)
        # B4: no column-0 guard (a top-level drop would open the pre-commit hook), and the line,
        # leading whitespace stripped, sits inside selftest() before that function's first git line.
        if [ -n "$g" ]; then
          C_OFF="${C_OFF:+$C_OFF
}$f|dir #647 B4|the guard sits at top level (line $g): hook modes need git's own GIT_DIR/GIT_INDEX_FILE"
        fi
        body="$(awk '/^selftest\(\) \{/ { on = 1 } on { print NR ":" $0 } on && /^\}/ { exit }' "$root/$f")"
        bguard="$(printf '%s\n' "$body" | awk -v g="$GUARD" '{ i = index($0, ":"); n = substr($0, 1, i - 1); s = substr($0, i + 1); sub(/^[ \t]+/, "", s); if (s == g) { print n; exit } }')"
        bfirst="$(printf '%s\n' "$body" | awk -v gw="$GW" '{ i = index($0, ":"); n = substr($0, 1, i - 1); s = substr($0, i + 1); if (s ~ /^[ \t]*#/) next; if (s ~ gw) { print n; exit } }')"
        if [ -z "$bguard" ]; then
          C_OFF="${C_OFF:+$C_OFF
}$f|dir #647 B4|selftest() carries no copy of the guard line"
        elif [ -n "$bfirst" ] && [ "$bguard" -gt "$bfirst" ]; then
          C_OFF="${C_OFF:+$C_OFF
}$f|dir #647 B4|selftest()'s guard (line $bguard) comes after its first git-reaching line ($bfirst)"
        fi
        ;;
      *)
        if [ -z "$g" ]; then
          C_OFF="${C_OFF:+$C_OFF
}$f|dir #647 B1|no column-0 '$GUARD' line (first git-reaching line: $first)"
        elif [ "$g" -gt "$first" ]; then
          C_OFF="${C_OFF:+$C_OFF
}$f|dir #647 B1|the guard (line $g) comes after the first git-reaching line ($first)"
        fi
        ;;
    esac
  done <<< "$(cd "$root" && git ls-files --cached --others --exclude-standard)"
  # B5: no lib, range-lib.sh or hook stub carries the line (stripped — the stricter reading), except
  # repo-arg-guard.sh itself.
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    [ "$l" = tools/lib/repo-arg-guard.sh ] && continue
    if awk -v g="$GUARD" '{ s = $0; sub(/^[ \t]+/, "", s); if (s == g) { found = 1 } } END { exit !found }' "$root/$l"; then
      C_OFF="${C_OFF:+$C_OFF
}$l|dir #647 B5|a lib or hook stub carries the guard line (a lib-level unset changes every sourcer)"
    fi
  done <<< "$(cd "$root" && ls tools/lib/*.sh tools/secret-guard/range-lib.sh tools/secret-guard/pre-commit tools/secret-guard/pre-push 2>/dev/null)"
}

# --- the real tree ---------------------------------------------------------------------------------
census "$REPO_ROOT"
real_off="$C_OFF"
real_reach="$C_REACH"
real_libs="$C_LIBS"

# A1 — the non-vacuity floor: every T1 file (spec §Design T1, as reconciled at implementation) plus
# install-secret-guard.sh is in the git-reaching set; the derived lib set has the seven git-reaching
# libs and not range-lib.
t1="bootstrap.sh install.sh uninstall.sh keel tests/run.sh examples/tour.sh docs/demo/record-demo.sh
docs/keel-ab/seed.sh docs/keel-ab/grade.sh
tools/pre-pr-gate.sh tools/public-audit.sh tools/doctor.sh tools/keel-impact.sh tools/read-trace.sh
tools/branch-cleanup.sh tools/changelog-section.sh tools/init-project.sh tools/token-report.sh
tools/pipeline-canary.sh tools/keel-check.sh tools/keel-check-gate.sh tools/install-pre-pr-gate.sh
tools/install-read-trace.sh tools/delta-audit/derive.sh tools/drydock/inventory.sh
tools/audit-packet/export.sh
tools/self/doctor.sh tools/self/prose-drift.sh tools/self/line-citations.sh
tools/self/citation-resolvability.sh tools/self/shellcheck-targets.sh tools/self/archive-sweep-check.sh
tools/self/backlog-census.sh tools/self/pool-report.sh tools/self/session-cost.sh
tools/secret-guard/ci-scan.sh tools/secret-guard/secret-scan.sh tools/install-secret-guard.sh"
floor_missing=""
for f in $t1; do
  case "
$real_reach
" in *"
$f
"*) ;; *) floor_missing="$floor_missing $f" ;; esac
done
if [ -z "$floor_missing" ]; then
  pass "A1: the census's git-reaching set contains every file of the spec's T1 and install-secret-guard.sh"
else
  fail "A1: the census's git-reaching set contains every file of the spec's T1" "missing from the set (detector regressed, or a file moved):$floor_missing"
fi
libs_missing=""
for b in backlog-blocks impact-store read-trace ref-guard repo-arg-guard repo-top transcript-usage; do
  case "
$real_libs
" in *"
$b.sh
"*) ;; *) libs_missing="$libs_missing $b" ;; esac
done
if [ -z "$libs_missing" ]; then
  pass "A1: the derived git-reaching lib set contains the seven known libs"
else
  fail "A1: the derived git-reaching lib set contains the seven known libs" "missing:$libs_missing"
fi
case "
$real_libs
" in
  *"
range-lib.sh
"*) fail "A1: range-lib.sh is not git-reaching" "the derived lib set contains range-lib.sh (it reaches no git)" ;;
  *) pass "A1: range-lib.sh is not in the derived lib set" ;;
esac

# The census itself: every offender, each naming its file and rule.
if [ -z "$real_off" ]; then
  pass "B1/B4/B5: every git-reaching script carries the guard where it must, no lib carries it"
else
  fail "B1/B4/B5: every git-reaching script carries the guard where it must, no lib carries it" "$(printf '%s\n' "$real_off" | sed 's/^/        /' | sed '1s/^ *//')"
fi

# --- A2: the detector itself, on a sandbox tree --------------------------------------------------------
# A scratch `git init` holding copies of what the cases touch. The baseline is the REAL tree's own
# copies, so it is clean only once the guards are in; each case then asserts the mutation (a) changed a
# file, (b) turns the census red, naming the case's file, and (c) names a file the baseline did not.
build_sandbox() { # prints the sandbox root
  local s
  s="$(new_repo)"
  mkdir -p "$s/tools/secret-guard" "$s/tools/lib"
  cp "$REPO_ROOT"/tools/lib/*.sh "$s/tools/lib/"
  cp "$REPO_ROOT"/tools/secret-guard/range-lib.sh "$REPO_ROOT"/tools/secret-guard/secret-scan.sh \
     "$REPO_ROOT"/tools/secret-guard/ci-scan.sh "$REPO_ROOT"/tools/secret-guard/pre-commit \
     "$REPO_ROOT"/tools/secret-guard/pre-push "$s/tools/secret-guard/"
  cp "$REPO_ROOT"/tools/pre-pr-gate.sh "$s/tools/"
  git -C "$s" add -A
  printf '%s' "$s"
}

sb="$(build_sandbox)"
census "$sb"
base_off="$C_OFF"
if [ -z "$base_off" ]; then
  pass "A2: the unmutated sandbox tree has no offenders (baseline)"
else
  fail "A2: the unmutated sandbox tree has no offenders (baseline)" "$(head -3 <<< "$base_off")"
fi

# case_red LABEL FILE — expect FILE among the offenders and not in the baseline.
case_red() {
  local label="$1" file="$2" sbc="$3" before="$4"
  census "$sbc"
  case "
$before
" in
    *"
$file|"*) fail "$label" "$file is already an offender in the baseline — the case proves nothing" ; return ;;
  esac
  case "
$C_OFF
" in
    *"
$file|"*) pass "$label" ;;
    *) fail "$label" "the census did not name $file; offenders: ${C_OFF:-none}" ;;
  esac
}
mutated() { # LABEL ORIGINAL COPY — the mutation changed the file
  if cmp -s "$2" "$3"; then fail "$1" "the mutation was a no-op on $3"; else pass "$1"; fi
}

# 1. the B2 line deleted from pre-pr-gate.sh
sb="$(build_sandbox)"
delete_line_containing "$sb/tools/pre-pr-gate.sh" "$GUARD"
mutated "A2 case 1: deleting the guard from pre-pr-gate.sh changes the file" "$REPO_ROOT/tools/pre-pr-gate.sh" "$sb/tools/pre-pr-gate.sh"
case_red "A2 case 1: the guard deleted from pre-pr-gate.sh -> red, naming it (B1)" tools/pre-pr-gate.sh "$sb" "$base_off"

# 2. a three-variable line (not byte-identical to the lib's)
sb="$(build_sandbox)"
replace_in_line_containing "$sb/tools/pre-pr-gate.sh" "$GUARD" " GIT_INDEX_FILE" ""
mutated "A2 case 2: a three-variable line changes the file" "$REPO_ROOT/tools/pre-pr-gate.sh" "$sb/tools/pre-pr-gate.sh"
case_red "A2 case 2: a three-variable line in pre-pr-gate.sh -> red, naming it (B1)" tools/pre-pr-gate.sh "$sb" "$base_off"

# 3. the line deleted from secret-scan.sh's selftest() (leading whitespace: it is indented there)
sb="$(build_sandbox)"
awk -v g="$GUARD" '{ s = $0; sub(/^[ \t]+/, "", s); if (s == g) next } { print }' "$sb/tools/secret-guard/secret-scan.sh" > "$sb/ss.tmp" && mv "$sb/ss.tmp" "$sb/tools/secret-guard/secret-scan.sh"
mutated "A2 case 3: deleting the guard from selftest() changes the file" "$REPO_ROOT/tools/secret-guard/secret-scan.sh" "$sb/tools/secret-guard/secret-scan.sh"
case_red "A2 case 3: the guard deleted from secret-scan.sh's selftest() -> red, naming it (B4)" tools/secret-guard/secret-scan.sh "$sb" "$base_off"

# 3b. the same file with the line at TOP LEVEL (column 0): the hook modes would lose git's own variables.
sb="$(build_sandbox)"
insert_before_line_containing "$sb/tools/secret-guard/secret-scan.sh" "selftest() {" "$GUARD"
mutated "A2 case 3b: a top-level guard in secret-scan.sh changes the file" "$REPO_ROOT/tools/secret-guard/secret-scan.sh" "$sb/tools/secret-guard/secret-scan.sh"
case_red "A2 case 3b: a column-0 guard in secret-scan.sh -> red, naming it (B4)" tools/secret-guard/secret-scan.sh "$sb" "$base_off"

# 4. the line added to a lib other than repo-arg-guard.sh (B5)
sb="$(build_sandbox)"
append_line "$sb/tools/lib/impact-store.sh" "$GUARD"
mutated "A2 case 4: adding the guard to impact-store.sh changes the file" "$REPO_ROOT/tools/lib/impact-store.sh" "$sb/tools/lib/impact-store.sh"
case_red "A2 case 4: the guard added to tools/lib/impact-store.sh -> red, naming it (B5)" tools/lib/impact-store.sh "$sb" "$base_off"

# 5. a new script whose only git call is `git --no-optional-locks -C "$x" status` (detector breadth)
sb="$(build_sandbox)"
printf '%s\n' '#!/usr/bin/env bash' 'x="$1"' 'git --no-optional-locks -C "$x" status' > "$sb/scratch-locks.sh"
git -C "$sb" add -A
case_red "A2 case 5: a script whose only git call is 'git --no-optional-locks -C' -> red, naming it" scratch-locks.sh "$sb" "$base_off"

# 6. a new script with only `git clone`
sb="$(build_sandbox)"
printf '%s\n' '#!/bin/sh' 'git clone "$1" "$2"' > "$sb/scratch-clone.sh"
git -C "$sb" add -A
case_red "A2 case 6: a script whose only git call is 'git clone' -> red, naming it" scratch-clone.sh "$sb" "$base_off"

# 7. a new script that guards only by sourcing a git-reaching lib reaches git through it
sb="$(build_sandbox)"
printf '%s\n' '#!/usr/bin/env bash' '. "$(dirname "$0")/lib/repo-top.sh"' > "$sb/scratch-lib-user.sh"
git -C "$sb" add -A
case_red "A2 case 7: a script reaching git only through a sourced git-reaching lib -> red, naming it" scratch-lib-user.sh "$sb" "$base_off"

# A8 — the lib's header: the superseded "NOT a complete census" clause is gone and the census is named.
check_eq "A8: tools/lib/repo-arg-guard.sh no longer carries the 'NOT a complete census' clause" 0 "$(grep -c 'NOT a complete census' "$REPO_ROOT/tools/lib/repo-arg-guard.sh")"
check_contains "A8: the lib's header names the census test" "$(cat "$REPO_ROOT/tools/lib/repo-arg-guard.sh")" "tests/test_git_env_guard.sh"

summary
