#!/usr/bin/env bash
# test_bypass_scan.sh — dir #842 slice 4 (docs/specs/842-guard-threat-model-1a-1b.md, B11, A18, A19): the known-bypass
# registers as an accumulator. Three groups:
#   A18 — the three directions over tools/self/known-bypass-shapes.tsv and the register files: every shape row names a
#         register file that holds its `[bypass:<class>]` key exactly once; every key a register holds has a shape row;
#         every command-reading register entry (the line holding its phrase) carries its key, and the entries about a
#         file's content or a machine state carry none. The checker is one function over a root directory, so the same
#         rules read broken copies: each mutant must turn its own rule red, or a green real run would prove nothing.
#         (The third direction — one `new-class … guards 2 90 felt` record per class in the guards' data dir — is the
#         operator machine's `accumulate.sh lint`, not CI: no data dir there, and HOME is sandboxed.)
#   A19 — tools/self/bypass-scan.sh on a fixture transcript tree (a candidate for a matching command, none for a
#         non-matching one or one outside the window, one parent plus two subagent files = ONE session, nothing written
#         under the repository), and the fixture classes through accumulate.sh (the dues, the ageing boundary, the
#         G0 sequence promoted -> fixed -> a recurrence).
# Keel-self-maintenance: it reads keel's own register files, which an adopter does not carry.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

SCAN="$REPO_ROOT/tools/self/bypass-scan.sh"
ACC="$REPO_ROOT/tools/self/accumulate.sh"
SHAPES_REL=tools/self/known-bypass-shapes.tsv
REGISTER_FILES='tools/pre-pr-gate.sh tests/lib.sh tools/lib/safe-write.sh SECURITY.md'   # every file that may hold a key
TAB="$(printf '\t')"

check_file "tools/self/bypass-scan.sh exists" "$SCAN"
check_file "$SHAPES_REL exists" "$REPO_ROOT/$SHAPES_REL"

# The register entries that read a COMMAND: phrase | class | region (header = the gate's header window, floor = the floor's
# Allowed-by-design block). Each phrase's line must carry the class's key exactly once.
ENTRIES='a leading word outside the skip set|gate-push:wrapper-outside-skip-set|header
zsh'"'"'s short forms|gate-push:zsh-short-form|header
a path to `gh`|gate-pr:path-to-gh|header
gh'"'"'s alias `gh pr new`|gate-pr:gh-pr-new-or-graphql|header
a second PR-opening command|gate-pr:two-pr-commands|header
an env that drops the home|gate-push:env-drops-home|header
an indexed assignment|gate-push:indexed-assignment-prefix|header
bash 3.2'"'"'s misreading|gate-push:heredoc-close-paren|header
a heredoc- or pipe-fed shell|gate-push:heredoc-fed-shell|header
an upper-case command word|gate-push:upper-case-command-word|header
group inside a|gate-push:case-in-group-in-subst|header
an upper-case command word|floor:upper-case-command-word|floor'
# The entries about a file's content or a machine state: no transcript to scan, so no key. phrase | file | region
NOCLASS='a hook started with stdin closed|tools/pre-pr-gate.sh|header
traps TERM|tests/lib.sh|whole
planted at the claimed temp path|tools/lib/safe-write.sh|whole'

# region_of ROOT FILE REGION — the lines of FILE a register entry may sit in.
region_of() {
  local root="$1" file="$2" region="$3"
  case "$region" in
    header) sed -n '1,/^# CLI subcommands/p' "$root/$file" ;;
    floor) awk '/Allowed by design:/ { f = 1 } f && !/^#/ { exit } f && /^#$/ { exit } f' "$root/$file" ;;
    *) cat "$root/$file" ;;
  esac
}

# keycount LINE_TEXT — how many `[bypass:` keys a line holds.
keycount() { grep -o -F '[bypass:' <<<"$1" | wc -l | tr -d ' '; }

# shape_classes ROOT — the class column of the shape table, header and comments dropped.
shape_classes() { awk -F'\t' '/^#/ || NF == 0 { next } !h { h = 1; next } { print $1 }' "$1/$SHAPES_REL"; }

