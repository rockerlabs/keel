#!/usr/bin/env bash
# secret-guard — the only fires-by-itself mechanism. Cover block (every pattern), allow
# (clean + bare prefix), the three allowlist channels, and real git-hook integration.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

scan="$REPO_ROOT/tools/secret-guard/secret-scan.sh"

# Point the personal-literals file at a nonexistent sandbox path by default, so a real
# ~/.claude/secret-scan-personal on the dev machine can never leak into these tests even if
# HOME isolation ever regresses. Personal-class tests override this per-invocation with env.
export SECRET_SCAN_PERSONAL_FILE="$SANDBOX/personal-absent"

# --- block: every key-shaped pattern, scanned as a FILE -----------------------------------------
block_file() {  # desc content
  local d; d="$(mktemp -d "$SANDBOX/sg.XXXXXX")"
  printf '%s\n' "$2" > "$d/f.txt"
  run "$scan" "$d/f.txt"
  check_status "$1 → exit 1" 1 "$STATUS"
  check_contains "$1 → BLOCKED" "$OUT" "BLOCKED"
}

block_file "AWS access key"          "aws = $(key 'AKIA' "$(rep A 16)")"
block_file "GitHub PAT (ghp_)"       "tok = $(key 'ghp_' "$(rep A 36)")"
block_file "GitHub fine-grained PAT" "tok = $(key 'github_pat_' "$(rep A 60)")"
block_file "Google API key"          "k = $(key 'AIza' "$(rep A 35)")"
block_file "Anthropic key (sk-ant-)" "k = $(key 'sk-ant-' "$(rep A 24)")"
block_file "OpenAI project (sk-proj-)" "k = $(key 'sk-proj-' "$(rep A 24)")"
block_file "generic sk- key"         "k = $(key 'sk-' "$(rep A 32)")"
block_file "Stripe key (sk_live_)"   "k = $(key 'sk_live_' "$(rep A 24)")"
block_file "GitLab PAT (glpat-)"     "k = $(key 'glpat-' "$(rep A 20)")"
block_file "Slack token (xoxb-)"     "k = $(key 'xoxb-' "$(rep A 12)")"
block_file "PEM private key"         "$(key '-----BEGIN RSA ' 'PRIVATE KEY-----')"

# --- allow: clean content, and shapes that must NOT trip the length-anchored patterns -----------
clean_file() {  # desc content
  local d; d="$(mktemp -d "$SANDBOX/sg.XXXXXX")"
  printf '%s\n' "$2" > "$d/f.txt"
  run "$scan" "$d/f.txt"
  check_status "$1 → exit 0" 0 "$STATUS"
  check_contains "$1 → clean" "$OUT" "clean"
}
clean_file "plain text"             "just some configuration text"
clean_file "bare prefix, no body"   "value = sk-"
clean_file "prefix below length"    "id = $(key 'AKIA' 'SHORT')"

# --- allowlist channel 1: inline secret-scan:allow comment --------------------------------------
d="$(mktemp -d "$SANDBOX/sg.XXXXXX")"
printf 'tok = %s  # secret-scan:allow\n' "$(key 'ghp_' "$(rep A 36)")" > "$d/f.txt"
run "$scan" "$d/f.txt"
check_status "inline allow comment → exit 0" 0 "$STATUS"

# --- allowlist channel 2: an ERE entry in .secret-scan-allow ------------------------------------
d="$(mktemp -d "$SANDBOX/sg.XXXXXX")"
printf 'tok = %s\n' "$(key 'ghp_' "$(rep A 36)")" > "$d/f.txt"
printf '%s\n' "$(key 'ghp_' 'A')" > "$d/.secret-scan-allow"   # ERE matching the planted token
run_in "$d" "$scan" f.txt
check_status "ERE allowlist entry → exit 0" 0 "$STATUS"

# --- allowlist channel 3: a path:<glob> exclusion -----------------------------------------------
d="$(mktemp -d "$SANDBOX/sg.XXXXXX")"
mkdir -p "$d/fixtures"
printf 'tok = %s\n' "$(key 'ghp_' "$(rep A 36)")" > "$d/fixtures/keys.txt"
printf 'path:fixtures/*\n' > "$d/.secret-scan-allow"
run_in "$d" "$scan" fixtures/keys.txt
check_status "path-glob allowlist → exit 0" 0 "$STATUS"

