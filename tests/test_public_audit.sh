#!/usr/bin/env bash
# public-audit — GAP on declared-private tokens and non-public-safe history identities; WARN on
# heuristic hits (home paths, content emails, Cyrillic); allowlist + --no-history behaviour.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

pa="$REPO_ROOT/tools/public-audit.sh"

# Pin the personal-literals file to /dev/null by default (dir #719 B14: a set-but-missing path is now a
# GAP, so the old nonexistent sandbox path would turn every exit-0 check red), so a real
# ~/.claude/secret-scan-personal on the dev machine can never leak into these tests.
# Personal-literal tests below override this per-invocation with env.
export SECRET_SCAN_PERSONAL_FILE=/dev/null

# a repo with one commit authored+committed by $1
repo_by() {
  local d; d="$(mktemp -d "$SANDBOX/pa.XXXXXX")"
  git -C "$d" init -q
  printf 'hello\n' > "$d/f.txt"; git -C "$d" add f.txt
  git -C "$d" -c user.email="$1" -c user.name=dev commit -qm init
  printf '%s' "$d"
}
commit_in() { git -C "$1" add -A; git -C "$1" -c user.email=dev@example.com -c user.name=dev commit -qm "$2"; }

# --help prints usage and exits 0 (a newcomer's reflex command must not error)
run bash "$pa" --help
check_status "--help → exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"

# clean: identity on the built-in safe list, no tokens
d="$(repo_by dev@example.com)"
run bash "$pa" "$d"
check_status "safe identity + clean tree → exit 0" 0 "$STATUS"
check_contains "reports no blockers" "$OUT" "no publication blockers"

# a corporate/personal identity in history → GAP
d="$(repo_by person@corp.com)"
run bash "$pa" "$d"
check_status "non-safe identity in history → GAP exit 1" 1 "$STATUS"
check_contains "names the leaked email" "$OUT" "person@corp.com"
# ...and --no-history skips that identity scan
run bash "$pa" --no-history "$d"
check_status "--no-history skips the identity GAP → exit 0" 0 "$STATUS"

# a declared-private token present in the tree → GAP
d="$(repo_by dev@example.com)"
printf 'internal codename ACME-X\n' > "$d/notes.txt"; commit_in "$d" notes
run bash "$pa" --token 'ACME-X' "$d"
check_status "token in tree → GAP" 1 "$STATUS"
check_contains "names the token (tree)" "$OUT" "private token /ACME-X/ in tracked tree"

# a declared token that STARTS WITH A DASH must still GAP, in tree/history/binary (regression: an
# unquoted `-- `-less grep/git-grep call would parse a dash-leading pattern as an option instead of a
# search term, and the swallowed error read as a false-clean)
d="$(repo_by dev@example.com)"
printf -- '-leaked-id-1234 is here\n' > "$d/dash.txt"; commit_in "$d" dash
run bash "$pa" --no-history --token '-leaked-id-1234' "$d"
check_status "dash-leading token in tree → GAP (not a silent false-clean)" 1 "$STATUS"
check_contains "names the dash-leading token (tree)" "$OUT" "private token /-leaked-id-1234/ in tracked tree"

d="$(repo_by dev@example.com)"
{ utf16le "-leaked-id-1234 in a binary blob"; } > "$d/dash.bin"
commit_in "$d" "add dash binary fixture"
run bash "$pa" --token '-leaked-id-1234' "$d"
check_status "dash-leading token in a binary blob → GAP" 1 "$STATUS"
check_contains "names the dash-leading token (binary blob)" "$OUT" "private token /-leaked-id-1234/ in a binary blob"

# dir #509 F6: a STAGED-but-UNCOMMITTED UTF-16LE binary carrying a declared token must still GAP, in
# BOTH default and --no-history mode — tree_grep's `git grep -I` skips binary content outright, and
# the history-only binary decoder (scan_binary_blobs) only sees objects reachable from a commit, so
# before this fix both modes read clean on a staged-only binary (verified reproduction, drydock V1).
d="$(repo_by dev@example.com)"
{ utf16le "token SeekritStagedName only staged"; } > "$d/staged.bin"
git -C "$d" add staged.bin   # staged, deliberately never committed
run bash "$pa" --token 'SeekritStagedName' "$d"
check_status "staged-only binary token, default mode → GAP exit 1" 1 "$STATUS"
check_contains "names the staged binary file (default mode)" "$OUT" \
  "private token /SeekritStagedName/ in a binary file in the working tree — staged.bin"
run bash "$pa" --no-history --token 'SeekritStagedName' "$d"
check_status "staged-only binary token, --no-history mode → GAP exit 1" 1 "$STATUS"
check_contains "names the staged binary file (--no-history mode)" "$OUT" \
  "private token /SeekritStagedName/ in a binary file in the working tree — staged.bin"

# dir #509 F6 review round: `git diff`/`git diff --cached` print paths relative to the REPO ROOT even
# under `-C <subdir>`, while `git ls-files` prints paths relative to that subdir — auditing a
# subdirectory (a plausible monorepo use) must still resolve the diff-sourced path correctly rather
# than doubling/mis-joining it against the audited DIR (verified live reproduction; caught by /polish's
# own review round, not the original ticket's fixtures).
d="$(repo_by dev@example.com)"
mkdir -p "$d/sub"
{ utf16le "token SeekritSubdirName in a subdir"; } > "$d/sub/staged-sub.bin"
git -C "$d" add sub/staged-sub.bin
run bash "$pa" --token 'SeekritSubdirName' "$d/sub"
check_status "staged binary token, DIR is a subdirectory → GAP exit 1" 1 "$STATUS"
check_contains "names the file relative to the audited subdirectory, not doubled" "$OUT" \
  "private token /SeekritSubdirName/ in a binary file in the working tree — staged-sub.bin"

# dir #509 F6 review round: an ALREADY-COMMITTED, untouched binary's token must still GAP under
# --no-history — the working-tree pass restricts to dirty (staged/modified/untracked) files in DEFAULT
# mode only, leaning on the history pass for everything else; --no-history has no history pass to lean
# on, so it must fall back to scanning every tracked file, the same unscoped coverage tree_grep's own
# text check already has in that mode (verified live reproduction).
d="$(repo_by dev@example.com)"
{ utf16le "token SeekritCommittedName untouched"; } > "$d/committed.bin"
commit_in "$d" "add committed binary"
run bash "$pa" --no-history --token 'SeekritCommittedName' "$d"
check_status "already-committed, untouched binary token under --no-history → GAP exit 1" 1 "$STATUS"
check_contains "names the committed binary file under --no-history" "$OUT" \
  "private token /SeekritCommittedName/ in a binary file in the working tree — committed.bin"
# ...and the same file is NOT re-decoded by the working-tree pass in DEFAULT mode (it's clean/unmodified,
# so the history pass alone covers it) — only one binary-blob mention, from history, not "working tree".
run bash "$pa" --token 'SeekritCommittedName' "$d"
check_status "same committed binary, default mode → GAP exit 1 (via history pass)" 1 "$STATUS"
check_contains "found via the history pass" "$OUT" "in a binary blob in git history — committed.bin"
check_absent "NOT re-decoded by the working-tree pass (already unmodified/clean)" "$OUT" \
  "in a binary file in the working tree"

# dir #509 F6 review round (a second delta round): an UNTRACKED binary's token must still GAP under
# --no-history too — widening the --no-history file list to `git ls-files` (every TRACKED file, to
# close the gap above) must not silently drop the untracked case default mode already covers via
# `git ls-files --others` (regression caught live by a delta re-review of the first fix).
d="$(repo_by dev@example.com)"
{ utf16le "token SeekritUntrackedName here"; } > "$d/untracked.bin"   # never git add-ed
run bash "$pa" --no-history --token 'SeekritUntrackedName' "$d"
check_status "untracked binary token under --no-history → GAP exit 1" 1 "$STATUS"
check_contains "names the untracked binary file under --no-history" "$OUT" \
  "private token /SeekritUntrackedName/ in a binary file in the working tree — untracked.bin"

# dir #509 F6 review round: a SYMLINK must not have its TARGET's bytes decoded — git tracks a symlink's
# content as its link-text (a short string), never the file it points to; scanning the target would
# read content this audit was never asked to touch and diverges from how git/tree_grep treat the link.
if command -v ln >/dev/null 2>&1; then
  d="$(repo_by dev@example.com)"
  outside="$SANDBOX/pa-symlink-target.bin"        # OUTSIDE $d — never itself audited by this run
  { utf16le "token SeekritSymlinkTargetName elsewhere"; } > "$outside"
  ln -s "$outside" "$d/link.bin"
  git -C "$d" add link.bin
  run bash "$pa" --token 'SeekritSymlinkTargetName' "$d"
  check_status "a staged symlink's TARGET content is not scanned → exit 0" 0 "$STATUS"
  check_absent "no GAP from following the symlink" "$OUT" "SeekritSymlinkTargetName"
fi

# dir #509 F7: a declared token inside an ANNOTATED-TAG message body must GAP — the token loop's
# `-G`/`--grep` pair searches commit diffs and messages only, never a tag body (which `git log` never
# shows in any format), so before this fix it read clean (verified reproduction, drydock V1).
d="$(repo_by dev@example.com)"
git -C "$d" -c user.email=dev@example.com -c user.name=dev tag -a probe \
  -m "$(printf 'release\n\nPrivateTagTokenXYZ')"
run bash "$pa" --token 'PrivateTagTokenXYZ' "$d"
check_status "declared token in an annotated-tag body → GAP exit 1" 1 "$STATUS"
check_contains "names the tag-body token hit" "$OUT" "private token /PrivateTagTokenXYZ/ in an annotated-tag message"

