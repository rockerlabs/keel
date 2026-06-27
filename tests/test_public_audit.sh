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

summary
