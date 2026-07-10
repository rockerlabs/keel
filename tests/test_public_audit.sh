#!/usr/bin/env bash
# public-audit — GAP on declared-private tokens and non-public-safe history identities; WARN on
# heuristic hits (home paths, content emails, Cyrillic); allowlist + --no-history behaviour.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

pa="$REPO_ROOT/tools/public-audit.sh"

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

# agent/session tooling metadata in a commit message → WARN (not a GAP). Built from parts so this
# test's own source carries no whole session token (keeps the repo's audit clean).
d="$(repo_by dev@example.com)"
sess="$(printf 'Claude-%s: https://claude.ai/code/%s_01ABCxyz' 'Session' 'session')"
git -C "$d" -c user.email=dev@example.com -c user.name=dev commit --allow-empty -q \
  -m "$(printf 'work\n\n%s' "$sess")"
run bash "$pa" "$d"
check_status "session metadata in a message → exit 0 (WARN)" 0 "$STATUS"
check_contains "warns about agent/session metadata" "$OUT" "session metadata"

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

# (b) per-repo .keel/ marker, NO env — resolved from the audited dir
d="$(repo_by person@corp.com)"; mkdir "$d/.keel"
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

summary
