#!/usr/bin/env bash
# tools/self/procsub-leak.sh (dir #905): the check for a process substitution bash 3.2 holds open once per
# loop pass inside a function (dir #904's crash). Each leaking shape it must flag, each shape it must not
# (a child process, a subshell, the top level, a comment, a here-document, the captured fix), the call
# following (same file, a sourced lib, two levels deep), the exit codes, a ground-truth leg that runs the
# same shapes on the host's /bin/bash when that is the 3.2 that leaks, and a live leg over keel's own tree.
# Every fixture body sits in a quoted here-document: the check skips those, so this file is not flagged.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

pl="$REPO_ROOT/tools/self/procsub-leak.sh"

# --- --help / bad args -------------------------------------------------------------------------
run "$pl" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$pl" --bogus
check_status "unknown flag -> exit 2" 2 "$STATUS"
run "$pl" /no/such/dir
check_status "missing REPO_DIR -> exit 2" 2 "$STATUS"

# --- one fixture repo, one function per case; each case is asserted by its function's name ------------
d="$(new_repo)"
cat > "$d/leaks.sh" <<'EOF'
#!/usr/bin/env bash
leak_done() { local f; for f in "$@"; do while read -r x; do echo "$x"; done < <(printf '%s\n' "$f"); done; }
leak_group() { local f; for f in "$@"; do { read -r x; echo "$x"; } < <(printf '%s\n' "$f"); done; }
leak_read() { local f x; for f in "$@"; do read -r x < <(printf '%s\n' "$f"); echo "$x"; done; }
leak_if() { local f; for f in "$@"; do if read -r x; then echo "$x"; fi < <(printf '%s\n' "$f"); done; }
leak_out() { local f; for f in "$@"; do echo "$f" > >(cat); done; }
leak_while_outer() {
  local i=0
  while [ "$i" -lt 3 ]; do
    i=$((i + 1))
    while read -r x; do
      echo "$x"
    done < <(
      printf '%s\n' "$i"
    )
  done
}
EOF
cat > "$d/clean.sh" <<'EOF'
#!/usr/bin/env bash
ok_external() { local f; for f in "$@"; do cat < <(printf '%s\n' "$f"); grep -c x <(printf '%s\n' "$f"); done; }
ok_subshell() { local f; for f in "$@"; do ( read -r x; echo "$x" ) < <(printf '%s\n' "$f"); done; }
ok_cmdsubst() { local f y; for f in "$@"; do y="$(while read -r x; do echo "$x"; done < <(printf '%s\n' "$f"))"; echo "$y"; done; }
ok_once() { while read -r x; do echo "$x"; done < <(printf 'a\n'); }
ok_fixed() {
  local f out
  for f in "$@"; do
    out="$(printf '%s\n' "$f")" || true
    [ -z "$out" ] || while read -r x; do echo "$x"; done <<< "$out"
  done
}
ok_comment() { local f; for f in "$@"; do echo "$f"; done; }   # done < <(a comment)
ok_heredoc() {
  local f
  for f in "$@"; do
    cat <<'DOC'
while read -r x; do :; done < <(prose)
DOC
  done
}
for f in a b; do while read -r x; do echo "$x"; done < <(printf '%s\n' "$f"); done
EOF
cat > "$d/lib-helper.sh" <<'EOF'
#!/usr/bin/env bash
helper_opens_one() { while read -r x; do echo "$x"; done < <(printf '%s\n' "$1"); }
EOF
cat > "$d/calls.sh" <<'EOF'
#!/usr/bin/env bash
. ./lib-helper.sh
once_wrapper() { helper_opens_one "$1"; }
leak_via_lib() { local f; for f in "$@"; do helper_opens_one "$f"; done; }
leak_two_deep() { local f; for f in "$@"; do [ -n "$f" ] && once_wrapper "$f"; done; }
ok_call_in_cmdsubst() { local f y; for f in "$@"; do y="$(helper_opens_one "$f")"; echo "$y"; done; }
ok_call_in_pipeline() { local f; for f in "$@"; do helper_opens_one "$f" | cat; done; }
ok_call_once() { helper_opens_one a; }
for f in a b; do helper_opens_one "$f"; done
EOF
( cd "$d" && git add -A && git commit -q -m fixture )