# regcheck ROOT — one `fail:<rule>:<detail>` line per rule that does not hold under ROOT; nothing = all hold.
regcheck() {
  local root="$1" classes cls reg n line phrase region file tmp
  classes="$(shape_classes "$root")"
  [ -n "$classes" ] || echo "fail:t:the shape table has no rows"

  # (t) every class has exactly one row; every row names a register file that exists and a valid actor.
  while IFS= read -r cls; do
    [ -n "$cls" ] || continue
    n="$(grep -c -x -F "$cls" <<<"$classes")"
    [ "$n" = 1 ] || echo "fail:t:class $cls has $n rows"
  done <<<"$classes"
  while IFS="$TAB" read -r cls reg _ actor; do
    case "$cls" in ''|'#'*|class) continue ;; esac
    [ -f "$root/$reg" ] || echo "fail:t:[$cls] register file $reg does not exist"
    case "$actor" in any|subagent) ;; *) echo "fail:t:[$cls] actor '$actor'" ;; esac
    # (k1) the register file holds the class's key exactly once.
    if [ -f "$root/$reg" ]; then
      n="$(grep -o -F "[bypass:$cls]" "$root/$reg" | wc -l | tr -d ' ')"
      [ "$n" = 1 ] || echo "fail:k1:[$cls] $reg holds its key $n times"
    fi
  done <"$root/$SHAPES_REL"

  # (k2) every key a register file holds has a shape row.
  for file in $REGISTER_FILES; do
    [ -f "$root/$file" ] || continue
    tmp="$(grep -o -E '\[bypass:[a-z0-9:-]+\]' "$root/$file" | sed 's/^\[bypass://; s/\]$//' | sort -u)"
    while IFS= read -r cls; do
      [ -n "$cls" ] || continue
      grep -q -x -F "$cls" <<<"$classes" || echo "fail:k2:$file holds a key for [$cls] with no shape row"
    done <<<"$tmp"
  done

  # (e) every command-reading entry's phrase line carries its own key exactly once, and the class is in the table.
  while IFS='|' read -r phrase cls region; do
    [ -n "$phrase" ] || continue
    file=tools/pre-pr-gate.sh
    grep -q -x -F "$cls" <<<"$classes" || echo "fail:e:[$cls] has no shape row"
    n=0
    while IFS= read -r line; do
      case "$line" in *"$phrase"*) ;; *) continue ;; esac
      n=$((n + 1))
      case "$line" in *"[bypass:$cls]"*) [ "$(keycount "$line")" = 1 ] || echo "fail:e:[$cls] the line holding '$phrase' holds $(keycount "$line") keys" ;;
        *) echo "fail:e:[$cls] the line holding '$phrase' lacks its key" ;; esac
    done <<<"$(region_of "$root" "$file" "$region")"
    [ "$n" -ge 1 ] || echo "fail:e:[$cls] no line in the $region holds '$phrase'"
  done <<<"$ENTRIES"
  # every shape row is claimed by an entry (a row with no register line is a dead class).
  while IFS= read -r cls; do
    [ -n "$cls" ] || continue
    grep -q -F "|$cls|" <<<"$ENTRIES" || echo "fail:e:shape row [$cls] has no entry in this test's table"
  done <<<"$classes"

  # (n) the content/state entries carry no key.
  while IFS='|' read -r phrase file region; do
    [ -n "$phrase" ] || continue
    n=0
    while IFS= read -r line; do
      case "$line" in *"$phrase"*) ;; *) continue ;; esac
      n=$((n + 1))
      [ "$(keycount "$line")" = 0 ] || echo "fail:n:the line holding '$phrase' carries a key (no transcript to scan)"
    done <<<"$(region_of "$root" "$file" "$region")"
    [ "$n" -ge 1 ] || echo "fail:n:no line in $file holds '$phrase'"
  done <<<"$NOCLASS"
}

check_eq "A18 real tree: every shape/register direction holds" "" "$(regcheck "$REPO_ROOT")"

# --- broken copies: each must turn its own rule red ------------------------------------------------------------------
copy="$SANDBOX/shapes-copy"
mkdir -p "$copy/tools/lib" "$copy/tools/self" "$copy/tests"
fresh_copy() {
  local f
  for f in $REGISTER_FILES "$SHAPES_REL"; do cp "$REPO_ROOT/$f" "$copy/$f"; done
}

fresh_copy; replace_in_line_containing "$copy/tools/pre-pr-gate.sh" 'a leading word outside the skip set' ' [bypass:gate-push:wrapper-outside-skip-set]' ''
check_contains "mutant: a class loses its key in the gate → k1 and e fail" "$(regcheck "$copy")" 'fail:k1:[gate-push:wrapper-outside-skip-set]'