# a token scrubbed from the tree but alive in history → still GAP
d="$(repo_by dev@example.com)"
printf 'ACME-X\n' > "$d/secret.txt"; commit_in "$d" add
git -C "$d" rm -q secret.txt; commit_in "$d" remove
run bash "$pa" --token 'ACME-X' "$d"
check_status "token only in history → GAP" 1 "$STATUS"
check_contains "names the token (history)" "$OUT" "in git history"

# home path → WARN (advisory, still exit 0)
d="$(repo_by dev@example.com)"
printf 'path = /Users/alice/keys\n' > "$d/p.txt"; commit_in "$d" path
run bash "$pa" --no-history "$d"
check_status "home path → exit 0 (WARN)" 0 "$STATUS"
check_contains "warns about a home path" "$OUT" "absolute home path"

# an email in file content → WARN; an allow-email config entry suppresses it
d="$(repo_by dev@example.com)"
printf 'contact dev@corp.io\n' > "$d/c.txt"; commit_in "$d" contact
run bash "$pa" --no-history "$d"
check_contains "warns about a content email" "$OUT" "email in tracked content"
printf 'allow-email: @corp\\.io\n' > "$d/.public-audit"
run bash "$pa" --no-history "$d"
check_absent "allow-email config suppresses it" "$OUT" "email in tracked content"

# Cyrillic in a tracked file → WARN (bytes written at runtime; the test source stays ASCII)
d="$(repo_by dev@example.com)"
printf '\xd0\xb7\xd0\xb0\xd0\xbc\xd0\xb5\xd1\x82\xd0\xba\xd0\xb0\n' > "$d/ru.txt"; commit_in "$d" ru
run bash "$pa" --no-history "$d"
check_status "Cyrillic → exit 0 (WARN)" 0 "$STATUS"
check_contains "warns about Cyrillic" "$OUT" "Cyrillic"

# a NON-ASCII (Cyrillic) name inside a UTF-32 BINARY blob → WARN via the iconv-UTF-32 decode pass.
# ASCII-in-UTF-32 survives NUL-strip, but a multi-byte code point needs the explicit UTF-32 decode —
# the felt leak class (a real name inside a binary fixture), here in UTF-32 rather than UTF-16.
# iconv-guarded; bytes built at runtime so this test source stays ASCII.
# NOTE: no --no-history — the binary-blob scan runs in the history pass (scan_binary_blobs over
# --all); the local sandbox repo has no remote, so the run stays offline.
cyr32="$(printf '\xd0\x98\xd0\xb2\xd0\xb0\xd0\xbd\xd0\xbe\xd0\xb2')"   # "Ivanov" (Cyrillic) in UTF-8
if command -v iconv >/dev/null 2>&1 && printf '%s' "$cyr32" | iconv -f UTF-8 -t UTF-32LE >/dev/null 2>&1; then
  d="$(repo_by dev@example.com)"
  printf '%s' "$cyr32" | iconv -f UTF-8 -t UTF-32LE > "$d/name32.bin"
  commit_in "$d" bin32
  run bash "$pa" "$d"
  check_status "UTF-32 binary Cyrillic → exit 0 (WARN)" 0 "$STATUS"
  check_contains "warns about Cyrillic in a binary blob" "$OUT" "Cyrillic text in a binary blob"
else
  pass "UTF-32 binary Cyrillic test skipped (no iconv / no UTF-32 converter)"
fi

# agent/session tooling metadata in a commit message → WARN (not a GAP). Built from parts so this
# test's own source carries no whole session token (keeps the repo's audit clean).
d="$(repo_by dev@example.com)"
sess="$(printf 'Claude-%s: https://claude.ai/code/%s_01ABCxyz' 'Session' 'session')"
git -C "$d" -c user.email=dev@example.com -c user.name=dev commit --allow-empty -q \
  -m "$(printf 'work\n\n%s' "$sess")"
run bash "$pa" "$d"
check_status "session metadata in a message → exit 0 (WARN)" 0 "$STATUS"
check_contains "warns about agent/session metadata" "$OUT" "session metadata"

# the same trailer in an ANNOTATED TAG message — not a commit message, so `git log` alone is blind
# to it; the check must mirror section 5's for-each-ref tag pass
d="$(repo_by dev@example.com)"
git -C "$d" -c user.email=dev@example.com -c user.name=dev tag -a v1 \
  -m "$(printf 'release\n\n%s' "$sess")"
run bash "$pa" "$d"
check_status "session metadata in a tag message → exit 0 (WARN)" 0 "$STATUS"
check_contains "warns about session metadata in a tag" "$OUT" "session metadata"

# history-content heuristics: a personal email + home path in a COMMIT MESSAGE BODY (not in any file)
# — the tree scan can't see it; the history pass must. WARN, not GAP.
d="$(repo_by dev@example.com)"
git -C "$d" -c user.email=dev@example.com -c user.name=dev commit --allow-empty -q \
  -m "$(printf 'fix\n\nContact %s about it; key at %s' 'jane@gmail.com' '/Users/realname/k.pem')"
run bash "$pa" "$d"
check_status "history-message leak → exit 0 (WARN, not GAP)" 0 "$STATUS"
check_contains "warns about an email in git history" "$OUT" "email in git history"
check_contains "warns about a home path in git history" "$OUT" "home path in git history"

# host PR refs: a leak reachable ONLY from a refs/pull/*-style ref (the host's closed-PR cache) must be
# detected — git log --all doesn't see it, so this is the false-clean the audit caught. Simulate with a
# local bare remote serving such a ref (hermetic, no network).
bare="$(mktemp -d "$SANDBOX/bare.XXXXXX")"; git init -q --bare "$bare"
d="$(repo_by dev@example.com)"
git -C "$d" remote add origin "$bare"
git -C "$d" push -q origin HEAD:main
git -C "$d" -c user.email=person@corp.com -c user.name=x commit --allow-empty -q -m leak
git -C "$d" push -q origin HEAD:refs/pull/1/head     # leak lives only in the PR ref...
git -C "$d" reset -q --hard HEAD~1                    # ...not in main / any local ref
run bash "$pa" "$d"
check_status "leak only in a refs/pull ref → GAP exit 1 (no false clean)" 1 "$STATUS"
check_contains "flags the PR-ref identity" "$OUT" "host PR ref"

# host PR refs apply the SAME heuristics as local history, not just identity/email: a home path living
# ONLY in a PR-ref commit (authored by a safe identity, so no GAP) must still be WARNed.
bare="$(mktemp -d "$SANDBOX/bare.XXXXXX")"; git init -q --bare "$bare"
d="$(repo_by dev@example.com)"
git -C "$d" remote add origin "$bare"
git -C "$d" push -q origin HEAD:main
git -C "$d" -c user.email=dev@example.com -c user.name=dev commit --allow-empty -q \
  -m "$(printf 'fix\n\nkey at %s' '/Users/realname/k.pem')"
git -C "$d" push -q origin HEAD:refs/pull/2/head     # home path lives only in the PR ref...
git -C "$d" reset -q --hard HEAD~1                    # ...not in main / any local ref
run bash "$pa" "$d"
check_status "home path only in a PR ref → exit 0 (WARN, safe identity)" 0 "$STATUS"
check_contains "warns about the PR-ref home path" "$OUT" "home path in a host PR ref"

# host PR refs include GitHub's synthetic …/merge ref, not just …/head: a leak reachable ONLY from a
# refs/pull/*/merge ref must also be caught.
bare="$(mktemp -d "$SANDBOX/bare.XXXXXX")"; git init -q --bare "$bare"
d="$(repo_by dev@example.com)"
git -C "$d" remote add origin "$bare"
git -C "$d" push -q origin HEAD:main
git -C "$d" -c user.email=person@corp.com -c user.name=x commit --allow-empty -q -m leak
git -C "$d" push -q origin HEAD:refs/pull/7/merge     # leak lives only in the MERGE ref...
git -C "$d" reset -q --hard HEAD~1                     # ...not in main / head / any local ref
run bash "$pa" "$d"
check_status "leak only in a refs/pull/*/merge ref → GAP exit 1" 1 "$STATUS"
check_contains "flags the merge-ref identity" "$OUT" "host PR ref"

# multi-remote: a non-GitHub remote that sorts FIRST alphabetically must not hide a later remote's
# PR-ref leak (regression for `git remote | head -1`, which picked the wrong remote and skipped scan).
bare="$(mktemp -d "$SANDBOX/bare.XXXXXX")"; git init -q --bare "$bare"
d="$(repo_by dev@example.com)"
git -C "$d" remote add aaa-mirror "$SANDBOX/no-such-mirror.git"   # sorts first; has no refs/pull/*
git -C "$d" remote add origin "$bare"
git -C "$d" push -q origin HEAD:main
git -C "$d" -c user.email=person@corp.com -c user.name=x commit --allow-empty -q -m leak
git -C "$d" push -q origin HEAD:refs/pull/1/head
git -C "$d" reset -q --hard HEAD~1
run bash "$pa" "$d"
check_status "multi-remote: a later remote's PR-ref leak still GAPs" 1 "$STATUS"
check_contains "scanned the GitHub-shaped remote despite a non-GitHub one sorting first" "$OUT" "host PR ref"