# install-secret-guard --help prints usage and exits 0 (it must not treat the flag as a repo path)
isg="$REPO_ROOT/tools/install-secret-guard.sh"
run "$isg" --help
check_status "install-secret-guard --help → exit 0" 0 "$STATUS"
check_contains "install-secret-guard --help prints usage" "$OUT" "Usage:"

# --- integration: the real pre-commit hook blocks a staged key ----------------------------------
repo="$(new_repo)"
"$isg" "$repo" >/dev/null
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/conf.txt"
git -C "$repo" add conf.txt
run git -C "$repo" commit -m "should be blocked"
check_status "pre-commit hook blocks the commit" 1 "$STATUS"
check_contains "pre-commit hook reports BLOCKED" "$OUT" "BLOCKED"

# --- integration: --range backstop (the pre-push path) scans a commit range ---------------------
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/b.txt"
git -C "$repo" add b.txt; git -C "$repo" commit -qm withkey
run_in "$repo" "$scan" --range "$base..HEAD"
check_status "--range backstop blocks key in range" 1 "$STATUS"

# --- integration: pre-push on a NEW repo's FIRST push scans the root commit (it has no parent, so a
# naive ${base}^ range used to scan nothing and wave the secret through) ---------------------------
prepush="$REPO_ROOT/tools/secret-guard/pre-push"
repo="$(new_repo)"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/root.txt"
git -C "$repo" add root.txt; git -C "$repo" commit -qm root
sha="$(git -C "$repo" rev-parse HEAD)"
OUT="$(cd "$repo" && printf 'refs/heads/main %s refs/heads/main %s\n' "$sha" "$(rep 0 40)" | bash "$prepush" 2>&1)"; STATUS=$?
check_status "pre-push blocks a first-push (root-commit) secret" 1 "$STATUS"
check_contains "pre-push reports BLOCKED on first push" "$OUT" "BLOCKED"

# --- a secret ADDED then REMOVED within the pushed range still ships its blob, so --range must catch
# it — a net endpoint diff (git diff A..B) would see neither endpoint and pass clean -----------------
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
root="$(git -C "$repo" rev-parse HEAD)"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/leak.txt"
git -C "$repo" add leak.txt; git -C "$repo" commit -qm addkey
git -C "$repo" rm -q leak.txt; git -C "$repo" commit -qm rmkey
run_in "$repo" "$scan" --range "$root..HEAD"
check_status "add-then-remove within range → BLOCKED (transient blob still ships)" 1 "$STATUS"
check_contains "names the transient leak file" "$OUT" "leak.txt"

# a clean commit range → clean (locks the fast pre-check path of the batched object scan)
repo="$(new_repo)"
printf 'nothing secret here\n' > "$repo/ok.txt"; git -C "$repo" add ok.txt; git -C "$repo" commit -qm base
cleanbase="$(git -C "$repo" rev-parse HEAD)"
printf 'still fine\n' > "$repo/ok2.txt"; git -C "$repo" add ok2.txt; git -C "$repo" commit -qm more
run_in "$repo" "$scan" --range "$cleanbase..HEAD"
check_status "clean range → exit 0" 0 "$STATUS"

# an explicit missing file is an error (exit 2), not a false "clean" (cf. doctor/public-audit)
run "$scan" "$SANDBOX/does-not-exist-$$.txt"
check_status "missing explicit file → exit 2" 2 "$STATUS"

# --- allowlist tolerates a CRLF-saved file (a trailing CR must not become part of the ERE) --------
d="$(mktemp -d "$SANDBOX/sg.XXXXXX")"
printf 'tok = %s\n' "$(key 'ghp_' "$(rep A 36)")" > "$d/f.txt"
printf '%s\r\n' "$(key 'ghp_' 'A')" > "$d/.secret-scan-allow"   # CRLF line ending
run_in "$d" "$scan" f.txt
check_status "CRLF-saved allowlist still suppresses → exit 0" 0 "$STATUS"

# =================================================================================================
# --- personal-data class: operator literals from $SECRET_SCAN_PERSONAL_FILE ----------------------
pfile="$SANDBOX/personal.rx"
printf '# operator literals (test fixture)\nJane[[:space:]]+Q[[:space:]]+Public\nMy[ _-]?Backup[ _-]?Drive\n' > "$pfile"

# blocks a personal literal in FILE mode, case-insensitively
d="$(mktemp -d "$SANDBOX/sg.XXXXXX")"
printf 'author: jane q public\n' > "$d/f.txt"
run env SECRET_SCAN_PERSONAL_FILE="$pfile" "$scan" "$d/f.txt"
check_status "personal literal (case-insensitive) → exit 1" 1 "$STATUS"
check_contains "personal literal → BLOCKED" "$OUT" "BLOCKED"