run "$pl" "$d" --quiet
check_status "leaking fixture -> exit 1" 1 "$STATUS"
for fn in leak_done leak_group leak_read leak_if leak_out leak_while_outer; do
  check_contains "flags $fn()" "$OUT" "leaks.sh $fn():"
done
check_contains "follows a call into a sourced lib's function" "$OUT" "calls.sh leak_via_lib(): calls helper_opens_one()"
check_contains "follows a call two levels deep (a function that calls a one-fd function once)" "$OUT" \
  "calls.sh leak_two_deep(): calls once_wrapper()"
for fn in ok_external ok_subshell ok_cmdsubst ok_once ok_fixed ok_comment ok_heredoc \
          once_wrapper ok_call_in_cmdsubst ok_call_in_pipeline ok_call_once helper_opens_one; do
  check_absent "does not flag $fn()" "$OUT" " $fn():"
done
check_absent "a loop at a script's top level is never flagged" "$OUT" "__keel_wrap"
check_eq "exactly the eight leaks, nothing else" 8 "$(match "$OUT" -c '^  LEAK ')"

# the fix shape, applied to every flagged function, turns the tree clean
d2="$(new_repo)"
cat > "$d2/fixed.sh" <<'EOF'
#!/usr/bin/env bash
fixed_done() {
  local f out
  for f in "$@"; do
    out="$(printf '%s\n' "$f")" || true
    [ -z "$out" ] || while read -r x; do echo "$x"; done <<< "$out"
  done
}
EOF
( cd "$d2" && git add -A && git commit -q -m fixture )
run "$pl" "$d2"
check_status "a clean tree -> exit 0" 0 "$STATUS"
check_contains "a clean tree says OK" "$OUT" "OK — no process substitution held open"

# an unparseable script is a blind spot: reported and exit 2, never passed as clean
printf '#!/usr/bin/env bash\nbroken() { if true; then echo x; }\n' > "$d2/broken.sh"
( cd "$d2" && git add -A && git commit -q -m broken )
run "$pl" "$d2"
check_status "an unparseable script -> exit 2" 2 "$STATUS"
check_contains "...and names it" "$OUT" "UNPARSED  broken.sh"

# --- ground truth: the shapes above behave on bash 3.2 the way the check classifies them -----------------
# The check's leak/no-leak table is a measurement of 3.2.57 (see its header). Where the host's /bin/bash is
# a 3.x (macOS), re-measure it: 40 passes under `ulimit -n 30` run a leaking shape out of fds, and must not
# run a clean one out. A newer bash never leaks, so the leg is skipped there.
if [ -x /bin/bash ] && /bin/bash -c '[ "${BASH_VERSINFO[0]}" -lt 4 ]'; then
  gt() {   # gt SHAPE — prints "leaks" or "holds" for SHAPE run 40 times in a loop inside a function
    local out
    out="$(/bin/bash -c 'ulimit -n 30; g() { :; }; f() { local i=0; while [ "$i" -lt 40 ]; do i=$((i + 1)); eval "$1"; done; }; f "$1"' _ "$1" 2>&1)"
    case "$out" in *'Too many open files'*) echo leaks ;; *) echo holds ;; esac
  }
  for shape in 'while read -r x; do :; done < <(echo a)' '{ read -r x; } < <(echo a)' 'read -r x < <(echo a)' \
               'if read -r x; then :; fi < <(echo a)' 'echo a > >(cat >/dev/null)' 'g < <(echo a)'; do
    check_eq "bash 3.2 leaks on: $shape" leaks "$(gt "$shape")"
  done
  for shape in 'cat < <(echo a) >/dev/null' 'grep -q a <(echo a)' '( read -r x ) < <(echo a)' \
               'y="$(read -r x < <(echo a))"' 'y="$(echo a)"; while read -r x; do :; done <<< "$y"'; do
    check_eq "bash 3.2 holds on: $shape" holds "$(gt "$shape")"
  done
else
  pass "ground-truth leg skipped: no bash 3.x at /bin/bash (only 3.2 leaks)"
fi

# --- live: keel's own tree carries no such leak ------------------------------------------------------
run "$pl" "$REPO_ROOT" --quiet
check_status "keel's own tree is clean -> exit 0" 0 "$STATUS"
check_eq "keel's own tree: no LEAK line" "" "$OUT"

summary