# SCALE regression (S2 — pipefail + SIGPIPE in the PR-ref token scan): a --token matching EARLY in a LARGE
# pr_hist made the old `printf … | grep -qE "$t" && gap` SIGPIPE printf (it keeps writing after grep matches
# and exits); `set -o pipefail` turned the pipeline into 141, so `&& gap` never fired and a real private-token
# leak passed CLEAN. The bulk commit pushes pr_hist well past the pipe buffer, then the token rides the newest
# commit (first in `git log -p`) so grep matches early — exactly the shape that triggered the false clean.
bare="$(mktemp -d "$SANDBOX/bare.XXXXXX")"; git init -q --bare "$bare"
d="$(repo_by dev@example.com)"
git -C "$d" remote add origin "$bare"
git -C "$d" push -q origin HEAD:main
i=1; while [ "$i" -le 4000 ]; do printf 'padding line %s of bulk PR-ref history\n' "$i"; i=$((i + 1)); done > "$d/bulk.txt"
git -C "$d" add bulk.txt
git -C "$d" -c user.email=dev@example.com -c user.name=dev commit -q -m bulk        # big older diff...
printf 'config token ACME-PR-TOKEN here\n' > "$d/leak.txt"
git -C "$d" add leak.txt
git -C "$d" -c user.email=dev@example.com -c user.name=dev commit -q -m 'add token' # ...token in the newest
git -C "$d" push -q origin HEAD:refs/pull/9/head     # both live only in the PR ref...
git -C "$d" reset -q --hard HEAD~2                    # ...not in main / tree / any local ref
run bash "$pa" --token 'ACME-PR-TOKEN' "$d"
check_status "token early in a LARGE PR-ref history → GAP exit 1 (S2, no SIGPIPE false-clean)" 1 "$STATUS"
check_contains "flags the PR-ref token at scale" "$OUT" "private token /ACME-PR-TOKEN/ in a host PR ref"

# a declared token that STARTS WITH A DASH, reachable only from a refs/pull ref, must still GAP (same
# missing-`--` regression class as the tree/binary cases above, at the PR-ref token call site)
bare="$(mktemp -d "$SANDBOX/bare.XXXXXX")"; git init -q --bare "$bare"
d="$(repo_by dev@example.com)"
git -C "$d" remote add origin "$bare"
git -C "$d" push -q origin HEAD:main
git -C "$d" -c user.email=dev@example.com -c user.name=dev commit --allow-empty -q \
  -m "$(printf 'fix\n\n-leaked-id-1234 is here')"
git -C "$d" push -q origin HEAD:refs/pull/3/head
git -C "$d" reset -q --hard HEAD~1
run bash "$pa" --token '-leaked-id-1234' "$d"
check_status "dash-leading token only in a refs/pull ref → GAP (not a silent false-clean)" 1 "$STATUS"
check_contains "flags the dash-leading PR-ref token" "$OUT" "private token /-leaked-id-1234/ in a host PR ref"

# a personal email in an ANNOTATED-TAG message body (which `git log -p` omits) → WARN
d="$(repo_by dev@example.com)"
git -C "$d" -c user.email=dev@example.com -c user.name=dev tag -a v9 -m "$(printf 'release\n\nby %s' 'zoe@gmail.com')"
run bash "$pa" "$d"
check_status "personal email in an annotated-tag body → exit 0 (WARN)" 0 "$STATUS"
check_contains "warns about the tag-body email" "$OUT" "email in git history"

# a shallow clone carries only partial history, so a clean result isn't trustworthy → a visible WARN
src="$(repo_by dev@example.com)"
git -C "$src" -c user.email=leaker@realcorp.com -c user.name=x commit --allow-empty -q -m deep
git -C "$src" -c user.email=dev@example.com -c user.name=dev commit --allow-empty -q -m recent
shallow="$(mktemp -d "$SANDBOX/shallow.XXXXXX")/c"
git clone -q --depth 1 "file://$src" "$shallow" 2>/dev/null
run bash "$pa" "$shallow"
check_contains "shallow clone → WARN that history is incomplete" "$OUT" "shallow clone"

# an orphaned refs/keel-pr-audit/* (e.g. from an interrupted run) is reaped on exit, even with no remote
d="$(repo_by dev@example.com)"
git -C "$d" update-ref refs/keel-pr-audit/head-stale HEAD
run bash "$pa" "$d"
left="$(git -C "$d" for-each-ref refs/keel-pr-audit/ | wc -l | tr -d ' ')"
check_status "orphaned PR-audit temp refs are reaped" 0 "$left"

# a broken allow-email ERE in .public-audit is reported clearly and ignored — not raw `grep: bad regex`.
# Whether `foo(bar` is "broken" depends on the grep: GNU rejects it, busybox accepts it as a literal.
# Gate on what THIS platform's grep actually does so the test is correct on both.
d="$(repo_by dev@example.com)"
printf 'allow-email: foo(bar\n' > "$d/.public-audit"
run bash "$pa" --no-history "$d"
check_absent "no raw grep bad-regex spew" "$OUT" "bad regex"
if [ -n "$(printf '' | grep -E -- 'foo(bar' 2>&1 >/dev/null)" ]; then
  check_contains "broken allow-email regex is flagged (grep rejects it here)" "$OUT" "invalid allow-email"
else
  pass "allow-email regex tolerated by this grep (busybox) → nothing to flag"
fi

# --- impact instrumentation: guardrail-fire event on GAP ----------------------------------------
# A GAP (a real publication blocker caught) records ONE metadata-only guard event when tracking is on (via
# $KEEL_IMPACT_LOG or the audited repo's .keel/ marker). A clean run (exit 0) and advisory WARNs, and the
# no-tracking default, record nothing.
imp_log="$SANDBOX/pa-events.log"; rm -f "$imp_log"

# (a) explicit override on a GAP
d="$(repo_by person@corp.com)"                       # non-safe identity in history → GAP exit 1
run env KEEL_IMPACT_LOG="$imp_log" bash "$pa" "$d"
check_status "GAP still exits 1 with impact log on" 1 "$STATUS"
check_file "GAP records an impact event" "$imp_log"
check_contains "event is a guard/public-audit line" "$(cat "$imp_log" 2>/dev/null)" "	guard	public-audit	blocked"

# (b) per-repo .keel/ marker, NO env — resolved from the audited dir. The gitignore line is what makes
# this a GENUINE legacy marker (dir #251 review: a bare `.keel/` alone is not proof of one).
d="$(repo_by person@corp.com)"; mkdir "$d/.keel"; printf '/.keel/impact-events.log\n' >> "$d/.gitignore"
run env -u KEEL_IMPACT_LOG bash "$pa" "$d"
check_status "GAP exits 1 with only a .keel/ marker" 1 "$STATUS"
check_file "marker alone records the GAP event (no env)" "$d/.keel/impact-events.log"

# (c) a clean run records nothing even with tracking on (only a GAP is a fire)
d="$(repo_by dev@example.com)"; mkdir "$d/.keel"
run env -u KEEL_IMPACT_LOG bash "$pa" "$d"
check_status "clean run exits 0" 0 "$STATUS"
check_nofile "a clean run records no impact event" "$d/.keel/impact-events.log"

# (d) no override AND no marker → nothing written on a GAP
d="$(repo_by person@corp.com)"                        # GAP, but no .keel/ marker
run env -u KEEL_IMPACT_LOG bash "$pa" "$d"
check_status "GAP exits 1 with tracking off" 1 "$STATUS"
check_nofile "no event written without override or marker" "$d/.keel/impact-events.log"

# --- 5b. binary blobs: the decoded scan catches what the text passes cannot see ------------------
# ASCII payload inside a UTF-16LE binary (NUL-interleaved — visible to the NUL-strip pass, no iconv
# needed, so this leg also runs on busybox). A plain-text grep sees none of it.

d="$(repo_by dev@example.com)"
{ printf '\000\000pad\000\000'; utf16le "built at /Users/tester/dev with token SeekritCorpName"; } > "$d/fix.bin"
commit_in "$d" "add binary fixture"
run bash "$pa" --token 'SeekritCorpName' "$d"
check_status "token inside a UTF-16LE binary blob → exit 1 (GAP)" 1 "$STATUS"
check_contains "binary-blob token GAP names the path" "$OUT" "in a binary blob in git history — fix.bin"
check_contains "binary-blob home-path WARN fires too" "$OUT" "absolute home path in a binary blob"

# an added-then-REMOVED binary still ships its blob — the scan walks blobs, not the final tree
git -C "$d" rm -q fix.bin; commit_in "$d" "remove the fixture"
run bash "$pa" --token 'SeekritCorpName' "$d"
check_status "removed-from-tree binary blob still detected → exit 1" 1 "$STATUS"

# non-ASCII (Cyrillic) inside UTF-16 needs the iconv pass — gate on the host having a usable iconv.
# The fixture name is built from UTF-8 escapes at runtime ("Testovoe Imya" in Cyrillic) so the test
# source stays ASCII — same discipline as the tree-scan Cyrillic test above.
cyrname="$(printf '\xd0\xa2\xd0\xb5\xd1\x81\xd1\x82\xd0\xbe\xd0\xb2\xd0\xbe\xd0\xb5\x20\xd0\x98\xd0\xbc\xd1\x8f')"
if command -v iconv >/dev/null 2>&1 && printf '%s' "$cyrname" | iconv -f UTF-8 -t UTF-16LE >/dev/null 2>&1; then
  d="$(repo_by dev@example.com)"
  printf 'author: %s' "$cyrname" | iconv -f UTF-8 -t UTF-16LE > "$d/cyr.bin"
  commit_in "$d" "add cyr fixture"
  run bash "$pa" "$d"
  check_contains "Cyrillic inside a UTF-16 binary blob → WARN" "$OUT" "Cyrillic text in a binary blob"
fi

# a text-only repo emits no binary-blob lines (text blobs are the text passes' job)
d="$(repo_by dev@example.com)"
run bash "$pa" "$d"
check_absent "text-only repo → no binary-blob output" "$OUT" "binary blob"

