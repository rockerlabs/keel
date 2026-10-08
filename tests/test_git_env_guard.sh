#!/usr/bin/env bash
# test_git_env_guard.sh — dir #647: a keel script that names a repository itself (an argument, a hook
# payload's cwd, its own checkout, a scratch fixture) still runs git against whatever an inherited
# GIT_DIR points at. The cure is one inline line at the top of every git-reaching script — byte-identical
# to the unset line in tools/lib/repo-arg-guard.sh — and THIS test is the census that turns red on any
# future git-reaching script without it (precedent: tests/test_lib_source_guard.sh layer 1; dir #644's
# census was a literal grep for the variable NAME `repo`, which is how this class regrew).
#
#   B1 — a SCRIPT is every tracked (or not-yet-tracked, not ignored) file whose first line is a `#!`
#        naming sh or bash, except tests/test_*.sh and tests/lib.sh (covered by the unset at the top of
#        tests/lib.sh). Each git-reaching script carries the guard line (B2: the `unset` line,
#        byte-identical to tools/lib/repo-arg-guard.sh's) before its first git-reaching line.
#   B3 — git-reaching = a non-comment line naming `git` as the command word in any of the shapes below, or
#        a line that sources a git-reaching LIB (derived here as a fixed point, never hard-coded). dir #661
#        widened this from "`git` then whitespace" after the 0.13.0 audit (S5-1): `/usr/bin/git`, `"git"`,
#        `git;`, `"${GIT:-git}"`, `X=git`, `"$GIT"`; a lib sourced after `&&`/inside `if`/in a `for` loop/
#        with no slash; a `dash`/`ksh`/`zsh` shebang; a lib anywhere (every shebang-less `.sh`).
#   B4 — the hook carve-out: secret-scan.sh keeps every inherited variable in its hook modes (git's own
#        GIT_DIR/GIT_INDEX_FILE for the commit being scanned) and drops them only inside selftest() — no copy
#        of the line anywhere else in the file, at any indentation (dir #661 S5-2).
#   B5 — no lib gains the line: a lib-level unset changes every sourcer's behaviour.
#
# The guard line is the SEVEN-variable line (dir #661 S5-3: the four repo selectors plus the object-store
# and namespace trio). Which variables are in it, which are left out and why, each measured, is recorded
# once, in the header of tools/lib/repo-arg-guard.sh; this test only compares each script's copy to it.
#
# Disclosed limits of a line-based census (it reads text, it does not run the scripts): a guard in a
# function body or `if` block is rejected only by the column-0 rule; a git call reached through a variable
# holding the command under a name other than GIT/GIT_BIN/GIT_CMD/git_bin/gitbin AND assigned from a non-
# literal is missed; a lib is matched by BASENAME, so tools/lib/read-trace.sh and tools/read-trace.sh share
# a name; a shebang-less `.sh` is treated as a lib; and a lib named in a `for` list counts only when a
# source line expands that loop variable.
#
# The census is a function over a root dir: it runs once on this repo and, per case, on a sandbox tree
# this file builds (a scratch `git init` holding copies), so the detector's own non-vacuity is asserted.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

echo "git-env guard census (dir #647)"

# git-reaching words (dir #661 widened; each alternative is one shape, none contains a backslash — awk -v
# would process it). TR = what may follow the command word.
#   A  `git` after anything but a word/path character, then whitespace, end of line or ; ) } " ' | & < > `
#      (not a list of subcommands: an earlier 30-subcommand list missed `git clone` and `git add`)
#   B  an absolute path ending in bin/git (/usr/bin/git, /opt/homebrew/bin/git)
#   C  a default expansion naming it: ${GIT_BIN:-git}
#   D  an expansion of a variable conventionally holding it: "$GIT", ${GIT_BIN}
TR='[[:space:];)}"'"'"'|&<>`]'
GW="(^|[^A-Za-z0-9_./-])git(${TR}|\$)"
GW="$GW|(^|[^A-Za-z0-9_.-])/[A-Za-z0-9_/.-]*bin/git(${TR}|\$)"
GW="$GW|[\$][{][A-Za-z_]+:[-=]git[}]"
GW="$GW|[\$][{]?(GIT|GIT_BIN|GIT_CMD|git_bin|gitbin)[}]?([^A-Za-z0-9_]|\$)"
GUARD="$(grep -m1 '^unset GIT_DIR' "$REPO_ROOT/tools/lib/repo-arg-guard.sh")"
case "$GUARD" in
  "unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE") pass "the lib's unset line is the seven-variable line (the one source of the list)" ;;
  *) fail "the lib's unset line is the seven-variable line" "tools/lib/repo-arg-guard.sh's first '^unset GIT_DIR' line reads: $GUARD" ;;
