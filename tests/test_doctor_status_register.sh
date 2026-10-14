#!/usr/bin/env bash
# test_doctor_status_register.sh — dir #766: every site in tools/self/doctor.sh that can print OK over a
# failed producer is either CHECKED (the dir #715 / #738 producer rule: spool the output, keep the status,
# a GAP naming what could not be read) or listed below with the reason it stays unchecked.
#
# A "site" is a non-comment line of tools/self/doctor.sh holding one of the four shapes that hide a
# producer's status: `|| true`, `|| echo`, a `< <(` process substitution, or a command substitution /
# process substitution closing with `2>/dev/null)`. A line that CAPTURES the status (`… || x_rc=$?`) is the
# checked form and is not a site. This test fails when doctor.sh gains a site the register
# below does not name (a NEW unregistered site), and when the register names a site doctor.sh no longer has
# (a STALE entry) — so converting a site to a checked form means deleting its register line in the same change.
#
# Register format, one site per line inside the heredoc below:  <reason> ## <the site line, trimmed>
# Identical site lines are listed once. Keep a reason short and specific: what the status is
# for, and why hiding it is correct HERE.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

doctor="$REPO_ROOT/tools/self/doctor.sh"
check_file "tools/self/doctor.sh exists" "$doctor"

# `read -d ''`, not `$(cat <<…)`: bash 3.2 miscounts the unbalanced parentheses in the entries below inside a $( ).
IFS= read -r -d '' register <<'REGISTER' || true
output gate for --quiet, not a producer: echo is the output itself ## say()  { [ "$QUIET" = 1 ] || echo "$@"; }
grep exits 1 on no match, which is valid here (an empty result is a real answer); the file read is guarded by file_readable above (a file with no ship-skip arm is an empty list, check 1) ## | grep -ohE '[A-Za-z0-9._-]+\.md' | sort -u || true)"
grep exits 1 on no match, which is valid here (an empty result is a real answer); the file read is guarded by file_readable above (absence of the core-@import pattern is graded by the caller) ## hit="$(grep -ohE "\(\^\|\[\[:space:\]\]\)@\[\^\[:space:\]\]\*keel/CORE[^']*" "$repo_root/$f" 2>/dev/null | sort -u || true)"
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result ## n_unique="$(printf '%s' "$import_re_found" | sort -u | grep -c . || true)"
grep exits 1 on no match, which is valid here (an empty result is a real answer); the file read is guarded by file_readable above (no advice hit is the clean case) ## | grep -vE "$marker_re" || true)"
grep exits 1 on no match, which is valid here (an empty result is a real answer); the file read is guarded by file_readable above (no leaked host path is the clean case) ## hit="$(grep -noE "$HOME_RE" "$repo_root/$f" 2>/dev/null | head -1 || true)"
grep exits 1 on no match, which is valid here (an empty result is a real answer); the file read is guarded by file_readable above (no leaked email is the clean case) ## hit="$(grep -noE "$EMAIL_RE" "$repo_root/$f" 2>/dev/null | grep -vE "$safe_email_re" | head -1 || true)"
the failure-path diagnosis only: the GAP naming the failure is already printed, this adds git's first stderr line ## why="$(git -C "$repo_root" ls-files -- "$@" 2>&1 >/dev/null || true)"   # the diagnosis only, on the failure path
the failure-path diagnosis only: the GAP naming the failure is already printed, this adds git's first stderr line ## [ -z "$why" ] || echo "       ${why%%$'\n'*}"
the failure-path diagnosis only: the GAP naming the failure is already printed, this adds git's first stderr line ## gv_why="$(git -C "$repo_root" "$@" 2>&1 >/dev/null || true)"   # the diagnosis only, on the failure path
the failure-path diagnosis only: the GAP naming the failure is already printed, this adds git's first stderr line ## [ -z "$gv_why" ] || echo "       ${gv_why%%$'\n'*}"
grep exits 1 on no match, which is valid here (an empty result is a real answer); the file read is guarded by file_readable above (no reference in a file is the clean case) ## scan_refs="$(grep -ohE '/?(tools|commands|templates)/[A-Za-z0-9._/-]+\.(sh|md)' "$repo_root/$f" | sort -u || true)"
outside a git repo (or a sandbox dir the tests point at) the porcelain list exits non-zero; the check falls back to repo_root and then to its documented no-BACKLOG skip ## | awk 'NR==1{sub(/^worktree /,""); path=$0} /^bare$/{bare=1} END{if (!bare) print path}' || true)"
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result (grep/sed over the fence-blanked BACKLOG text) ## < <(grep -nE '^### dir #[0-9]+ ' <<< "$fence_blanked" | cut -d: -f1)
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result (grep/sed over the fence-blanked BACKLOG text) ## < <(grep -nE '^### dir #[0-9]+ |^## ' <<< "$fence_blanked" | cut -d: -f1)
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result (grep/sed over the fence-blanked BACKLOG text) ## < <(sed -E 's/`[^`]*`//g' <<< "$fence_blanked")
best-effort by design: no gh, offline or unauthenticated is the documented degrade, and that check's OK line says so (needs gh) ## pr_state="$(cd "$repo_root" && gh pr view "$pr_num" --json state -q .state 2>/dev/null)" || continue
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result (the tag list was read by git_value, status checked) ## tags="$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<< "$tags_raw" | sed 's/^v//' | sort -u || true)"
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result ## | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result ## unreleased_count="$(grep -cE '^## \[Unreleased\]' <<< "$changelog_blanked" || true)"
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result ## total_sections="$(grep -cE '^## (\[Unreleased\]|\[[0-9]+\.[0-9]+\.[0-9]+\])' <<< "$changelog_blanked" || true)"
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result ## n_tags="$(printf '%s\n' "$tags" | grep -c . || true)"
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result ## ur_subheadings="$(grep -oE '^### (Added|Changed|Fixed)\b' <<< "$unreleased_body" | sed -E 's/^### //' || true)"
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result (the tag list was read by git_value, status checked) ## ct_tag_list="$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<< "$ct_tags_raw" | sed 's/^v//' || true)"
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result (the commit log was read by git_value, status checked) ## ct_commit_tickets="$(_extract_dir_tickets <<< "$ct_log" || true)"
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result (the fragment text was read with its status checked) ## $ct_fragment_text" || true)"
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result ## ps_lines="$(grep -nE '\$\{?PIPESTATUS' <<< "$stripped" | cut -d: -f1 | paste -sd, - || true)"
a pure filter over in-memory text: no producer to fail, and no-match is a valid empty result ## rest="$(printf '%s\n' "$defs" | grep -vxF "$exempt" || true)"
shopt is a best-effort glob-option toggle for an advisory machine-hygiene check; failing to set it only makes the glob match less ## shopt -s nullglob nocaseglob 2>/dev/null || true
advisory size estimate: du failing on one unreadable subpath only leaves that stray clone's size partly uncounted (the warn line says ~) ## kb="$(du -sk "$d" 2>/dev/null | awk '{print $1}')" || true
restores the glob options set above; best-effort, same advisory check ## shopt -u nullglob nocaseglob 2>/dev/null || true
the failure-path diagnosis only: the GAP naming the failure is already printed, this adds git's first stderr line ## sc_why="$(bash "$self_dir/shellcheck-targets.sh" "$repo_root" 2>&1 >/dev/null || true)"
the failure-path diagnosis only: the GAP naming the failure is already printed, this adds git's first stderr line ## [ -z "$sc_why" ] || echo "       ${sc_why%%$'\n'*}"
REGISTER


