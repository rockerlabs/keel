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

summary