fresh_copy; printf 'gate-push:invented-shape\ttools/pre-pr-gate.sh\tgit[[:space:]]push\tany\n' >> "$copy/$SHAPES_REL"
check_contains "mutant: a shape row whose class no register names → k1 fails" "$(regcheck "$copy")" 'fail:k1:[gate-push:invented-shape]'

fresh_copy; printf 'gate-pr:path-to-gh\ttools/pre-pr-gate.sh\tgh\tany\n' >> "$copy/$SHAPES_REL"
check_contains "mutant: a class with two rows → t fails" "$(regcheck "$copy")" 'fail:t:class gate-pr:path-to-gh has 2 rows'

fresh_copy; replace_in_line_containing "$copy/tools/pre-pr-gate.sh" 'an indexed assignment' 'gate-push:indexed-assignment-prefix' 'gate-push:stray-key'
check_contains "mutant: a register key with no shape row → k2 fails" "$(regcheck "$copy")" 'fail:k2:tools/pre-pr-gate.sh holds a key for [gate-push:stray-key]'

fresh_copy; replace_in_line_containing "$copy/tools/pre-pr-gate.sh" 'a heredoc- or pipe-fed shell' ' [bypass:gate-push:heredoc-fed-shell]' ''
insert_before_line_containing "$copy/tools/pre-pr-gate.sh" 'a heredoc- or pipe-fed shell' '# [bypass:gate-push:heredoc-fed-shell] on the line before'
check_contains "mutant: the key moved off the phrase's line → e fails" "$(regcheck "$copy")" "fail:e:[gate-push:heredoc-fed-shell] the line holding 'a heredoc- or pipe-fed shell' lacks its key"

fresh_copy; replace_in_line_containing "$copy/tests/lib.sh" 'traps TERM' 'traps TERM' 'traps TERM [bypass:gate-push:env-drops-home]'
check_contains "mutant: a state entry that carries a key → n fails" "$(regcheck "$copy")" "fail:n:the line holding 'traps TERM' carries a key"

fresh_copy; replace_in_line_containing "$copy/tools/pre-pr-gate.sh" 'a non-literal verb' ' [bypass:floor:upper-case-command-word]' ''
check_contains "mutant: the floor entry loses its key → k1 fails" "$(regcheck "$copy")" 'fail:k1:[floor:upper-case-command-word]'

# --- the shape table is well formed and compiles; `classes` prints one new-class line per class -------------------------
run env KEEL_GUARDS_ACCUM_DIR="$SANDBOX/guards-acc-demo" bash "$SCAN" classes
check_status "classes -> exit 0" 0 "$STATUS"
n_rows="$(shape_classes "$REPO_ROOT" | wc -l | tr -d ' ')"
check_eq "classes prints one line per shape row" "$n_rows" "$(grep -c ' new-class ' <<<"$OUT")"
check_contains "classes names the owner, threshold, window and counts" "$OUT" ' guards 2 90 felt'
check_contains "classes writes into the configured data dir" "$OUT" "$SANDBOX/guards-acc-demo"
check_nodir "classes created no data dir (it only prints)" "$SANDBOX/guards-acc-demo"
run env KEEL_GUARDS_ACCUM_DIR="$SANDBOX/x" bash "$SCAN" data-dir
check_eq "data-dir honours KEEL_GUARDS_ACCUM_DIR" "$SANDBOX/x" "$OUT"
run env -u KEEL_GUARDS_ACCUM_DIR bash "$SCAN" data-dir
check_eq "data-dir default sits under HOME/.keel, outside any repository" "$HOME/.keel/guards-accumulator" "$OUT"

bad="$SANDBOX/bad-shapes.tsv"
printf 'class\tregister\tpattern\tactor\nbad class!\ta-register-file\tgit\tany\n' >"$bad"
run bash "$SCAN" classes --shapes "$bad"
check_status "a malformed class id -> exit 2" 2 "$STATUS"
printf 'class\tregister\tpattern\tactor\nok:one\ta-register-file\t(unclosed\tany\n' >"$bad"
run bash "$SCAN" classes --shapes "$bad"
check_status "a pattern that does not compile -> exit 2" 2 "$STATUS"
printf 'class\tregister\tpattern\tactor\nok:one\ta-register-file\tgit\tnobody\n' >"$bad"
run bash "$SCAN" classes --shapes "$bad"
check_status "an unknown actor -> exit 2" 2 "$STATUS"