esac

# The allowlist — one reason per entry, each with a mode. `exempt`: never demanded a guard.
# `selftest-only`: the line sits inside selftest(), never at top level (B4).
allow_mode() {
  case "$1" in
    tools/secret-guard/ci-scan.sh) echo exempt ;;        # bare git in its cwd only, in CI: an inherited value is the caller's own choice of repo
    tools/secret-guard/pre-commit) echo exempt ;;        # a git hook stub; reaches no git today, listed so a future git line does not demand a guard
    tools/secret-guard/pre-push) echo exempt ;;          # a git hook stub; reaches git only through range-lib's `git cat-file` (dir #546), and must keep git's own hook environment
    tools/secret-guard/secret-scan.sh) echo selftest-only ;; # hook modes run under git's own GIT_DIR/GIT_INDEX_FILE; selftest() writes into a real repo
    *) echo "" ;;
  esac
}

# first_reach FILE LIBS — line number of the first non-comment line that is git-reaching; empty if none.
# LIBS is the newline-separated git-reaching lib basenames (".sh" included). A line is git-reaching when it
#   - matches GW, or
#   - is a source line (`.`/`source`, anywhere on the line: after &&, ;, then, do, {, ( …) naming a lib by
#     basename, with or without a directory part, or
#   - is a `for VAR in …` header naming a lib while a later or earlier source line expands $VAR / ${VAR}
#     (the loop-sourced shape: `for l in a b; do . "$d/lib/$l.sh"; done`).
# Strings, heredocs and messages count (stricter, never weaker). An awk -v regex carries no backslash.
first_reach() {
  local alt="" b
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    b="${b%.sh}"
    alt="${alt:+$alt|}${b//./[.]}"
  done <<< "${2:-}"
  awk -v gw="$GW" -v srccmd='(^|[;&|({[:space:]])([.]|source)[[:space:]]+' \
      -v lb="(^|[^A-Za-z0-9_-])(${alt:-NO_SUCH_LIB})([^A-Za-z0-9_-]|[.]sh|\$)" '
    /^[[:space:]]*#/ { next }
    $0 ~ gw && !g { g = NR }
    $0 ~ srccmd { srcl[++ns] = $0; if ($0 ~ lb && !l) l = NR }
    /(^|[^A-Za-z0-9_])for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]/ && $0 ~ lb {
      v = $0; sub(/^.*for[[:space:]]+/, "", v); sub(/[[:space:]].*$/, "", v); fv[++nf] = v; fl[nf] = NR }
    END {
      r = g + 0
      if (l && (!r || l < r)) r = l
      for (i = 1; i <= nf; i++) for (j = 1; j <= ns; j++)
        if (index(srcl[j], "$" fv[i]) || index(srcl[j], "${" fv[i] "}")) { if (!r || fl[i] < r) r = fl[i] }
      if (r) print r
    }' "$1"
}