# the same content with NO personal file → only the key class runs → clean
run env SECRET_SCAN_PERSONAL_FILE="$SANDBOX/absent.rx" "$scan" "$d/f.txt"
check_status "absent personal file → keys-only, exit 0" 0 "$STATUS"

# a malformed personal ERE must fail CLOSED (exit 2), never silently disable detection.
# Only observable where the host grep actually REJECTS the ERE — busybox grep accepts an
# unbalanced '(' and then scans with it consistently, so there is nothing to fail closed on.
bad="$SANDBOX/bad.rx"
printf 'unbalanced(\n' > "$bad"
rc=0; printf '' | grep -iE 'unbalanced(' >/dev/null 2>&1 || rc=$?
if [ "$rc" -ge 2 ]; then
  run env SECRET_SCAN_PERSONAL_FILE="$bad" "$scan" "$d/f.txt"
  check_status "malformed personal regex → exit 2 (fail closed)" 2 "$STATUS"
else
  pass "malformed personal regex → host grep accepts the ERE; fail-closed not applicable"
fi

# staged text: the pre-commit path sees a personal literal in an added line
repo="$(new_repo)"
printf 'backup goes to my backup drive\n' > "$repo/notes.txt"
git -C "$repo" add notes.txt
run_in "$repo" env SECRET_SCAN_PERSONAL_FILE="$pfile" "$scan"
check_status "staged personal literal → exit 1" 1 "$STATUS"

# staged BINARY: a personal literal hidden as UTF-16LE inside a binary file — the class a
# plain-text grep cannot see (e.g. a real name inside a binary media-database fixture)
utf16le() { local s="$1" i; for ((i=0; i<${#s}; i++)); do printf '%s\000' "${s:i:1}"; done; }
repo="$(new_repo)"
{ printf '\000\000padding\000\000'; utf16le "made by Jane Q Public"; printf '\000\000'; } > "$repo/fixture.bin"
git -C "$repo" add fixture.bin
run_in "$repo" env SECRET_SCAN_PERSONAL_FILE="$pfile" "$scan"
check_status "staged UTF-16LE binary with personal literal → exit 1" 1 "$STATUS"
check_contains "binary hit names the file" "$OUT" "fixture.bin"

# --range: a personal literal in a pushed commit range is blocked
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
pbase="$(git -C "$repo" rev-parse HEAD)"
printf 'shot on My Backup Drive\n' > "$repo/b.txt"; git -C "$repo" add b.txt; git -C "$repo" commit -qm withpii
run_in "$repo" env SECRET_SCAN_PERSONAL_FILE="$pfile" "$scan" --range "$pbase..HEAD"
check_status "--range blocks a personal literal" 1 "$STATUS"

# --range: a UTF-16 binary blob introduced by the range is decoded and blocked
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
pbase="$(git -C "$repo" rev-parse HEAD)"
utf16le "Jane Q Public archive" > "$repo/lib.bin"
git -C "$repo" add lib.bin; git -C "$repo" commit -qm binpii
run_in "$repo" env SECRET_SCAN_PERSONAL_FILE="$pfile" "$scan" --range "$pbase..HEAD"
check_status "--range blocks a UTF-16 binary personal literal" 1 "$STATUS"

# --- determinism regression: a key EARLY in a large pushed range must always block ---------------
# The old fast path used `grep -q`, whose first-match exit SIGPIPE'd the still-writing
# `git cat-file --batch`; under pipefail the whole pipeline then read as failed and the hit was
# intermittently discarded (the macOS CI flake). A small secret-bearing blob plus a large blob in
# the same range locks the fixed (`grep -c`, stream fully consumed) behavior.
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
pbase="$(git -C "$repo" rev-parse HEAD)"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/leak.txt"
git -C "$repo" add leak.txt; git -C "$repo" commit -qm addkey
awk 'BEGIN{for(i=0;i<40000;i++) print "padding line", i}' > "$repo/big.txt"
git -C "$repo" add big.txt; git -C "$repo" commit -qm bigblob
run_in "$repo" "$scan" --range "$pbase..HEAD"
check_status "key early in a large range → deterministic exit 1" 1 "$STATUS"
check_contains "large-range scan names the leak" "$OUT" "leak.txt"

summary