# compressed-data noise: ISOLATED [\xd0-\xd3][\x80-\xbf] byte pairs occur by chance in any real
# binary (a gif matches hundreds of times per MB) — the Cyrillic heuristic requires a RUN, so
# isolated pairs must not trip it (regression: keel's own demo.gif was false-positived)
d="$(repo_by dev@example.com)"
{ printf '\000\000GIF89a'; printf '\xd0\x8f'; printf 'xx\x01\x02'; printf '\xd1\x82'; printf 'yy\x03\x04'; printf '\xd2\x91'; } > "$d/noise.bin"
commit_in "$d" "add noisy binary"
run bash "$pa" "$d"
check_absent "isolated Cyrillic byte pairs in a binary → no false positive" "$OUT" "Cyrillic text in a binary blob"

# a BINARY leak reachable ONLY from a refs/pull/* ref must be caught by the decoded pass too
# (regression: `--not --all` excluded the fetched temp refs themselves — the scan was a no-op)
bare="$(mktemp -d "$SANDBOX/bare.XXXXXX")"; git init -q --bare "$bare"
d="$(repo_by dev@example.com)"
git -C "$d" remote add origin "$bare"
git -C "$d" push -q origin HEAD:main
{ printf '\000\000'; utf16le "token SeekritCorpName pr only"; } > "$d/pr.bin"
commit_in "$d" "pr binary"
git -C "$d" push -q origin HEAD:refs/pull/9/head      # binary leak lives only in the PR ref...
git -C "$d" reset -q --hard HEAD~1                     # ...not in main / any local ref
run bash "$pa" --token 'SeekritCorpName' "$d"
check_status "binary token only in a PR ref → GAP exit 1" 1 "$STATUS"
check_contains "names the PR-ref binary blob" "$OUT" "binary blob in a host PR ref"

# an oversized blob is skipped but SURFACED, never silently trusted
d="$(repo_by dev@example.com)"
{ printf '\000\000'; utf16le "token SeekritCorpName beyond the cap"; } > "$d/big.bin"
commit_in "$d" "add big binary"
run env KEEL_AUDIT_BLOB_MAX=10 bash "$pa" --token 'SeekritCorpName' "$d"
check_status "oversized blob skipped → its token NOT found (exit 0)" 0 "$STATUS"
check_contains "skipped blob is surfaced as UN-audited" "$OUT" "UN-audited"

# dir #196 (same overflow class dir #156 fixed in self/doctor.sh): a digit-SHAPED but overflowing cap
# (20 nines) must fall back to the default (10MB) instead of overflowing the shell's native integer
# range and crashing the later `-gt` size comparison with "integer expression expected" — reproduced
# live against the unguarded case arm before fixing it here.
run env KEEL_AUDIT_BLOB_MAX=99999999999999999999 bash "$pa" --token 'SeekritCorpName' "$d"
check_status "an overflowing cap falls back to the default, blob well under it → GAP (exit 1)" 1 "$STATUS"
check_absent "no 'integer expression expected' crash leaks through" "$OUT" "integer expression expected"
check_contains "the token is found — the default cap, not the overflow, governs" "$OUT" \
  "binary blob in git history"

# --- CLI surface: unknown option, non-directory DIR (dir #101) -----------------------------------
run bash "$pa" --bogus
check_status "unknown option → exit 2" 2 "$STATUS"
check_contains "names the bad flag" "$OUT" "unknown option '--bogus'"

run bash "$pa" "$SANDBOX/no-such-audit-dir"
check_status "DIR not a directory → exit 2" 2 "$STATUS"
check_contains "names the missing dir" "$OUT" "not a directory"

# --- --quiet: suppresses the header/note lines, never the GAP/WARN findings themselves (dir #101) --
d="$(repo_by dev@example.com)"
printf 'path = /Users/alice/keys\n' > "$d/p.txt"; commit_in "$d" path
run bash "$pa" --no-history "$d"
check_contains "without --quiet, the header line prints" "$OUT" "● public-audit"
run bash "$pa" --no-history --quiet "$d"
check_status "--quiet, WARN-only run → exit 0" 0 "$STATUS"
check_absent "--quiet drops the header line" "$OUT" "● public-audit"
check_contains "--quiet still prints the WARN itself" "$OUT" "absolute home path"

d="$(repo_by person@corp.com)"
run bash "$pa" --quiet "$d"
check_status "--quiet, GAP run → exit 1" 1 "$STATUS"
check_absent "--quiet drops the header line on the GAP path too" "$OUT" "● public-audit"
check_contains "--quiet still prints the GAP itself" "$OUT" "person@corp.com"

# --- --config FILE: reads config from an explicit path instead of DIR/.public-audit (dir #101) -----
d="$(repo_by dev@example.com)"
printf 'internal codename ACME-X\n' > "$d/notes.txt"; commit_in "$d" notes
cfg="$SANDBOX/external.public-audit"
printf 'token: ACME-X\n' > "$cfg"
run bash "$pa" --no-history "$d"
check_absent "no DIR/.public-audit → the token isn't hunted yet" "$OUT" "private token"
run bash "$pa" --no-history --config "$cfg" "$d"
check_status "--config FILE token hit → GAP exit 1" 1 "$STATUS"
check_contains "the externally-configured token is found" "$OUT" "private token /ACME-X/ in tracked tree"

# --- allow-path: a tracked path glob excluded from content scanning (dir #101) ---------------------
d="$(repo_by dev@example.com)"
mkdir -p "$d/vendor"
printf 'contact dev@corp.io\n' > "$d/vendor/third-party.txt"
commit_in "$d" "vendor file"
run bash "$pa" --no-history "$d"
check_contains "without allow-path, the vendored email still WARNs" "$OUT" "email in tracked content"
printf 'allow-path: vendor/*\n' > "$d/.public-audit"
commit_in "$d" "add allow-path config"
run bash "$pa" --no-history "$d"
check_absent "allow-path excludes the vendored file from content scanning" "$OUT" "email in tracked content"

# --- dir #145: personal literals (local secret-scan-personal), hunted as private tokens -----------
pfile="$SANDBOX/pa-personal.rx"
printf 'Jane[[:space:]]+Q[[:space:]]+Public\n' > "$pfile"

# a personal literal in plain tracked text → GAP, case-insensitively
d="$(repo_by dev@example.com)"
printf 'author: jane q public\n' > "$d/notes.txt"; commit_in "$d" notes
run env SECRET_SCAN_PERSONAL_FILE="$pfile" bash "$pa" --no-history "$d"
check_status "personal literal in tracked text → GAP" 1 "$STATUS"
check_contains "tree personal hit is labeled" "$OUT" "personal literal (secret-scan-personal) in tracked tree"

# a personal literal scrubbed from the tree but alive in history → still GAP
d="$(repo_by dev@example.com)"
printf 'jane q public\n' > "$d/secret.txt"; commit_in "$d" add
git -C "$d" rm -q secret.txt; commit_in "$d" remove
run env SECRET_SCAN_PERSONAL_FILE="$pfile" bash "$pa" "$d"
check_status "personal literal only in history → GAP" 1 "$STATUS"
check_contains "history personal hit is labeled" "$OUT" "personal literal (secret-scan-personal) in git history"

# a personal literal inside a UTF-16LE binary blob → GAP (invisible to log -p / log -G)
d="$(repo_by dev@example.com)"
{ utf16le "made by Jane Q Public"; } > "$d/fixture.bin"
commit_in "$d" fixture
run env SECRET_SCAN_PERSONAL_FILE="$pfile" bash "$pa" "$d"
check_status "personal literal in a UTF-16LE binary blob → GAP" 1 "$STATUS"
check_contains "personal binary hit is labeled" "$OUT" "personal literal (secret-scan-personal) in a binary blob"

# dir #250: the SAME decode recipe (deliberately duplicated from secret-scan.sh's emit_blob(), see
# decode_binary()'s header) has the SAME UTF-8-locale hole. Every test above runs under this suite's
# ambient C locale, so none exercised this axis. pick_utf8_locale() (tests/lib.sh) picks one the host
# actually has; skip with `pass`, not a hard failure, when it has none.
utf8_locale="$(pick_utf8_locale)" || utf8_locale=""
# reuse $cyr32 (defined above, still in scope — no function/subshell boundary between here and there)
# rather than re-deriving the same Cyrillic bytes under a second name.
if [ -n "$utf8_locale" ] && command -v iconv >/dev/null 2>&1 && printf '%s' "$cyr32" | iconv -f UTF-8 -t UTF-32LE >/dev/null 2>&1; then
  p32pa="$SANDBOX/pa-personal.utf32locale"; printf '%s\n' "$cyr32" > "$p32pa"
  d="$(repo_by dev@example.com)"
  printf 'author %s here' "$cyr32" | iconv -f UTF-8 -t UTF-32LE > "$d/name32.bin"
  commit_in "$d" bin32
  run env LC_ALL="$utf8_locale" SECRET_SCAN_PERSONAL_FILE="$p32pa" bash "$pa" "$d"
  check_status "non-ASCII personal literal in a UTF-32 blob is caught under a real UTF-8 locale ($utf8_locale)" 1 "$STATUS"
  check_contains "personal binary hit is labeled (UTF-8 locale)" "$OUT" "personal literal (secret-scan-personal) in a binary blob"
else
  pass "UTF-8-locale UTF-32 personal-literal test skipped (no UTF-8 locale on this host / no iconv UTF-32 converter)"
fi