# --- A19: the scan on a fixture transcript tree ------------------------------------------------------------------------
S1=00000000-0000-4000-8000-000000000001   # parent with two subagents
S2=00000000-0000-4000-8000-000000000002   # a heredoc-fed shell, newlines in the command
S3=00000000-0000-4000-8000-000000000003   # out of the window
S4=00000000-0000-4000-8000-000000000004   # a main-session upper-case git checkout (not a subagent's)
T="$SANDBOX/transcripts/-fixture-proj"
mkdir -p "$T/$S1/subagents"

# bashline FILE SESSION SIDECHAIN TIMESTAMP COMMAND — append one assistant line holding one Bash tool call.
bashline() {
  jq -n -c --arg s "$2" --argjson sc "$3" --arg ts "$4" --arg c "$5" \
    '{type: "assistant", sessionId: $s, isSidechain: $sc, timestamp: $ts,
      message: {role: "assistant", content: [{type: "text", text: "ok"}, {type: "tool_use", name: "Bash", input: {command: $c}}]}}' >>"$1"
}
bashline "$T/$S1.jsonl" "$S1" false 2026-09-10T10:00:00.000Z 'GIT push origin feature'
bashline "$T/$S1.jsonl" "$S1" false 2026-09-10T10:01:00.000Z 'git status'
bashline "$T/$S1/subagents/agent-a1.jsonl" "$S1" true 2026-09-10T10:02:00.000Z 'GIT checkout main'
bashline "$T/$S1/subagents/agent-a2.jsonl" "$S1" true 2026-09-10T10:03:00.000Z 'GIT reset --hard'
printf 'not json at all\n{"truncated":' >>"$T/$S1/subagents/agent-a2.jsonl"
bashline "$T/$S2.jsonl" "$S2" false 2026-09-11T10:00:00.000Z "$(printf "bash <<'X'\ngit push --no-verify\nX\n")"
bashline "$T/$S3.jsonl" "$S3" false 2026-01-01T10:00:00.000Z 'GIT push origin old'
bashline "$T/$S4.jsonl" "$S4" false 2026-09-12T10:00:00.000Z 'GIT checkout main'
S6=00000000-0000-4000-8000-000000000006   # a word merely ending in sh, or a script named x.sh, before a heredoc: no heredoc-fed-shell candidate
bashline "$T/$S6.jsonl" "$S6" false 2026-09-14T10:00:00.000Z "$(printf "crash <<'X'\\ngit push origin x\\nX\\n")"
bashline "$T/$S6.jsonl" "$S6" false 2026-09-14T10:01:00.000Z "$(printf "run.sh <<'X'\\ngit push origin x\\nX\\n")"
S5=00000000-0000-4000-8000-000000000005   # an ordinary commit-message heredoc and a plain push: no heredoc class
bashline "$T/$S5.jsonl" "$S5" false 2026-09-13T10:00:00.000Z "$(printf "git commit -m \"\$(cat <<'EOF'\nfix the thing\nEOF\n)\"\ngit push origin feature\n")"
bashline "$T/$S5.jsonl" "$S5" false 2026-09-13T10:05:00.000Z 'echo "gh pr create" > note.txt; git push origin feature'

repo_state_before="$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)"
cands="$SANDBOX/cands.tsv"
run bash "$SCAN" scan --transcripts "$SANDBOX/transcripts" --as-of 2026-09-15 --days 30 --out "$cands"
check_status "scan -> exit 0" 0 "$STATUS"
check_file "scan wrote the candidate file" "$cands"
c="$(cat "$cands")"
check_contains "candidate: the upper-case git push in the parent session" "$c" "gate-push:upper-case-command-word${TAB}$S1"
check_contains "candidate: the newline-bearing heredoc-fed shell (newlines flattened)" "$c" "gate-push:heredoc-fed-shell${TAB}$S2"
check_absent "no candidate for 'git status'" "$c" 'git status'
check_absent "an ordinary commit-message heredoc followed by a push is no heredoc candidate" "$c" "$S5"
check_absent "a word merely ending in sh before a heredoc is no heredoc-fed-shell candidate" "$c" "$S6"
check_absent "no candidate for a command outside the window" "$c" "$S3"
check_absent "a main-session upper-case git checkout is not a subagent's (actor subagent)" "$c" "floor:upper-case-command-word${TAB}$S4"
floor_sessions="$(awk -F'\t' '$1 == "floor:upper-case-command-word" { print $2 }' "$cands" | sort -u)"
check_eq "one parent + two subagent files -> candidates under ONE session (the parent's)" "$S1" "$floor_sessions"
check_eq "both subagent commands are listed under that session" "2" "$(awk -F'\t' '$1 == "floor:upper-case-command-word" { n++ } END { print n + 0 }' "$cands")"
check_contains "the malformed transcript lines were skipped, the scan counts the commands it read" "$OUT" 'command(s) scanned'
check_absent "stdout carries counts, never command text" "$OUT" 'git push'
check_eq "scan wrote nothing under the repository" "$repo_state_before" "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)"