# guard_line FILE — number of the first line equal to GUARD that EXECUTES at top level: column 0, outside a
# heredoc body, and with no column-0 `exit`/`return` line before it (dir #661 S5-1: a guard in a heredoc or
# after an exit "counted as present"). Empty if none. A function body or `if` block is rejected only by the
# column-0 rule (disclosed in the header).
guard_line() {
  awk -v g="$GUARD" -v q="'" '
    nq > 0 {  # inside heredoc bodies: the queue holds the delimiters still owed, in order
      t = $0; if (hdash[1]) sub(/^\t+/, "", t)
      if (t == dq[1]) { for (i = 1; i < nq; i++) { dq[i] = dq[i + 1]; hdash[i] = hdash[i + 1] } nq-- }
      next
    }
    /^(exit|return)([[:space:]]|$)/ { dead = 1 }
    $0 == g && !dead { print NR; exit }
    {
      # every `<<` on the line, left to right, each real opener queued (`cat <<A; cat <<B` owes A then B).
      # Not an opener: `<<<` (a here-string) and a shift inside `((` ... `))` (arithmetic).
      rest = $0; off = 0
      while (match(rest, "<<-?[[:space:]]*[A-Za-z_\"" q "]")) {
        pos = off + RSTART; pre = substr($0, 1, pos - 1)
        if ((pos > 1 && substr($0, pos - 1, 1) == "<") || pre ~ /[(][(][^)]*$/) { off += RSTART; rest = substr(rest, RSTART + 1); continue }
        h = substr(rest, RSTART); d = (h ~ /^<<-/)
        sub(/^<<-?[[:space:]]*/, "", h); gsub("[\"" q "]", "", h); sub(/[^A-Za-z0-9_].*$/, "", h)
        if (h != "") { nq++; dq[nq] = h; hdash[nq] = d }
        off += RSTART + 1; rest = substr(rest, RSTART + 2)
      }
    }' "$1"
}

# has_line LIST ITEM — is ITEM one of the newline-separated lines of LIST.
has_line() {
  case "
$1
" in *"
$2
"*) return 0 ;; esac
  return 1
}

# add_off WHAT — append one offender line to C_OFF.
add_off() { C_OFF="${C_OFF:+$C_OFF
}$1"; }

# is_script FILE — a B1 script: first line is a `#!` naming sh, bash, dash, ash, ksh or zsh.
is_script() { head -1 "$1" | grep -Eq '^#!.*(^|[^A-Za-z0-9_])(ba|da|a|k|z)?sh([^A-Za-z0-9_]|$)'; }

# census_files ROOT — every tracked or not-yet-tracked, not ignored, file of the tree.
census_files() { (cd "$1" && git ls-files --cached --others --exclude-standard); }

# lib_candidates ROOT — every lib the census may derive: tools/lib/*.sh, range-lib.sh, and every other
# tracked shebang-less `.sh` (dir #661: a lib outside tools/lib), except tests/lib.sh and tests/test_*.sh.
lib_candidates() {
  local root="$1" f
  {
    (cd "$root" && ls tools/lib/*.sh tools/secret-guard/range-lib.sh 2>/dev/null)
    while IFS= read -r f; do
      case "$f" in *.sh) ;; *) continue ;; esac
      case "$f" in tests/test_*.sh | tests/lib.sh) continue ;; esac
      [ -f "$root/$f" ] || continue
      head -1 "$root/$f" | grep -q '^#!' && continue
      printf '%s\n' "$f"
    done <<< "$(census_files "$root")"
  } | sort -u
}

# derive_libs ROOT — sets C_LIBS: the libs that reach git, directly or by sourcing one that does (a fixed
# point, never hard-coded), as basenames.
derive_libs() {
  local root="$1" libs l b changed=1
  libs="$(lib_candidates "$root")"
  C_LIBS=""
  while [ "$changed" = 1 ]; do
    changed=0
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      b="$(basename "$l")"
      has_line "$C_LIBS" "$b" && continue
      if [ -n "$(first_reach "$root/$l" "$C_LIBS")" ]; then
        C_LIBS="${C_LIBS:+$C_LIBS
}$b"
        changed=1
      fi
    done <<< "$libs"
  done
}

# census ROOT [LIBS] — sets C_REACH (git-reaching B1 scripts), C_LIBS (git-reaching libs), C_OFF (one
# "<file>|<rule>|<why>" per offender), all newline-separated strings (a 0-element bash-3.2 array under
# `set -u` crashes, so no arrays). LIBS, when given, is a lib set derived earlier (the sandbox trees copy
# the real libs unchanged, so re-deriving it per case would only cost time).
census() {
  local root="$1" f l first g sel mode
  C_REACH="" C_OFF=""
  if [ -n "${2:-}" ]; then C_LIBS="$2"; else derive_libs "$root"; fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$root/$f" ] || continue
    case "$f" in tests/test_*.sh | tests/lib.sh) continue ;; esac
    is_script "$root/$f" || continue
    first="$(first_reach "$root/$f" "$C_LIBS")"
    [ -n "$first" ] || continue
    C_REACH="${C_REACH:+$C_REACH
}$f"
    mode="$(allow_mode "$f")"
    [ "$mode" = exempt ] && continue
    if [ "$mode" = selftest-only ]; then
      # B4: no copy of the guard line OUTSIDE selftest() at any indentation (a top-level or hook-arm drop
      # would open the pre-commit hook), and the line inside selftest() comes before that function's first
      # git-reaching line. sel = guard line inside selftest, its first git line, copies outside selftest.
      sel="$(awk -v g="$GUARD" -v gw="$GW" '
        { s = $0; sub(/^[ \t]+/, "", s) }
        /^selftest\(\) \{/ { on = 1 }
        on { if (s == g && !bg) bg = NR
             if (s !~ /^#/ && s ~ gw && !bf) bf = NR }
        !on && s == g { out++ ; if (!ol) ol = NR }
        on && /^\}/ { on = 0 }
        END { print bg + 0, bf + 0, out + 0, ol + 0 }' "$root/$f")"
      set -- $sel   # four integers: guard line in selftest, its first git line, copies outside, first such line (0 = none)
      [ "$3" = 0 ] || add_off "$f|dir #647 B4|the guard sits outside selftest() (line $4): hook modes need git's own GIT_DIR/GIT_INDEX_FILE"
      if [ "$1" = 0 ]; then
        add_off "$f|dir #647 B4|selftest() carries no copy of the guard line"
      elif [ "$2" != 0 ] && [ "$1" -gt "$2" ]; then
        add_off "$f|dir #647 B4|selftest()'s guard (line $1) comes after its first git-reaching line ($2)"
      fi
    else
      g="$(guard_line "$root/$f")"
      if [ -z "$g" ]; then
        add_off "$f|dir #647 B1|no executing column-0 '$GUARD' line (first git-reaching line: $first)"
      elif [ "$g" -gt "$first" ]; then
        add_off "$f|dir #647 B1|the guard (line $g) comes after the first git-reaching line ($first)"
      fi
    fi
  done <<< "$(census_files "$root")"
  # B5: no lib, range-lib.sh or hook stub carries the line (stripped — the stricter reading), except
  # repo-arg-guard.sh itself.
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    [ "$l" = tools/lib/repo-arg-guard.sh ] && continue
    [ -f "$root/$l" ] || continue
    if awk -v g="$GUARD" '{ s = $0; sub(/^[ \t]+/, "", s); if (s == g) { found = 1 } } END { exit !found }' "$root/$l"; then
      add_off "$l|dir #647 B5|a lib or hook stub carries the guard line (a lib-level unset changes every sourcer)"
    fi
  done <<< "$({ lib_candidates "$root"; printf '%s\n' tools/secret-guard/pre-commit tools/secret-guard/pre-push; } | sort -u)"
}

# --- the real tree ---------------------------------------------------------------------------------
census "$REPO_ROOT"
real_off="$C_OFF"
real_reach="$C_REACH"
real_libs="$C_LIBS"

# A1 — the non-vacuity floor, a hand-kept list on purpose (a census that silently finds nothing would be
# green): every script known to reach git when this census was written, plus install-secret-guard.sh, is in
# the git-reaching set; the derived lib set has the seven git-reaching libs, and range-lib.sh since dir #546.
# (uninstall.sh left the list with dir #688: its only git call was the machine-wide hooksPath read, which now
# goes through tools/install-secret-guard.sh --where --global, a script that is on the list.)
t1="bootstrap.sh install.sh keel tests/run.sh examples/tour.sh docs/demo/record-demo.sh
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
  has_line "$real_reach" "$f" || floor_missing="$floor_missing $f"
done
if [ -z "$floor_missing" ]; then
  pass "A1: the census's git-reaching set contains every known git-reaching script"
else
  fail "A1: the census's git-reaching set contains every known git-reaching script" "missing from the set (detector regressed, or a file moved):$floor_missing"
fi
libs_missing=""
for b in backlog-blocks impact-store read-trace ref-guard repo-arg-guard repo-top transcript-usage; do
  has_line "$real_libs" "$b.sh" || libs_missing="$libs_missing $b"
done
if [ -z "$libs_missing" ]; then
  pass "A1: the derived git-reaching lib set contains the seven known libs"
else
  fail "A1: the derived git-reaching lib set contains the seven known libs" "missing:$libs_missing"
fi
# range-lib.sh joined the set with dir #546 (`git cat-file` in secret_guard_commit_known). It still carries
# no guard line (B5 below): the pre-push hook sources it and must keep git's own hook environment.
if has_line "$real_libs" range-lib.sh; then
  pass "A1: range-lib.sh is in the derived lib set (it reaches git since dir #546)"
else
  fail "A1: range-lib.sh is in the derived lib set (it reaches git since dir #546)" "the derived lib set lacks range-lib.sh (the detector regressed, or secret_guard_commit_known lost its git call)"
fi
# tests/test_*.sh are outside B1 because tests/lib.sh unsets the variables before any fixture runs; pin
# that line (every test file sourcing lib.sh is tests/test_lib_source_guard.sh's job).
check_eq "tests/lib.sh carries the guard line the census exempts every test file on" 1 "$(grep -cxF -- "$GUARD" "$REPO_ROOT/tests/lib.sh")"

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
census "$sb" "$real_libs"
base_off="$C_OFF"
if [ -z "$base_off" ]; then
  pass "A2: the unmutated sandbox tree has no offenders (baseline)"
else
  fail "A2: the unmutated sandbox tree has no offenders (baseline)" "$(head -3 <<< "$base_off")"
fi

# case_red LABEL FILE SANDBOX BASELINE — expect FILE among the offenders and not in the baseline.
case_red() {
  local label="$1" file="$2" sbc="$3" before="$4"
  census "$sbc" "$real_libs"
  if grep -q -- "^$file|" <<< "$before"; then
    fail "$label" "$file is already an offender in the baseline — the case proves nothing"
  elif grep -q -- "^$file|" <<< "$C_OFF"; then
    pass "$label"
  else
    fail "$label" "the census did not name $file; offenders: ${C_OFF:-none}"
  fi
}
mutated() { # LABEL ORIGINAL COPY — the mutation changed the file
  if cmp -s "$2" "$3"; then fail "$1" "the mutation was a no-op on $3"; else pass "$1"; fi
}

# 1. the B2 line deleted from pre-pr-gate.sh
sb="$(build_sandbox)"
delete_line_containing "$sb/tools/pre-pr-gate.sh" "$GUARD"
mutated "A2 case 1: deleting the guard from pre-pr-gate.sh changes the file" "$REPO_ROOT/tools/pre-pr-gate.sh" "$sb/tools/pre-pr-gate.sh"
case_red "A2 case 1: the guard deleted from pre-pr-gate.sh -> red, naming it (B1)" tools/pre-pr-gate.sh "$sb" "$base_off"

# 2. a shortened line (one name dropped; not byte-identical to the lib's)
sb="$(build_sandbox)"
replace_in_line_containing "$sb/tools/pre-pr-gate.sh" "$GUARD" " GIT_INDEX_FILE" ""
mutated "A2 case 2: a shortened guard line changes the file" "$REPO_ROOT/tools/pre-pr-gate.sh" "$sb/tools/pre-pr-gate.sh"
case_red "A2 case 2: a shortened guard line in pre-pr-gate.sh -> red, naming it (B1)" tools/pre-pr-gate.sh "$sb" "$base_off"

# 3. the line deleted from secret-scan.sh's selftest() (leading whitespace: it is indented there)
sb="$(build_sandbox)"
delete_line_containing "$sb/tools/secret-guard/secret-scan.sh" "$GUARD"
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

# --- dir #661: the widened census — one fixture per shape the detector used to fail open on ----------------
# Each fixture is a scratch script with NO guard whose only git reach is the named shape; the census must
# name it. case_red proves "red without the change" for the detector; the baseline stays clean.
shape_case() { # LABEL FILE LINE... — a new bash script (shebang first) holding LINEs, named by the census
  local label="$1" file="$2"; shift 2
  local sbc; sbc="$(build_sandbox)"
  printf '%s\n' '#!/usr/bin/env bash' "$@" > "$sbc/$file"
  git -C "$sbc" add -A
  case_red "$label" "$file" "$sbc" "$base_off"
}
shape_case 'dir #661 S5-1: GIT="${GIT:-git}" then "$GIT" -C -> red, naming it' scratch-var-default.sh 'GIT="${GIT:-git}"' '"$GIT" -C "$1" commit -m x'
shape_case 'dir #661 S5-1: "${GIT_BIN:-git}" -C -> red, naming it' scratch-bin-default.sh '"${GIT_BIN:-git}" -C "$1" status'
shape_case 'dir #661 S5-1: /usr/bin/git -C -> red, naming it' scratch-abs-path.sh '/usr/bin/git -C "$1" status'
shape_case 'dir #661 S5-1: "git" -C (quoted command word) -> red, naming it' scratch-quoted.sh '"git" -C "$1" status'
shape_case 'dir #661 S5-1: git; (word then semicolon) -> red, naming it' scratch-semicolon.sh 'git; echo done'
shape_case 'dir #661 S5-1: G=git then "$G" (assignment of the command word) -> red, naming it' scratch-assigned.sh 'G=git' '"$G" -C "$1" status'
shape_case 'dir #661 S5-1: a git-reaching lib sourced in a for-loop -> red, naming it' scratch-loop-src.sh 'for l in repo-top; do . "$(dirname "$0")/lib/$l.sh"; done'
shape_case 'dir #661 S5-1: a git-reaching lib sourced after && -> red, naming it' scratch-and-src.sh '[ -f x ] && . "$(dirname "$0")/lib/repo-top.sh"'
shape_case 'dir #661 S5-1: a git-reaching lib sourced inside if/then -> red, naming it' scratch-if-src.sh 'if true; then . "$(dirname "$0")/lib/repo-top.sh"; fi'
shape_case 'dir #661 S5-1: a git-reaching lib sourced without a slash -> red, naming it' scratch-bare-src.sh '. repo-top.sh'
sb="$(build_sandbox)"
printf '%s\n' '#!/usr/bin/env dash' 'git -C "$1" status' > "$sb/scratch-dash.sh"
git -C "$sb" add -A
case_red "dir #661 S5-1: a dash-shebang script (#!/usr/bin/env dash) -> red, naming it" scratch-dash.sh "$sb" "$base_off"
# a git-reaching lib OUTSIDE tools/lib (shebang-less .sh anywhere), and a script that sources it
sb="$(build_sandbox)"
mkdir -p "$sb/extras"
printf '%s\n' '# shellcheck shell=bash' 'ext_status() { git -C "$1" status; }' > "$sb/extras/extlib.sh"
printf '%s\n' '#!/usr/bin/env bash' '. "$(dirname "$0")/extras/extlib.sh"' > "$sb/scratch-ext-user.sh"
git -C "$sb" add -A
census "$sb"
if has_line "$C_LIBS" extlib.sh; then pass "dir #661 S5-1: a git-reaching lib outside tools/lib is in the derived lib set"; else fail "dir #661 S5-1: a git-reaching lib outside tools/lib is in the derived lib set" "derived: $(printf '%s' "$C_LIBS" | tr '\n' ' ')"; fi
if grep -q -- '^scratch-ext-user.sh|' <<< "$C_OFF"; then pass "dir #661 S5-1: a script sourcing a lib outside tools/lib -> red, naming it"; else fail "dir #661 S5-1: a script sourcing a lib outside tools/lib -> red, naming it" "offenders: ${C_OFF:-none}"; fi
# B5 reaches such a lib too
sb="$(build_sandbox)"
mkdir -p "$sb/extras"
printf '%s\n' '# shellcheck shell=bash' 'ext_status() { git -C "$1" status; }' > "$sb/extras/extlib.sh"
append_line "$sb/extras/extlib.sh" "$GUARD"
git -C "$sb" add -A
census "$sb"
if grep -q -- '^extras/extlib.sh|' <<< "$C_OFF"; then pass "dir #661 S5-1: the guard line added to a lib outside tools/lib -> red, naming it (B5)"; else fail "dir #661 S5-1: the guard line added to a lib outside tools/lib -> red, naming it (B5)" "offenders: ${C_OFF:-none}"; fi

# a guard that never executes must not count as present (heredoc body; after a column-0 exit)
sb="$(build_sandbox)"
printf '%s\n' '#!/usr/bin/env bash' "cat <<'EOF'" "$GUARD" 'EOF' 'git -C "$1" status' > "$sb/scratch-heredoc-guard.sh"
git -C "$sb" add -A
case_red "dir #661 S5-1: a guard line inside a heredoc body does not count -> red, naming it" scratch-heredoc-guard.sh "$sb" "$base_off"
sb="$(build_sandbox)"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' "$GUARD" 'git -C "$1" status' > "$sb/scratch-after-exit.sh"
git -C "$sb" add -A
case_red "dir #661 S5-1: a guard line after a column-0 exit does not count -> red, naming it" scratch-after-exit.sh "$sb" "$base_off"

# a here-string (<<<) is not a heredoc opener: a real guard after one still counts
sb="$(build_sandbox)"
printf '%s\n' '#!/usr/bin/env bash' "read -r x <<< 'word'" "$GUARD" 'git -C "$1" status' > "$sb/scratch-herestring.sh"
git -C "$sb" add -A
census "$sb" "$real_libs"
if grep -q -- '^scratch-herestring.sh|' <<< "$C_OFF"; then fail "dir #661 S5-1: a real guard after a here-string (<<<) still counts as present" "the census named scratch-herestring.sh: $C_OFF"; else pass "dir #661 S5-1: a real guard after a here-string (<<<) still counts as present"; fi
has_line "$C_REACH" scratch-herestring.sh && pass "dir #661 S5-1: ... and that script is in the git-reaching set (the guard check ran)" || fail "dir #661 S5-1: ... and that script is in the git-reaching set (the guard check ran)" "not in the reach set"

sb="$(build_sandbox)"
printf '%s\n' '#!/usr/bin/env bash' 'read -r x <<< "$1"; cat <<EOF' "$GUARD" 'EOF' 'git -C "$1" status' > "$sb/scratch-herestring-heredoc.sh"
git -C "$sb" add -A
case_red "dir #661 S5-1: a heredoc opened after a here-string on the same line still hides its body's guard -> red, naming it" scratch-herestring-heredoc.sh "$sb" "$base_off"
sb="$(build_sandbox)"
printf '%s\n' '#!/usr/bin/env bash' 'cat <<A; cat <<B' 'a' 'A' "$GUARD" 'B' 'git -C "$1" status' > "$sb/scratch-two-heredocs.sh"
git -C "$sb" add -A
case_red "dir #661 S5-1: a second heredoc opener on one line hides the guard line in its body -> red, naming it" scratch-two-heredocs.sh "$sb" "$base_off"
sb="$(build_sandbox)"
printf '%s\n' '#!/usr/bin/env bash' 'n=3; x=$((1<<n))' "$GUARD" 'git -C "$1" status' > "$sb/scratch-shift.sh"
git -C "$sb" add -A
census "$sb" "$real_libs"
if grep -q -- '^scratch-shift.sh|' <<< "$C_OFF"; then fail "dir #661 S5-1: an arithmetic shift (<<) is not a heredoc opener — a real guard after it still counts" "the census named scratch-shift.sh: $C_OFF"; else pass "dir #661 S5-1: an arithmetic shift (<<) is not a heredoc opener — a real guard after it still counts"; fi
# the same list is spelled by tools/lib/impact-store.sh's scoped `env -u` form, which the census cannot see
impact_names="$(sed -n '/^_keel_store_git() {/,/^}/p' "$REPO_ROOT/tools/lib/impact-store.sh" | grep -v '^[[:space:]]*#' | tr -s ' \\\n' '\n\n' | awk '$0 == "-u" { getline; print }' | sort | tr '\n' ' ')"
guard_names="$(printf '%s\n' ${GUARD#unset } | sort | tr '\n' ' ')"
check_eq "dir #661: tools/lib/impact-store.sh's scoped env -u names exactly the variables of the guard line" "$guard_names" "$impact_names"

# S5-3, transport side: an inherited GIT_NAMESPACE makes a clone of a local repo come up EMPTY (measured, git 2.52.0)
t_src="$(new_repo)"
git -C "$t_src" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m first
for t_url in "$t_src" "file://$t_src"; do
  t_dst="$(mktemp -d "$SANDBOX/clone.XXXXXX")"
  env GIT_NAMESPACE=foo bash -c "$GUARD"'; git clone -q "$1" "$2/c" >/dev/null 2>&1' _ "$t_url" "$t_dst"
  check_eq "dir #661 S5-3: with GIT_NAMESPACE inherited, a clone of ${t_url%%$t_src*}<local repo> carries the source's commit once the guard ran" 1 "$(git -C "$t_dst/c" rev-list --count HEAD 2>/dev/null || echo 0)"
done

# S5-2: B4 also rejects an INDENTED guard outside selftest() (a hook arm), not only a column-0 one
sb="$(build_sandbox)"
insert_before_line_containing "$sb/tools/secret-guard/secret-scan.sh" "selftest() {" "  $GUARD"
mutated "dir #661 S5-2: an indented guard in secret-scan.sh outside selftest() changes the file" "$REPO_ROOT/tools/secret-guard/secret-scan.sh" "$sb/tools/secret-guard/secret-scan.sh"
case_red "dir #661 S5-2: an indented guard outside selftest() -> red, naming secret-scan.sh (B4)" tools/secret-guard/secret-scan.sh "$sb" "$base_off"

# non-vacuity the other way: the widened detector must not name a script that does not reach git
sb="$(build_sandbox)"
printf '%s\n' '#!/usr/bin/env bash' 'GIT_DIR_X=1' 'echo "see .gitignore and digit and a-git-like name"' \
  '# git status is mentioned in a comment only' 'cat <<'"'"'EOF'"'"'' 'Move keel stores: the read-trace store and impact store.' 'EOF' \
  'for name in impact read-trace; do echo "$name"; done' '. "$(dirname "$0")/tools/lib/state-root.sh"' > "$sb/scratch-no-git.sh"
git -C "$sb" add -A
census "$sb" "$real_libs"
if grep -q -- '^scratch-no-git.sh|' <<< "$C_OFF"; then fail "dir #661 S5-1: prose, a store-name loop list and a non-git lib source are not git-reaching" "the widened census named scratch-no-git.sh: $C_OFF"; else pass "dir #661 S5-1: prose, a store-name loop list and a non-git lib source are not git-reaching"; fi

# the real in-tree instance of the loop-sourced shape (S5's own evidence)
if has_line "$real_reach" tools/machine-watch.sh; then pass "dir #661 S5-1: tools/machine-watch.sh (loop-sourced git-global-paths) is in the real git-reaching set"; else fail "dir #661 S5-1: tools/machine-watch.sh (loop-sourced git-global-paths) is in the real git-reaching set" "the census does not know machine-watch.sh reaches git"; fi

# S5-3: the dropped set covers the object-store variables, behaviourally
t_a="$(new_repo)"; t_d="$(new_repo)"
env GIT_OBJECT_DIRECTORY="$t_d/.git/objects" bash -c "$GUARD"'; git -C "$1" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m first' _ "$t_a" >/dev/null 2>&1
check_eq "dir #661 S5-3: an inherited GIT_OBJECT_DIRECTORY no longer sends a fresh repo's commit into the foreign store" 0 "$(find "$t_d/.git/objects" -type f | wc -l | tr -d ' ')"
check_eq "dir #661 S5-3: ... and the target repo's own object store passes fsck" 0 "$(git -C "$t_a" fsck >/dev/null 2>&1; echo $?)"
t_blob="$(printf 'pin661' | git -C "$t_d" hash-object -w --stdin)"
printf 'pin661' | env GIT_ALTERNATE_OBJECT_DIRECTORIES="$t_d/.git/objects" bash -c "$GUARD"'; git -C "$1" hash-object -w --stdin >/dev/null' _ "$t_a" >/dev/null 2>&1
if git -C "$t_a" cat-file -e "$t_blob" 2>/dev/null; then pass "dir #661 S5-3: an inherited GIT_ALTERNATE_OBJECT_DIRECTORIES no longer hides a write behind a foreign store"; else fail "dir #661 S5-3: an inherited GIT_ALTERNATE_OBJECT_DIRECTORIES no longer hides a write behind a foreign store" "the blob never reached the target's own store"; fi

# A8 — the lib's header: the superseded "NOT a complete census" clause is gone and the census is named.
check_eq "A8: tools/lib/repo-arg-guard.sh no longer carries the 'NOT a complete census' clause" 0 "$(grep -c 'NOT a complete census' "$REPO_ROOT/tools/lib/repo-arg-guard.sh")"
check_contains "A8: the lib's header names the census test" "$(cat "$REPO_ROOT/tools/lib/repo-arg-guard.sh")" "tests/test_git_env_guard.sh"

summary