# the personal-consumption note appears when the file exists — and the run is clean without hits
d="$(repo_by dev@example.com)"
run env SECRET_SCAN_PERSONAL_FILE="$pfile" bash "$pa" "$d"
check_status "personal file + clean repo → exit 0" 0 "$STATUS"
check_contains "notes that personal literals are hunted" "$OUT" "secret-scan-personal literals"

# a personal-file line with an invalid ERE is a GAP (not silently dropped, not a script-aborting
# failure) — that literal goes unscanned, which is a detection-accuracy failure, not a false-positive
# risk like a bad allow-email entry (which stays a WARN). Whether `foo(bar` is "broken" depends on the
# grep: GNU rejects it, busybox accepts it as a literal — gate on what THIS platform's grep actually
# does, same discipline as the allow-email broken-regex test above.
d="$(repo_by dev@example.com)"
badfile="$SANDBOX/pa-personal-bad.rx"
printf 'foo(bar\n' > "$badfile"
run env SECRET_SCAN_PERSONAL_FILE="$badfile" bash "$pa" --no-history "$d"
if [ -n "$(printf '' | grep -iE -- 'foo(bar' 2>&1 >/dev/null)" ]; then
  check_status "invalid personal regex line → GAP exit 1, not a script-aborting failure" 1 "$STATUS"
  check_contains "flags the invalid personal regex line" "$OUT" "invalid regex line"
else
  pass "personal-literal regex tolerated by this grep (busybox) → nothing to flag"
fi

# no personal file at all (the sandbox default, /dev/null) → no personal-literal hunting, no note
d="$(repo_by dev@example.com)"
run bash "$pa" --no-history "$d"
check_absent "no personal file → no personal-literal note" "$OUT" "secret-scan-personal literals"

# a personal literal reachable ONLY from a refs/pull/* text ref → GAP (same false-clean class as
# declared tokens: git log --all doesn't see it)
bare="$(mktemp -d "$SANDBOX/bare.XXXXXX")"; git init -q --bare "$bare"
d="$(repo_by dev@example.com)"
git -C "$d" remote add origin "$bare"
git -C "$d" push -q origin HEAD:main
git -C "$d" -c user.email=dev@example.com -c user.name=dev commit --allow-empty -q \
  -m "$(printf 'fix\n\nauthor: jane q public')"
git -C "$d" push -q origin HEAD:refs/pull/1/head     # leak lives only in the PR ref...
git -C "$d" reset -q --hard HEAD~1                    # ...not in main / any local ref
run env SECRET_SCAN_PERSONAL_FILE="$pfile" bash "$pa" "$d"
check_status "personal literal only in a refs/pull ref → GAP exit 1" 1 "$STATUS"
check_contains "PR-ref personal hit is labeled" "$OUT" "personal literal (secret-scan-personal) in a host PR ref"
check_contains "PR-ref personal GAP names the real fix (rewriting local history won't purge it)" "$OUT" "purge via delete-and-recreate"

# a personal literal inside a binary blob reachable ONLY from a refs/pull/* ref → GAP
bare="$(mktemp -d "$SANDBOX/bare.XXXXXX")"; git init -q --bare "$bare"
d="$(repo_by dev@example.com)"
git -C "$d" remote add origin "$bare"
git -C "$d" push -q origin HEAD:main
{ utf16le "made by Jane Q Public"; } > "$d/pr-fixture.bin"
commit_in "$d" "add pr binary fixture"
git -C "$d" push -q origin HEAD:refs/pull/2/head     # binary leak lives only in the PR ref...
git -C "$d" reset -q --hard HEAD~1                    # ...not in main / any local ref
run env SECRET_SCAN_PERSONAL_FILE="$pfile" bash "$pa" "$d"
check_status "personal literal in a binary blob only in a refs/pull ref → GAP exit 1" 1 "$STATUS"
check_contains "PR-ref binary personal hit is labeled" "$OUT" "personal literal (secret-scan-personal) in a binary blob"

# --- dir #647 (A4): an inherited GIT_DIR must not redirect the audit to another repo. L carries a private
# token ONLY in history (committed, then scrubbed); A is clean and holds a refs/keel-pr-audit/head-99 ref.
# Audited with GIT_DIR=A/.git: before the fix every `git -C "$DIR"` resolved to A, so the leak read clean
# (exit 0) AND cleanup_pr_refs deleted A's refs/keel-pr-audit/* (E6). Must exit 1, and A's ref must survive.
l647="$(repo_by dev@example.com)"
printf 'internal codename ZETA-647\n' > "$l647/leak.txt"; commit_in "$l647" leak
git -C "$l647" rm -q leak.txt; commit_in "$l647" scrub
a647="$(repo_by dev@example.com)"
git -C "$a647" update-ref refs/keel-pr-audit/head-99 HEAD
a647_refs_before="$(git -C "$a647" for-each-ref)"
run env GIT_DIR="$a647/.git" bash "$pa" --token 'ZETA-647' "$l647"
check_status "dir #647 A4: a history-only leak under GIT_DIR=<clean decoy> -> GAP exit 1 (not a false clean)" 1 "$STATUS"
check_contains "dir #647 A4: names the token found in history" "$OUT" "ZETA-647"
check_eq "dir #647 A4: the decoy's refs (incl. refs/keel-pr-audit/head-99) are byte-identical" "$a647_refs_before" "$(git -C "$a647" for-each-ref)"

# --- dir #719: personal literals in the working-tree binary pass (B12), invalid-byte names (B13), a
# set-but-unusable SECRET_SCAN_PERSONAL_FILE (B14) ---------------------------------------------------
p719="$SANDBOX/pa-personal-719.rx"
printf 'SeekritPersonName\n' > "$p719"

# A18 (S7-4, --no-history): a committed UTF-16LE binary holding the literal → GAP naming the file.
d="$(repo_by dev@example.com)"
{ utf16le "made by SeekritPersonName"; } > "$d/fix.bin"
commit_in "$d" "add fix.bin"
run env SECRET_SCAN_PERSONAL_FILE="$p719" bash "$pa" --no-history "$d"
check_status "dir #719 A18: personal literal in a committed binary, --no-history → GAP exit 1" 1 "$STATUS"
check_contains "dir #719 A18: names the file in the working tree" "$OUT" \
  "personal literal (secret-scan-personal) in a binary file in the working tree — fix.bin"

# A19 (default mode): an untracked binary, and (separate repo) a staged-only one → the same GAP.
d="$(repo_by dev@example.com)"
{ utf16le "made by SeekritPersonName"; } > "$d/new.bin"      # never git add-ed
run env SECRET_SCAN_PERSONAL_FILE="$p719" bash "$pa" "$d"
check_status "dir #719 A19: personal literal in an untracked binary, default mode → GAP exit 1" 1 "$STATUS"
check_contains "dir #719 A19: names the untracked binary" "$OUT" \
  "personal literal (secret-scan-personal) in a binary file in the working tree — new.bin"
d="$(repo_by dev@example.com)"
{ utf16le "made by SeekritPersonName"; } > "$d/staged.bin"
git -C "$d" add staged.bin                                    # staged, never committed
run env SECRET_SCAN_PERSONAL_FILE="$p719" bash "$pa" "$d"
check_status "dir #719 A19: personal literal in a staged-only binary, default mode → GAP exit 1" 1 "$STATUS"
check_contains "dir #719 A19: names the staged binary" "$OUT" \
  "personal literal (secret-scan-personal) in a binary file in the working tree — staged.bin"

# A20: two binaries holding the literal → exactly ONE working-tree personal-literal GAP per pass.
d="$(repo_by dev@example.com)"
{ utf16le "made by SeekritPersonName"; } > "$d/one.bin"
{ utf16le "also SeekritPersonName"; } > "$d/two.bin"
commit_in "$d" "add two binaries"
run env SECRET_SCAN_PERSONAL_FILE="$p719" bash "$pa" --no-history "$d"
check_eq "dir #719 A20: exactly one working-tree personal-literal GAP for two binaries" "1" \
  "$(grep -c 'personal literal (secret-scan-personal) in a binary file in the working tree' <<< "$OUT")"

# A21 (no false GAP): (a) a clean binary beside a personal file; (b) /dev/null + no tokens + a binary
# holding the literal → the working-tree personal GAP must not appear.
d="$(repo_by dev@example.com)"
{ utf16le "nothing personal here"; } > "$d/clean.bin"
commit_in "$d" "add clean.bin"
run env SECRET_SCAN_PERSONAL_FILE="$p719" bash "$pa" --no-history "$d"
check_status "dir #719 A21a: personal file + clean binary → exit 0" 0 "$STATUS"
d="$(repo_by dev@example.com)"
{ utf16le "made by SeekritPersonName"; } > "$d/fix.bin"
commit_in "$d" "add fix.bin"
run env SECRET_SCAN_PERSONAL_FILE=/dev/null bash "$pa" --no-history "$d"
check_absent "dir #719 A21b: /dev/null + no tokens → no working-tree binary GAP" "$OUT" \
  "in a binary file in the working tree"