# The sites doctor.sh holds now: trimmed non-comment lines carrying a hiding shape.
# `|| true`, `|| echo` and `< <(` are always sites; `2>/dev/null)` is one only when the same line does not capture
# the status (`… || x_rc=$?`) — a capture on a line that ALSO carries `|| true` must not exempt that `|| true`.
sites="$( { grep -E '\|\| true|\|\| echo|< <\(' "$doctor"
            grep -E '2>/dev/null\)' "$doctor" | grep -vE '\|\| [A-Za-z_]*rc=\$\?' ; } \
  | sed -E 's/^[[:space:]]*//' | grep -vE '^#' | LC_ALL=C sort -u)"
registered="$(printf '%s\n' "$register" | grep -F ' ## ' | sed -E 's/^.* ## //' | LC_ALL=C sort -u)"

unregistered="$(LC_ALL=C comm -23 <(printf '%s\n' "$sites") <(printf '%s\n' "$registered"))"
stale="$(LC_ALL=C comm -13 <(printf '%s\n' "$sites") <(printf '%s\n' "$registered"))"
if [ -z "$unregistered" ]; then
  pass "every status-hiding site in tools/self/doctor.sh is checked or registered"
else
  fail "every status-hiding site in tools/self/doctor.sh is checked or registered" \
    "unregistered (check it, or register it with a reason): $unregistered"
fi
if [ -z "$stale" ]; then
  pass "no register entry names a site doctor.sh no longer has"
else
  fail "no register entry names a site doctor.sh no longer has" "stale: $stale"
fi
no_reason="$(printf '%s\n' "$register" | grep -F ' ## ' | awk -F' ## ' 'length($1) < 12 {print}')"
if [ -z "$no_reason" ]; then
  pass "every register entry carries a reason"
else
  fail "every register entry carries a reason" "too short: $no_reason"
fi

summary
