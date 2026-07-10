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

# --- a session trailer in a pushed commit MESSAGE is blocked by --range (a message is not a blob,
# so every content pass is blind to it; felt 2026-07-10: such trailers reached a public main).
# The trailer is assembled by printf so this file never holds the literal the scanners flag. --------
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
mbase="$(git -C "$repo" rev-parse HEAD)"
printf 'fine\n' > "$repo/b.txt"; git -C "$repo" add b.txt
git -C "$repo" commit -qm "$(printf 'change\n\nClaude-%s: https://claude.ai/code/%s_01test' Session session)"
run_in "$repo" "$scan" --range "$mbase..HEAD"
check_status "session trailer in a pushed commit message → BLOCKED" 1 "$STATUS"
check_contains "labels the offending commit message" "$OUT" "message"

# the sanctioned noreply co-author trailer must NOT trip the message pass
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
mbase="$(git -C "$repo" rev-parse HEAD)"
printf 'fine\n' > "$repo/b.txt"; git -C "$repo" add b.txt
git -C "$repo" commit -qm "$(printf 'change\n\nCo-Authored-By: Claude <noreply@anthropic.com>')"
run_in "$repo" "$scan" --range "$mbase..HEAD"
check_status "noreply co-author trailer in a message → exit 0" 0 "$STATUS"

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

# --- impact instrumentation: metadata-only guardrail-fire event ----------------------------------
# A block records ONE event line — never the matched secret — when tracking is on, via either the
# $KEEL_IMPACT_LOG override or a repo's .keel/ marker. With neither it writes nothing (behaviour unchanged).
imp_dir="$(mktemp -d "$SANDBOX/imp.XXXXXX")"; imp_log="$imp_dir/events.log"
printf '%s\n' "aws = $(key 'AKIA' "$(rep A 16)")" > "$imp_dir/leak.txt"

# (a) explicit override
run env KEEL_IMPACT_LOG="$imp_log" SECRET_SCAN_PERSONAL_FILE="$SANDBOX/personal-absent" "$scan" "$imp_dir/leak.txt"
check_status "block still exits 1 with impact log on" 1 "$STATUS"
check_file "block records an impact event" "$imp_log"
check_contains "event is a guard/secret-guard line" "$(cat "$imp_log")" "	guard	secret-guard	blocked"
check_absent "event log never contains the secret" "$(cat "$imp_log")" "AKIA"

# (b) per-repo .keel/ marker, NO env — the out-of-the-box path
mrepo="$(new_repo)"; mkdir "$mrepo/.keel"
printf '%s\n' "aws = $(key 'AKIA' "$(rep A 16)")" > "$mrepo/leak.txt"
run_in "$mrepo" env -u KEEL_IMPACT_LOG SECRET_SCAN_PERSONAL_FILE="$SANDBOX/personal-absent" "$scan" leak.txt
check_status "block exits 1 with only a .keel/ marker" 1 "$STATUS"
check_file "marker alone records the event (no env)" "$mrepo/.keel/impact-events.log"
check_contains "marker event is a guard/secret-guard line" "$(cat "$mrepo/.keel/impact-events.log" 2>/dev/null)" "	guard	secret-guard	blocked"

# (c) no override AND no marker → nothing written
nrepo="$(new_repo)"                                  # a repo WITHOUT .keel/
printf '%s\n' "aws = $(key 'AKIA' "$(rep A 16)")" > "$nrepo/leak.txt"
run_in "$nrepo" env -u KEEL_IMPACT_LOG SECRET_SCAN_PERSONAL_FILE="$SANDBOX/personal-absent" "$scan" leak.txt
check_status "block still exits 1 with tracking off" 1 "$STATUS"
check_nofile "no event written without override or marker" "$nrepo/.keel/impact-events.log"

# --- the explicit --staged alias behaves exactly like the default staged mode --------------------
repo="$(new_repo)"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/conf.txt"
git -C "$repo" add conf.txt
run_in "$repo" "$scan" --staged
check_status "--staged alias blocks a staged key" 1 "$STATUS"

repo="$(new_repo)"
printf 'nothing here\n' > "$repo/ok.txt"; git -C "$repo" add ok.txt
run_in "$repo" "$scan" --staged
check_status "--staged on a clean staging area → exit 0" 0 "$STATUS"

# --- --tracked detective audit: ALL tracked content, not just a diff (doctor / periodic review) --
repo="$(new_repo)"
printf 'tok = %s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/old.txt"
git -C "$repo" add old.txt; git -C "$repo" commit -qm withkey
printf 'clean\n' > "$repo/new.txt"; git -C "$repo" add new.txt; git -C "$repo" commit -qm clean
run_in "$repo" "$scan" --tracked
check_status "--tracked audit finds a long-committed key" 1 "$STATUS"
check_contains "--tracked names the file with a line number" "$OUT" "old.txt:1"

# --tracked audits tracked content ONLY: an untracked leak is out of scope, a clean tree passes
repo="$(new_repo)"
printf 'clean\n' > "$repo/ok.txt"; git -C "$repo" add ok.txt; git -C "$repo" commit -qm base
printf 'tok = %s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/untracked.txt"
run_in "$repo" "$scan" --tracked
check_status "--tracked ignores untracked files / clean tracked → exit 0" 0 "$STATUS"

# --tracked runs the binary decode pass too (a tracked UTF-16 fixture is the felt leak class)
if command -v iconv >/dev/null 2>&1; then
  repo="$(new_repo)"
  printf 'name is SeekritPersonName ok' | iconv -f UTF-8 -t UTF-16LE > "$repo/fix.bin"
  git -C "$repo" add fix.bin; git -C "$repo" commit -qm bin
  pfile="$SANDBOX/personal-tracked"; printf 'SeekritPersonName\n' > "$pfile"
  run_in "$repo" env SECRET_SCAN_PERSONAL_FILE="$pfile" "$scan" --tracked
  check_status "--tracked catches a personal literal in a tracked UTF-16 binary" 1 "$STATUS"
  check_contains "--tracked labels the binary hit" "$OUT" "(binary)"
fi

# --- --selftest verifies the scanner end-to-end and exits 0 --------------------------------------
run "$scan" --selftest
check_status "--selftest → exit 0" 0 "$STATUS"
check_contains "--selftest checks the key-shape catch" "$OUT" "caught a key-shaped string"
check_absent "--selftest reports no FAIL" "$OUT" "FAIL"
# host-dependent probes degrade to a WARN (no iconv → no UTF-16 probe; lenient busybox grep → no
# fail-closed probe) — assert their OK lines only where the host actually runs them
if command -v iconv >/dev/null 2>&1; then
  check_contains "--selftest checks the UTF-16 blob catch" "$OUT" "UTF-16LE blob"
fi
greprc=0; printf '' | grep -iE 'unbalanced(paren' >/dev/null 2>&1 || greprc=$?
if [ "$greprc" -ge 2 ]; then
  check_contains "--selftest checks the fail-closed guard" "$OUT" "fails CLOSED"
fi

# --- install verifies the INSTALLED copy via selftest (a wired-but-broken gate must fail install) -
repo="$(new_repo)"
run "$isg" "$repo"
check_status "vendor install with selftest verify → exit 0" 0 "$STATUS"
check_contains "install runs the installed copy's selftest" "$OUT" "selftest: OK"

summary