# A22 / A26 (B13, Linux): a committed name ending in an invalid UTF-8 byte (0xE9) must not hide the NEXT
# record from the NUL read (A22a), the default-mode `_wp` read (A22b) or scan_binary_blobs' line read
# (A26) under bash >= 5 + UTF-8. The filesystem may refuse such a name (APFS) → one pass line.
bad_locale="$(pick_utf8_locale)" || bad_locale="C.UTF-8"
d="$(repo_by dev@example.com)"
badname="$d/$(printf 'a-caf\351')"
if { printf 'x\000clean\000' > "$badname"; } 2>/dev/null && [ -e "$badname" ]; then
  { utf16le "SeekritTok"; } > "$d/b.bin"
  commit_in "$d" "invalid-byte name + b.bin"
  run env LC_ALL="$bad_locale" bash "$pa" --no-history --token SeekritTok "$d"
  check_status "dir #719 A22a: name ending in an invalid byte does not hide the next binary (--no-history)" 1 "$STATUS"
  check_contains "dir #719 A22a: names b.bin" "$OUT" "private token /SeekritTok/ in a binary file in the working tree — b.bin"
  run env LC_ALL="$bad_locale" bash "$pa" --token SeekritTok "$d"
  check_contains "dir #719 A26: scan_binary_blobs keeps b.bin after the invalid-byte name" "$OUT" \
    "private token /SeekritTok/ in a binary blob in git history — b.bin"
  printf '\000' >> "$badname"; printf '\000' >> "$d/b.bin"      # modified after commit, both stay binary
  run env LC_ALL="$bad_locale" bash "$pa" --token SeekritTok "$d"
  check_contains "dir #719 A22b: default-mode _wp read keeps b.bin after the invalid-byte name" "$OUT" \
    "private token /SeekritTok/ in a binary file in the working tree — b.bin"
else
  pass "dir #719 A22/A26 skipped (this filesystem refuses a name ending in an invalid byte)"
fi

# A23 retired (dir #746 S2-5): decode_binary is pinned to its twin, emit_blob, by tests/test_secret_guard.sh (T2).

# A27 (B14): SECRET_SCAN_PERSONAL_FILE set to a missing path / a directory / a symlink to a directory →
# one GAP naming the variable; a dangling symlink → only the existing could-not-be-parsed GAP; /dev/null
# and empty → no such line.
d="$(repo_by dev@example.com)"
mkdir "$SANDBOX/pa-personal-dir719"
ln -s "$SANDBOX/pa-personal-dir719" "$SANDBOX/pa-personal-dirlink719"
ln -s "$SANDBOX/pa-personal-nowhere719" "$SANDBOX/pa-personal-dangling719"
for p in "$SANDBOX/pa-personal-missing719" "$SANDBOX/pa-personal-dir719" "$SANDBOX/pa-personal-dirlink719"; do
  run env SECRET_SCAN_PERSONAL_FILE="$p" bash "$pa" --no-history "$d"
  check_status "dir #719 A27: set-but-unusable personal file ($(basename "$p")) → GAP exit 1" 1 "$STATUS"
  check_contains "dir #719 A27: names the variable ($(basename "$p"))" "$OUT" "SECRET_SCAN_PERSONAL_FILE is set to"
  check_contains "dir #719 A27: says coverage is ZERO ($(basename "$p"))" "$OUT" "personal-literal coverage is ZERO"
done
run env SECRET_SCAN_PERSONAL_FILE="$SANDBOX/pa-personal-dangling719" bash "$pa" --no-history "$d"
check_status "dir #719 A27: a dangling symlink → GAP exit 1" 1 "$STATUS"
check_contains "dir #719 A27: the dangling symlink gets the existing could-not-be-parsed GAP" "$OUT" "could not be read or parsed"
check_absent "dir #719 A27: ...and not the B14 GAP too" "$OUT" "SECRET_SCAN_PERSONAL_FILE is set to"
run env SECRET_SCAN_PERSONAL_FILE=/dev/null bash "$pa" --no-history "$d"
check_status "dir #719 A27: /dev/null switches the personal half off → exit 0" 0 "$STATUS"
check_absent "dir #719 A27: /dev/null → no B14 GAP" "$OUT" "SECRET_SCAN_PERSONAL_FILE is set to"
run env SECRET_SCAN_PERSONAL_FILE= bash "$pa" --no-history "$d"
check_status "dir #719 A27: set-but-empty reads the (absent) default → exit 0" 0 "$STATUS"
check_absent "dir #719 A27: empty → no B14 GAP" "$OUT" "SECRET_SCAN_PERSONAL_FILE is set to"


# --- dir #738 (slice 3 of spec 746): public-audit never reports clean over a read it could not complete ---
# A failed git read or grep is a GAP `could not <step> (exit N) — the audit is INCOMPLETE` (B14), a non-git
# DIR is refused (B13), and the producer rule is held by a register (B15). Fixtures build the Cyrillic bytes
# with printf octal escapes, never as literals.
real_git738="$(type -P git)"
loc738="$(pick_utf8_locale)" || loc738="C.UTF-8"
p738="$SANDBOX/pa-personal-738.rx"
printf 'SeekritPersonName\n' > "$p738"

# shim738 DIR 'sh code' — DIR/git runs the code first (it may exit), then execs the real git.
shim738() {
  mkdir -p "$1"
  printf '#!/bin/sh\n%s\nexec "%s" "$@"\n' "$2" "$real_git738" > "$1/git"
  chmod +x "$1/git"
}
# farm738 DIR [SKIP…] — a PATH made of symlinks to the tools public-audit uses, minus the named ones.
farm738() {
  local dir="$1" t p s skip
  shift
  mkdir -p "$dir"
  for t in git grep sed sort tr cat cmp wc dirname rm mkdir mktemp date iconv uname head cut awk ls env basename readlink od xargs find; do
    skip=0
    for s in "$@"; do [ "$s" = "$t" ] && skip=1; done
    [ "$skip" = 1 ] && continue
    p="$(type -P "$t")" || continue
    ln -s "$p" "$dir/$t"
  done
}

# A30 (S2-4, B13) (a): a plain directory outside every repository is refused, never "clean".
nogit738="$SANDBOX/pa-nogit-738"
mkdir -p "$nogit738"
printf 'hello johndoe\n' > "$nogit738/f.txt"
printf 'johndoe\n' > "$SANDBOX/pa-personal-johndoe-738.rx"
run env SECRET_SCAN_PERSONAL_FILE="$SANDBOX/pa-personal-johndoe-738.rx" bash "$pa" --no-history "$nogit738"
check_status "dir #738 A30a: a non-git directory → exit 2" 2 "$STATUS"
check_contains "dir #738 A30a: says it is not a git repository" "$OUT" "is not a git repository"
check_absent "dir #738 A30a: never claims a clean audit" "$OUT" "no publication blockers found"

# A30 (b): mktemp failing → exit 2, no audit with an empty audit_tmp. A shim `mktemp` (macOS's ignores a missing
# TMPDIR and falls back to its user temp dir, so the env alone cannot fail it there).
d="$(repo_by dev@example.com)"
mkdir -p "$SANDBOX/pa-shim-mktemp-fail-738"
printf '#!/bin/sh\necho "mktemp: shim failure" >&2\nexit 1\n' > "$SANDBOX/pa-shim-mktemp-fail-738/mktemp"
chmod +x "$SANDBOX/pa-shim-mktemp-fail-738/mktemp"
run env PATH="$SANDBOX/pa-shim-mktemp-fail-738:$PATH" bash "$pa" "$d"
check_status "dir #738 A30b: mktemp failing → exit 2" 2 "$STATUS"
check_contains "dir #738 A30b: says the temp dir could not be created" "$OUT" "could not create a temp dir"

# A30 (c): DIR = a linked worktree (its .git is a FILE) still runs — git rev-parse, not `[ -d .git ]`.
d="$(repo_by dev@example.com)"
git -C "$d" worktree add -q "$SANDBOX/pa-wt-738" -b pa-wt-738 2>/dev/null
run bash "$pa" "$SANDBOX/pa-wt-738"
check_status "dir #738 A30c: a linked worktree is audited (exit 0 on a clean tree)" 0 "$STATUS"

# A30 (d): a RELATIVE temp dir must not leave audit_tmp relative (git -C DIR grep -f would open the wrong file).
# GNU/busybox mktemp return one under a relative TMPDIR; macOS's ignores TMPDIR, so a shim returns one everywhere.
d="$(repo_by dev@example.com)"
printf 'by SeekritPersonName\n' > "$d/t.txt"; commit_in "$d" "add t.txt"
mkdir -p "$SANDBOX/pa-rel-738/t" "$SANDBOX/pa-shim-mktemp-rel-738"
printf '#!/bin/sh\nexec "%s" -d ./t/tmp.XXXXXX\n' "$(type -P mktemp)" > "$SANDBOX/pa-shim-mktemp-rel-738/mktemp"
chmod +x "$SANDBOX/pa-shim-mktemp-rel-738/mktemp"
run_in "$SANDBOX/pa-rel-738" env PATH="$SANDBOX/pa-shim-mktemp-rel-738:$PATH" SECRET_SCAN_PERSONAL_FILE="$p738" bash "$pa" --no-history "$d"
check_status "dir #738 A30d: a relative temp dir still finds the literal → exit 1" 1 "$STATUS"
check_contains "dir #738 A30d: the literal GAP fires" "$OUT" "personal literal (secret-scan-personal) in tracked tree"
check_absent "dir #738 A30d: and no step failed" "$OUT" "could not"

# A31 (#694, B3+B4): two lines that fuse into an invalid ERE — each is its own pattern; the bad one is a GAP.
printf 'zorb[\nplugh]\n' > "$SANDBOX/pa-personal-fuse-738.rx"
d="$(repo_by dev@example.com)"
run env SECRET_SCAN_PERSONAL_FILE="$SANDBOX/pa-personal-fuse-738.rx" bash "$pa" --no-history "$d"
check_status "dir #738 A31: an invalid personal line → exit 1" 1 "$STATUS"
check_contains "dir #738 A31: exactly the invalid line is reported" "$OUT" "GAP  1 invalid regex line(s)"