ln -s "$SANDBOX/transcripts" "$SANDBOX/transcripts-link"
run bash "$SCAN" scan --transcripts "$SANDBOX/transcripts-link" --as-of 2026-09-15 --days 30 --out "$SANDBOX/cands-link.tsv"
check_contains "a symlinked transcripts root is walked (the KB links ~/.claude/projects)" "$(cat "$SANDBOX/cands-link.tsv")" "gate-push:heredoc-fed-shell${TAB}$S2"

# the candidate file is personal data: owner-only whatever the caller's umask
mode_out="$SANDBOX/cands-mode.tsv"
( umask 022; bash "$SCAN" scan --transcripts "$SANDBOX/transcripts" --as-of 2026-09-15 --days 30 --out "$mode_out" >/dev/null 2>&1 )
check_eq "an explicit --out is created owner-only (0600) under umask 022" "-rw-------" "$(ls -l "$mode_out" | cut -c1-10)"
# ...also when the file already exists with looser permissions, and a non-regular --out is refused (never removed)
printf 'old\n' >"$mode_out"; chmod 644 "$mode_out"
bash "$SCAN" scan --transcripts "$SANDBOX/transcripts" --as-of 2026-09-15 --days 30 --out "$mode_out" >/dev/null 2>&1
check_eq "an existing --out file is tightened to 0600 too" "-rw-------" "$(ls -l "$mode_out" | cut -c1-10)"
ln -s "$mode_out" "$SANDBOX/cands-link-out.tsv"
run bash "$SCAN" scan --transcripts "$SANDBOX/transcripts" --as-of 2026-09-15 --days 30 --out "$SANDBOX/cands-link-out.tsv"
check_status "--out that is a symlink -> exit 2" 2 "$STATUS"
check_file "...and the link's target survives the cleanup trap" "$mode_out"
run bash "$SCAN" scan --transcripts "$SANDBOX/transcripts" --as-of 2026-09-15 --days 30 --out /dev/null
check_status "--out /dev/null (not a regular file) -> exit 2" 2 "$STATUS"
# a failed scan leaves no half-written candidate file behind
printf 'class\tregister\tpattern\tactor\nok:one\ta-register-file\t(unclosed\tany\n' >"$SANDBOX/bad-shapes2.tsv"
run bash "$SCAN" scan --transcripts "$SANDBOX/transcripts" --shapes "$SANDBOX/bad-shapes2.tsv" --as-of 2026-09-15 --days 30 --out "$SANDBOX/cands-failed.tsv"
check_status "a malformed shape table -> exit 2" 2 "$STATUS"
check_nofile "...and the candidate file is removed" "$SANDBOX/cands-failed.tsv"
run bash "$SCAN" scan --transcripts "$SANDBOX/transcripts" --since 2026-10-20 --as-of 2026-10-15
check_status "--since later than --as-of -> exit 2" 2 "$STATUS"
run env -u HOME -u KEEL_HOME -u KEEL_GUARDS_ACCUM_DIR bash "$SCAN" classes
check_status "classes with no data dir to name -> exit 2, no half-printed lines" 2 "$STATUS"
check_absent "...and prints no new-class line" "$OUT" ' new-class '
run bash "$SCAN" scan --transcripts "$SANDBOX/transcripts" --as-of 2026-09-15 --days 30 --out "$REPO_ROOT/bypass-candidates.tsv"
check_status "--out inside the repository is refused (exit 2)" 2 "$STATUS"
check_nofile "...and nothing was created there" "$REPO_ROOT/bypass-candidates.tsv"
new_repo "$SANDBOX/some-other-repo" >/dev/null 2>&1
run bash "$SCAN" scan --transcripts "$SANDBOX/transcripts" --as-of 2026-09-15 --days 30 --out "$SANDBOX/some-other-repo/c.tsv"
check_status "--out inside ANY git work tree is refused" 2 "$STATUS"
mkdir -p "$SANDBOX/scratch-tmp"
run env TMPDIR="$SANDBOX/scratch-tmp" bash "$SCAN" scan --transcripts "$SANDBOX/transcripts" --as-of 2026-09-15 --days 30
check_status "no --out -> a scratch file, exit 0" 0 "$STATUS"
dflt="$(sed -n 's/^bypass-scan: candidates written to \(.*\) (since.*/\1/p' <<<"$OUT")"
check_file "the default scratch file exists" "$dflt"
case "$dflt" in "$REPO_ROOT"/*) fail "the default scratch file is outside the repository" "$dflt" ;; *) pass "the default scratch file is outside the repository" ;; esac
run bash "$SCAN" scan --transcripts "$SANDBOX/no-such-dir"
check_status "a missing transcripts dir -> exit 2" 2 "$STATUS"
run bash "$SCAN" scan --transcripts "$SANDBOX/transcripts" --since 2026-09-01 --days 5
check_status "--since with --days -> exit 2" 2 "$STATUS"
run bash "$SCAN" scan --transcripts "$SANDBOX/transcripts" --as-of 2026-13-45
check_status "a bad --as-of -> exit 2" 2 "$STATUS"

# --- A19: the fixture classes through accumulate.sh -------------------------------------------------------------
D="$SANDBOX/guards-acc"
ASOF=2026-10-15
acc() { bash "$ACC" --dir "$D" --as-of "$ASOF" "$@"; }
acc init >/dev/null 2>&1
for id in wf-two wf-single wf-aged wf-89 wf-sub leak-one leak-pre; do
  acc new-class "gate-pr:$id" "title $id" "tools/pre-pr-gate.sh $id" guards 2 90 felt >/dev/null 2>&1
done
# sight CLASS DATE SESSION DANGER
sight() { acc add "$2" "gate-pr:$1" guards "session:$3" yes "$4" fixture-model "fixture:1" >/dev/null 2>&1; }
sight wf-two 2026-10-01 aaaa no
sight wf-two 2026-10-05 bbbb no
sight wf-single 2026-10-05 aaaa no
sight wf-aged 2026-10-05 aaaa no
sight wf-aged 2026-07-17 bbbb no      # exactly 90 days before the as-of day: stops counting
sight wf-89 2026-10-05 aaaa no
sight wf-89 2026-07-18 bbbb no        # 89 days: still counts
sight wf-sub 2026-10-05 pppp no       # a subagent's sighting, under its parent's uuid
sight wf-sub 2026-10-06 pppp no       # a second subagent of the same parent: the same source
sight leak-one 2026-10-09 cccc yes    # one felt danger: due at once
sight leak-pre 2026-10-14 dddd yes
run bash "$ACC" --dir "$D" --as-of "$ASOF" due --owner guards
dues="$(sort <<<"$OUT" | tr '\n' ' ')"
check_eq "due: two distinct sessions in the window, the 89-day pair, the felt danger, and nothing else" \
  "gate-pr:leak-one gate-pr:leak-pre gate-pr:wf-89 gate-pr:wf-two " "$dues"
# the G0 sequence: promoted -> fixed at the closure date -> a recurrence is due only when dated after it.
acc promote gate-pr:leak-one dir-9001 >/dev/null 2>&1
acc promote gate-pr:leak-pre dir-9002 >/dev/null 2>&1
run bash "$ACC" --dir "$D" --as-of "$ASOF" due --owner guards
check_absent "a promoted class is not due" "$OUT" 'leak-one'
acc fixed gate-pr:leak-one dir-9001 --date 2026-10-10 >/dev/null 2>&1
acc fixed gate-pr:leak-pre dir-9002 --date 2026-10-16 >/dev/null 2>&1
run bash "$ACC" --dir "$D" --as-of "$ASOF" due --owner guards
check_absent "fixed: the sighting dated before the closure does not make the class due" "$OUT" 'leak-one'
check_absent "fixed (closure later than every sighting): not due" "$OUT" 'leak-pre'
sight leak-one 2026-10-12 eeee yes
run bash "$ACC" --dir "$D" --as-of "$ASOF" due --owner guards
check_contains "fixed: a sighting dated after the closure makes the class due again" "$OUT" 'gate-pr:leak-one'
sight leak-pre 2026-10-09 ffff yes
run bash "$ACC" --dir "$D" --as-of "$ASOF" due --owner guards
check_absent "fixed: a sighting dated before the closure does not" "$OUT" 'leak-pre'
run bash "$ACC" --dir "$D" lint
check_status "the fixture data dir lints clean" 0 "$STATUS"

summary