# A32 (#738, B14): a corrupt index must not read as "no publication blockers found".
d="$(repo_by dev@example.com)"
printf 'by SeekritPersonName\n' > "$d/t.txt"; commit_in "$d" "add t.txt"
printf 'garbage' > "$d/.git/index"
run env SECRET_SCAN_PERSONAL_FILE="$p738" bash "$pa" --no-history "$d"
check_status "dir #738 A32: a corrupt index → exit 1" 1 "$STATUS"
check_contains "dir #738 A32: names the failed read" "$OUT" "could not"
check_contains "dir #738 A32: says the audit is INCOMPLETE" "$OUT" "the audit is INCOMPLETE"
check_absent "dir #738 A32: never claims a clean audit" "$OUT" "no publication blockers found"

# A33 (a): a failing `git log` → a GAP naming the history read, never clean.
d="$(repo_by dev@example.com)"
shim738 "$SANDBOX/pa-shim-log-738" 'for a in "$@"; do [ "$a" = log ] && { echo "fatal: shim" >&2; exit 128; }; done'
run env PATH="$SANDBOX/pa-shim-log-738:$PATH" bash "$pa" "$d"
check_status "dir #738 A33a: a failing git log → exit 1" 1 "$STATUS"
check_contains "dir #738 A33a: names the history read" "$OUT" "could not read the history (log -p)"
check_absent "dir #738 A33a: never claims a clean audit" "$OUT" "no publication blockers found"

# A33 (b): a failing `cat-file blob` over a committed binary holding the literal → a GAP, not a silent skip.
d="$(repo_by dev@example.com)"
{ utf16le "made by SeekritPersonName"; } > "$d/b.bin"; commit_in "$d" "add b.bin"
shim738 "$SANDBOX/pa-shim-blob-738" 'cf=0; bl=0; for a in "$@"; do [ "$a" = cat-file ] && cf=1; [ "$a" = blob ] && bl=1; done; [ "$cf$bl" = 11 ] && { echo "fatal: shim" >&2; exit 128; }'
run env PATH="$SANDBOX/pa-shim-blob-738:$PATH" SECRET_SCAN_PERSONAL_FILE="$p738" bash "$pa" "$d"
check_status "dir #738 A33b: a failing cat-file blob → exit 1" 1 "$STATUS"
check_contains "dir #738 A33b: names the blob read" "$OUT" "could not read blob"

# A33 (c): an unreadable working-tree binary → a GAP (root reads it fine, so non-root only).
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  d="$(repo_by dev@example.com)"
  { utf16le "made by SeekritPersonName"; } > "$d/b.bin"; commit_in "$d" "add b.bin"
  chmod 000 "$d/b.bin"
  run env SECRET_SCAN_PERSONAL_FILE="$p738" bash "$pa" --no-history "$d"
  chmod 644 "$d/b.bin"
  check_status "dir #738 A33c: an unreadable working-tree binary → exit 1" 1 "$STATUS"
  check_contains "dir #738 A33c: names the unreadable file" "$OUT" "could not read 'b.bin' in the working tree"
else
  pass "dir #738 A33c skipped (root reads a chmod 000 file)"
fi

# A33 (d): a textconv driver must not hide a committed-then-removed literal from `git log -p` / `-G`.
d="$(repo_by dev@example.com)"
printf '*.txt diff=hide\n' > "$d/.gitattributes"
git -C "$d" config diff.hide.textconv true
printf 'by SeekritPersonName SeekritTokenX\n' > "$d/t.txt"; commit_in "$d" "add t.txt"
git -C "$d" rm -q t.txt; commit_in "$d" "remove t.txt"
run env SECRET_SCAN_PERSONAL_FILE="$p738" bash "$pa" "$d"
check_status "dir #738 A33d: a literal behind a textconv driver → exit 1" 1 "$STATUS"
check_contains "dir #738 A33d: found in the history (log -p)" "$OUT" "personal literal (secret-scan-personal) in git history"
run bash "$pa" --token SeekritTokenX "$d"
check_status "dir #738 A33d: a token behind a textconv driver → exit 1" 1 "$STATUS"
check_contains "dir #738 A33d: found by the -G read" "$OUT" "private token /SeekritTokenX/ in git history"

# A33 (e) (B5 a2): a non-ASCII token with an ERE operator, matched where a grep reads it. Cyrillic built from bytes.
ivdot738="$(printf '\320\230\320\262.\320\275')"  # Cyrillic "Iv.n": matches Cyrillic "Ivan" only through the dot
ivan738="$(printf '\320\230\320\262\320\260\320\275')"  # Cyrillic "Ivan"
d="$(repo_by dev@example.com)"
git -C "$d" tag -a v1 -m "$(printf 'x %s y' "$ivan738")"
run env LC_ALL="$loc738" bash "$pa" --token "$ivdot738" "$d"
check_status "dir #738 A33e: a non-ASCII token in an annotated-tag message → exit 1" 1 "$STATUS"
check_contains "dir #738 A33e: found in the tag message" "$OUT" "in an annotated-tag message"
# ...and in a committed binary behind a lone surrogate (needs slice 1's decode — iconv -c / the fallback).
d="$(repo_by dev@example.com)"
{ printf 'AB\000\330'; printf 'x\000 \000\030\004\062\004\060\004\075\004 \000y\000'; } > "$d/s.bin"
commit_in "$d" "add s.bin"
# A33e: the lone-surrogate half rides on slice 1's resuming decode (dir #746 S2-2, merged in the same integration).
run env LC_ALL="$loc738" bash "$pa" --token "$ivdot738" "$d"
check_status "dir #738 A33e: a non-ASCII token behind a lone surrogate in a binary → exit 1" 1 "$STATUS"
check_contains "dir #738 A33e: found in the binary blob" "$OUT" "in a binary blob in git history"
# the same token, no surrogate: the plain UTF-16 decode must still find it under the token's two passes.
d="$(repo_by dev@example.com)"
{ printf 'x\000 \000\030\004\062\004\060\004\075\004 \000y\000'; } > "$d/p.bin"
commit_in "$d" "add p.bin"
run env LC_ALL="$loc738" bash "$pa" --token "$ivdot738" "$d"
check_status "dir #738 A33e: a non-ASCII token in a plain UTF-16 binary → exit 1" 1 "$STATUS"
check_contains "dir #738 A33e: found in the binary blob (plain)" "$OUT" "in a binary blob in git history"

# A33 (f): `-diff` in .gitattributes must not hide a committed-then-removed literal (`--text`).
d="$(repo_by dev@example.com)"
printf '*.svg -diff\n' > "$d/.gitattributes"
printf '<svg>by SeekritPersonName</svg>\n' > "$d/a.svg"; commit_in "$d" "add a.svg"
git -C "$d" rm -q a.svg; commit_in "$d" "remove a.svg"
run env SECRET_SCAN_PERSONAL_FILE="$p738" bash "$pa" "$d"
check_status "dir #738 A33f: a literal in a -diff file in history → exit 1" 1 "$STATUS"
check_contains "dir #738 A33f: found in the history" "$OUT" "personal literal (secret-scan-personal) in git history"

# A33 (g): a NUL inside a text-classed file must not hide the rest of the history from the greps.
d="$(repo_by dev@example.com)"
{ rep x 9000; printf '\nb\000c\n'; } > "$d/nul.txt"; commit_in "$d" "add nul.txt"
printf 'contact bob@corp-example.org\n' > "$d/mail.txt"; commit_in "$d" "add mail.txt"
run bash "$pa" "$d"
check_contains "dir #738 A33g: the email in history is still reported" "$OUT" "email in git history content"

# A33 (h): a failing PR-ref fetch → a GAP naming the remote.
d="$(repo_by dev@example.com)"
git -C "$d" remote add origin "$SANDBOX/pa-no-such-remote-738"
shim738 "$SANDBOX/pa-shim-fetch-738" 'case " $* " in *" ls-remote "*) printf "0000000000000000000000000000000000000001\trefs/pull/1/head\n"; exit 0 ;; *" fetch "*) echo "fatal: shim" >&2; exit 128 ;; esac'
run env PATH="$SANDBOX/pa-shim-fetch-738:$PATH" bash "$pa" "$d"
check_status "dir #738 A33h: a failing PR-ref fetch → exit 1" 1 "$STATUS"
check_contains "dir #738 A33h: names the remote" "$OUT" "could not fetch the host PR refs of origin"

# A33 (i): a PATH without grep → at least one `could not` GAP, never clean.
d="$(repo_by dev@example.com)"
farm738 "$SANDBOX/pa-farm-nogrep-738" grep
run env PATH="$SANDBOX/pa-farm-nogrep-738" "$(type -P bash)" "$pa" "$d"
check_status "dir #738 A33i: no grep on PATH → exit 1" 1 "$STATUS"
check_contains "dir #738 A33i: at least one step is reported as failed" "$OUT" "could not"
check_absent "dir #738 A33i: never claims a clean audit" "$OUT" "no publication blockers found"

# A33 (j): a tracked file deleted but not committed, under --no-history → a GAP (HEAD still holds it).
d="$(repo_by dev@example.com)"
printf 'by SeekritPersonName\n' > "$d/t.txt"; commit_in "$d" "add t.txt"
rm "$d/t.txt"
run env SECRET_SCAN_PERSONAL_FILE="$p738" bash "$pa" --no-history "$d"
check_status "dir #738 A33j: a deleted-but-committed tracked file, --no-history → exit 1" 1 "$STATUS"
check_contains "dir #738 A33j: names the missing file" "$OUT" "tracked file 't.txt' is missing from the working tree"
run env SECRET_SCAN_PERSONAL_FILE="$p738" bash "$pa" "$d"
check_absent "dir #738 A33j control: default mode reads HEAD, so no such GAP" "$OUT" "is missing from the working tree"

# A35 (#740, B5 in public-audit): a literal after an invalid byte in history is still found under a UTF-8 locale.
d="$(repo_by dev@example.com)"
printf 'caf\351 by JOHNDOE\n' > "$d/e.txt"; commit_in "$d" "add e.txt"
git -C "$d" rm -q e.txt; commit_in "$d" "remove e.txt"
run env LC_ALL="$loc738" SECRET_SCAN_PERSONAL_FILE="$SANDBOX/pa-personal-johndoe-738.rx" bash "$pa" "$d"
check_status "dir #738 A35: a literal after an invalid byte in history → exit 1" 1 "$STATUS"
check_contains "dir #738 A35: found in the history" "$OUT" "personal literal (secret-scan-personal) in git history"

# A35b (B5 c, public-audit): a NON-ASCII literal in another case is found only by the caller-locale pass over the
# sanitized copy (pass C folds ASCII only) — after an invalid byte in history, and in a decoded binary.
ivan_mixed738="$(printf '\320\230\320\262\320\260\320\275')"  # Cyrillic "Ivan", mixed case
ivan_upper738="$(printf '\320\230\320\222\320\220\320\235')"  # Cyrillic "IVAN", upper case
printf '%s\n' "$ivan_mixed738" > "$SANDBOX/pa-personal-ivan-738.rx"
d="$(repo_by dev@example.com)"
printf 'caf\351 name %s\n' "$ivan_upper738" > "$d/e.txt"; commit_in "$d" "add e.txt"
git -C "$d" rm -q e.txt; commit_in "$d" "remove e.txt"
run env LC_ALL="$loc738" SECRET_SCAN_PERSONAL_FILE="$SANDBOX/pa-personal-ivan-738.rx" bash "$pa" "$d"
check_status "dir #738 A35b: a non-ASCII literal in another case after an invalid byte in history → exit 1" 1 "$STATUS"
check_contains "dir #738 A35b: found in the history" "$OUT" "personal literal (secret-scan-personal) in git history"
d="$(repo_by dev@example.com)"
{ printf 'x\000 \000\030\004\022\004\020\004\035\004 \000y\000'; } > "$d/u.bin"  # UTF-16LE: x, Cyrillic "IVAN" upper case, y
commit_in "$d" "add u.bin"
run env LC_ALL="$loc738" SECRET_SCAN_PERSONAL_FILE="$SANDBOX/pa-personal-ivan-738.rx" bash "$pa" --no-history "$d"
check_status "dir #738 A35b: a non-ASCII literal in another case in a UTF-16 binary → exit 1" 1 "$STATUS"
check_contains "dir #738 A35b: found in the binary file" "$OUT" "personal literal (secret-scan-personal) in a binary file in the working tree — u.bin"

# A35c (the analogue of secret-scan's A6(f), found by the 0.16.0 integration): an ASCII literal or token whose `.` stands
# for a NON-ASCII letter ("fran.ois" for a two-byte letter) matches only in the caller's locale — under LC_ALL=C the dot
# is one byte. Pass U must therefore run for every literal and token, not only non-ASCII ones, or the audit reads clean
# where main's single caller-locale grep found it.
cced738="$(printf '\303\247')"                                              # a two-byte Latin letter
printf 'fran.ois\n' > "$SANDBOX/pa-personal-dot-738.rx"
d="$(repo_by dev@example.com)"
printf 'name fran%sois here\n' "$cced738" > "$d/n.txt"; commit_in "$d" "add n.txt"
git -C "$d" rm -q n.txt; commit_in "$d" "remove n.txt"
run env LC_ALL="$loc738" SECRET_SCAN_PERSONAL_FILE="$SANDBOX/pa-personal-dot-738.rx" bash "$pa" "$d"
check_status "dir #738 A35c: an ASCII literal whose dot stands for a non-ASCII letter, in history → exit 1" 1 "$STATUS"
check_contains "dir #738 A35c: found in the history" "$OUT" "personal literal (secret-scan-personal) in git history"
d="$(repo_by dev@example.com)"
printf 'name fran%sois here\n' "$cced738" > "$d/n.txt"; commit_in "$d" "add n.txt"
git -C "$d" tag -a v1 -m "$(printf 'tag fran%sois' "$cced738")"
run env LC_ALL="$loc738" bash "$pa" --token 'fran.ois' "$d"
check_status "dir #738 A35c: an ASCII token whose dot stands for a non-ASCII letter, in a tag message → exit 1" 1 "$STATUS"
check_contains "dir #738 A35c: found in the annotated-tag message" "$OUT" "in an annotated-tag message"

# A38 (B14, unborn HEAD): no commits is not a failure — the untracked binary is still audited.
d="$(mktemp -d "$SANDBOX/pa.XXXXXX")"
git -C "$d" init -q
{ utf16le "made by SeekritPersonName"; } > "$d/x.bin"
run env SECRET_SCAN_PERSONAL_FILE="$p738" bash "$pa" "$d"
check_status "dir #738 A38: a repository with no commits → exit 1 (the binary's GAP)" 1 "$STATUS"
check_contains "dir #738 A38: the untracked binary is reported" "$OUT" "in a binary file in the working tree — x.bin"
check_absent "dir #738 A38: no false 'could not list the changed files'" "$OUT" "could not list the changed files"

# A39 (B14, prefix): DIR = a subdirectory. Only the diff spool is prefix-stripped.
d="$(repo_by dev@example.com)"
mkdir -p "$d/sub/sub"
{ utf16le "made by SeekritPersonName"; } > "$d/sub/sub/x.bin"
run env SECRET_SCAN_PERSONAL_FILE="$p738" bash "$pa" "$d/sub"
check_contains "dir #738 A39: an untracked sub/sub/x.bin is named relative to DIR" "$OUT" \
  "in a binary file in the working tree — sub/x.bin"
d="$(repo_by dev@example.com)"
mkdir -p "$d/sub/sub"
{ utf16le "nothing here"; } > "$d/sub/sub/y.bin"; commit_in "$d" "add y.bin"
{ utf16le "made by SeekritPersonName"; } > "$d/sub/sub/y.bin"
git -C "$d" config diff.relative true
run env SECRET_SCAN_PERSONAL_FILE="$p738" bash "$pa" "$d/sub"
check_contains "dir #738 A39: under diff.relative=true the changed file is still found (--no-relative)" "$OUT" \
  "in a binary file in the working tree — sub/y.bin"

# A36 (B15): the register. Outside decode_binary (a twin, pinned elsewhere), a fail-open shape must carry
# `# fail-open-ok: <reason>`; a read -r must carry LC_ALL=C or the tag; `local x="$(…)"` is flagged with or
# without `||` (local returns 0 and hides the status).
register738() {   # FILE → one "N: line" per violation
  awk '
    /^decode_binary\(\) \{/ { skip = 1 }
    skip { if ($0 == "}") skip = 0; next }
    /^[[:space:]]*#/ { next }
    {
      line = $0
      if (index(line, "# fail-open-ok:") > 0) next
      bad = 0
      if (index(line, "|| true") || index(line, "|| :") || index(line, "< <(") || index(line, "| head")) bad = 1
      if (index(line, "|| continue") && index(line, "git ")) bad = 1
      if (index(line, "=\"$(") && !index(line, "||")) bad = 1
      if (index(line, "local ") && index(line, "=\"$(")) bad = 1
      if (index(line, "read -r") && !index(line, "LC_ALL=C")) bad = 1
      if (bad) print NR ": " line
    }' "$1"
}
check_eq "dir #738 A36: public-audit.sh holds no untagged fail-open shape" "" "$(register738 "$pa")"
mut738="$SANDBOX/pa-mutant-738.sh"
cp "$pa" "$mut738"; printf 'echo hi || true\n' >> "$mut738"
check_ne "dir #738 A36 mutation: an untagged || true turns the register red" "" "$(register738 "$mut738")"
cp "$pa" "$mut738"; printf 'while read -r x; do :; done\n' >> "$mut738"
check_ne "dir #738 A36 mutation: a read -r without LC_ALL=C turns the register red" "" "$(register738 "$mut738")"
cp "$pa" "$mut738"; printf 'f() { local x="$(cmd)" || rc=$?; }\n' >> "$mut738"
check_ne "dir #738 A36 mutation: local x=\"\$(cmd)\" || rc=\$? turns the register red" "" "$(register738 "$mut738")"
cp "$pa" "$mut738"; printf 'echo hi || true  # fail-open-ok: control\n' >> "$mut738"
check_eq "dir #738 A36 control: a tagged line is accepted" "" "$(register738 "$mut738")"

# --- dir #746 (slice 1, S2-2): decode_binary resumes after an invalid UTF-16 unit — iconv -c, or the built-in
# decoder where the host's iconv cannot resume (musl). A9(d): a Cyrillic literal after a lone surrogate.
d="$(repo_by dev@example.com)"
printf '\320\230\320\262\320\260\320\275\n' > "$SANDBOX/pa-personal-cyr746"      # "Ivan" (Cyrillic), UTF-8
printf 'AB\000\330l\000e\000a\000d\000 \000\030\004\062\004\060\004\075\004 \000t\000r\000a\000i\000l\000' \
  > "$d/bad16le.bin"
commit_in "$d" "binary with a lone surrogate before the literal"
run env SECRET_SCAN_PERSONAL_FILE="$SANDBOX/pa-personal-cyr746" bash "$pa" --no-history "$d"
check_status "dir #746 A9(d): a Cyrillic literal after an invalid unit in a binary → GAP exit 1" 1 "$STATUS"
check_contains "dir #746 A9(d): ...naming bad16le.bin" "$OUT" "in a binary file in the working tree — bad16le.bin"

summary
