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
block_file "GitHub OAuth (gho_)"     "tok = $(key 'gho_' "$(rep A 36)")"
block_file "GitHub user (ghu_)"      "tok = $(key 'ghu_' "$(rep A 36)")"
block_file "GitHub server (ghs_)"    "tok = $(key 'ghs_' "$(rep A 36)")"
block_file "GitHub refresh (ghr_)"   "tok = $(key 'ghr_' "$(rep A 36)")"
block_file "npm token (npm_)"        "tok = $(key 'npm_' "$(rep A 36)")"
block_file "Hugging Face (hf_)"      "tok = $(key 'hf_' "$(rep A 34)")"
block_file "Google API key"          "k = $(key 'AIza' "$(rep A 35)")"
block_file "Anthropic key (sk-ant-)" "k = $(key 'sk-ant-' "$(rep A 24)")"
block_file "OpenAI project (sk-proj-)" "k = $(key 'sk-proj-' "$(rep A 24)")"
block_file "generic sk- key"         "k = $(key 'sk-' "$(rep A 32)")"
block_file "Stripe key (sk_live_)"   "k = $(key 'sk_live_' "$(rep A 24)")"
block_file "GitLab PAT (glpat-)"     "k = $(key 'glpat-' "$(rep A 20)")"
block_file "Slack token (xoxb-)"     "k = $(key 'xoxb-' "$(rep A 12)")"
block_file "PEM private key"         "$(key '-----BEGIN RSA ' 'PRIVATE KEY-----')"

# --- the BLOCK message must NOT print the allowlist bypass syntax (FRAMEWORK "Enforcement mechanics") ---
# An agent optimizing to get unblocked follows any bypass recipe printed in the error text — one did, on
# Cursor: it read the old "add it to .secret-scan-allow" line and committed the key. The message must state
# WHAT is wrong, never HOW to defeat the check.
d="$(mktemp -d "$SANDBOX/sg.XXXXXX")"
printf 'tok = %s\n' "$(key 'ghp_' "$(rep A 36)")" > "$d/f.txt"
run "$scan" "$d/f.txt"
check_status  "block-message probe → exit 1" 1 "$STATUS"
check_contains "block message states the problem (BLOCKED)" "$OUT" "BLOCKED"
check_absent  "block message omits the .secret-scan-allow recipe" "$OUT" ".secret-scan-allow"
check_absent  "block message omits the inline secret-scan:allow recipe" "$OUT" "secret-scan:allow"

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

# the commit-message pass scans ALL THREE classes, not just session metadata (backlog dir #12): a
# key or a personal literal pasted into a commit message ships as unpurgeably as a tag message's
# would, so both must block here exactly as they do in the tag pass. --------------------------------
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
mbase="$(git -C "$repo" rev-parse HEAD)"
printf 'fine\n' > "$repo/b.txt"; git -C "$repo" add b.txt
git -C "$repo" commit -qm "$(printf 'change\n\ntoken %s end' "$(key 'ghp_' "$(rep a 36)")")"
run_in "$repo" "$scan" --range "$mbase..HEAD"
check_status "key in a pushed commit message → BLOCKED" 1 "$STATUS"
check_contains "labels the offending commit message (key)" "$OUT" "message"

repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
mbase="$(git -C "$repo" rev-parse HEAD)"
printf 'fine\n' > "$repo/b.txt"; git -C "$repo" add b.txt
git -C "$repo" commit -qm "change thanks to seekritpersonname"
msgpfile="$SANDBOX/personal-msg"; printf 'SeekritPersonName\n' > "$msgpfile"
run_in "$repo" env SECRET_SCAN_PERSONAL_FILE="$msgpfile" "$scan" --range "$mbase..HEAD"
check_status "personal literal in a pushed commit message → BLOCKED" 1 "$STATUS"

# --- an annotated TAG's message is neither a blob nor a commit message — a pushed tag (pre-push
# passes "<tagsha> --not --remotes") must have its message body scanned too, or a key / personal
# literal / session trailer in the tag ships to the remote uncaught -------------------------------
tag_range() {  # desc  tag-message  expected-exit  [personal-file]
  local repo tagsha
  repo="$(new_repo)"
  printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
  git -C "$repo" tag -a v1.0 -m "$2"
  tagsha="$(git -C "$repo" rev-parse v1.0)"
  run_in "$repo" env SECRET_SCAN_PERSONAL_FILE="${4:-$SECRET_SCAN_PERSONAL_FILE}" \
    "$scan" --range "$tagsha --not --remotes"
  check_status "$1" "$3" "$STATUS"
}

tag_range "key in an annotated tag message → BLOCKED" \
  "release token $(key 'ghp_' "$(rep a 36)") end" 1
check_contains "labels the offending tag" "$OUT" "tag"
# session trailer assembled by printf — the source never holds the literal
tag_range "session trailer in an annotated tag message → BLOCKED" \
  "$(printf 'release\n\nClaude-%s: https://claude.ai/code/%s_01test' Session session)" 1
# class 2 reaches the tag pass, case-insensitively
tagpfile="$SANDBOX/personal-tag"; printf 'SeekritPersonName\n' > "$tagpfile"
tag_range "personal literal in an annotated tag message → BLOCKED" \
  "thanks to seekritpersonname" 1 "$tagpfile"
tag_range "clean annotated tag message → exit 0" \
  "ordinary release notes" 0

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

# --range: a NON-ASCII personal literal in a UTF-32 binary blob is decoded and blocked. A NON-ASCII
# literal is used on purpose — an ASCII one survives the NUL-strip pass even in UTF-32, so only a
# multi-byte code point exercises the iconv-UTF-32 pass. iconv-guarded (the capability needs it); the
# Cyrillic literal is built from bytes so this test source stays ASCII.
cyr="$(printf '\320\230\320\262\320\260\320\275\320\276\320\262')"   # "Ivanov" (Cyrillic) in UTF-8
if command -v iconv >/dev/null 2>&1 && printf '%s' "$cyr" | iconv -f UTF-8 -t UTF-32LE >/dev/null 2>&1; then
  repo="$(new_repo)"
  printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
  pbase="$(git -C "$repo" rev-parse HEAD)"
  p32="$SANDBOX/personal.utf32"; printf '%s\n' "$cyr" > "$p32"
  printf 'author %s here' "$cyr" | iconv -f UTF-8 -t UTF-32LE > "$repo/name32.bin"
  git -C "$repo" add name32.bin; git -C "$repo" commit -qm bin32
  run_in "$repo" env SECRET_SCAN_PERSONAL_FILE="$p32" "$scan" --range "$pbase..HEAD"
  check_status "--range blocks a UTF-32 binary non-ASCII personal literal" 1 "$STATUS"
else
  pass "--range UTF-32 binary test skipped (no iconv / no UTF-32 converter)"
fi

# --- dir #250: the UTF-8-locale axis the test above never exercised — every test in this suite runs
# under tests/lib.sh's ambient C locale, and the miss only fires under a REAL UTF-8 locale (see
# emit_blob()'s own comment in secret-scan.sh for the full mechanism). pick_utf8_locale() (tests/lib.sh)
# picks one the HOST actually has, C.UTF-8 preferred (musl only ships that); skip with `pass`, not a
# hard failure, when the host has none.
utf8_locale="$(pick_utf8_locale)" || utf8_locale=""
if [ -n "$utf8_locale" ] && command -v iconv >/dev/null 2>&1 && printf '%s' "$cyr" | iconv -f UTF-8 -t UTF-32LE >/dev/null 2>&1; then
  p32u="$SANDBOX/personal.utf32locale"; printf '%s\n' "$cyr" > "$p32u"
  d="$(mktemp -d "$SANDBOX/sg.XXXXXX")"
  printf 'lead %s trail' "$cyr" | iconv -f UTF-8 -t UTF-32LE > "$d/f32.bin"
  run env LC_ALL="$utf8_locale" SECRET_SCAN_PERSONAL_FILE="$p32u" "$scan" -- "$d/f32.bin"
  check_status "a non-ASCII personal literal in a UTF-32 blob is caught under a real UTF-8 locale ($utf8_locale)" 1 "$STATUS"
  # the free red test (lead #4 in dir #250's body): --selftest's own UTF-32 probe must also pass
  # 9/9 under this locale — it is the check install/bootstrap scripts run after wiring the hook.
  run env LC_ALL="$utf8_locale" "$scan" --selftest
  check_status "--selftest exits 0 under a real UTF-8 locale ($utf8_locale)" 0 "$STATUS"
  check_absent "no selftest probe FAILs under a UTF-8 locale" "$OUT" "selftest: FAIL"
else
  pass "UTF-8-locale axis test skipped (no UTF-8 locale on this host / no iconv UTF-32 converter)"
fi

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

# (b) per-repo .keel/ marker, NO env — the out-of-the-box path. The gitignore line is what makes this
# a GENUINE old-style `enable` marker (dir #251 review: a bare `.keel/` alone is not proof — D3's own
# role-3 files can legitimately be the only thing there for a project that never ran impact tracking).
mrepo="$(new_repo)"; mkdir "$mrepo/.keel"
printf '/.keel/impact-events.log\n' >> "$mrepo/.gitignore"
printf '%s\n' "aws = $(key 'AKIA' "$(rep A 16)")" > "$mrepo/leak.txt"
run_in "$mrepo" env -u KEEL_IMPACT_LOG SECRET_SCAN_PERSONAL_FILE="$SANDBOX/personal-absent" "$scan" leak.txt
check_status "block exits 1 with only a .keel/ marker" 1 "$STATUS"
check_file "marker alone records the event (no env)" "$mrepo/.keel/impact-events.log"
check_contains "marker event is a guard/secret-guard line" "$(cat "$mrepo/.keel/impact-events.log" 2>/dev/null)" "	guard	secret-guard	blocked"

# (b2) worktree fallback: the untracked marker lives only at the MAIN checkout — a block inside a
# linked worktree must still record there (before the fallback these events silently vanished)
run_in "$mrepo" git commit -qm seed --allow-empty
mwt="$SANDBOX/mrepo-wt"
git -C "$mrepo" worktree add -q -b wt-guard "$mwt" >/dev/null 2>&1
printf '%s\n' "aws = $(key 'AKIA' "$(rep A 16)")" > "$mwt/leak.txt"
wt_events_before="$(wc -l < "$mrepo/.keel/impact-events.log" | tr -d ' ')"
run_in "$mwt" env -u KEEL_IMPACT_LOG SECRET_SCAN_PERSONAL_FILE="$SANDBOX/personal-absent" "$scan" leak.txt
check_status "block in a worktree still exits 1" 1 "$STATUS"
check_contains "worktree block records to the MAIN checkout's log" "$(wc -l < "$mrepo/.keel/impact-events.log" | tr -d ' ')" "$((wt_events_before + 1))"
check_nofile "no worktree-local event log appears" "$mwt/.keel/impact-events.log"

# (c) no override AND no marker → nothing written
nrepo="$(new_repo)"                                  # a repo WITHOUT .keel/
printf '%s\n' "aws = $(key 'AKIA' "$(rep A 16)")" > "$nrepo/leak.txt"
run_in "$nrepo" env -u KEEL_IMPACT_LOG SECRET_SCAN_PERSONAL_FILE="$SANDBOX/personal-absent" "$scan" leak.txt
check_status "block still exits 1 with tracking off" 1 "$STATUS"
check_nofile "no event written without override or marker" "$nrepo/.keel/impact-events.log"

# (d) dir #251: a real EXTERNAL store entry (no in-tree marker at all) also records — the store branch
# of this file's own inline resolver, not just its legacy-marker fallback
srepo="$(new_repo)"
sstore_root="$SANDBOX/secret-guard-store"
sstore="$sstore_root/$(cd "$srepo" && pwd -P | tr '/' '-')"
mkdir -p "$sstore"
printf '%s\n' "aws = $(key 'AKIA' "$(rep A 16)")" > "$srepo/leak.txt"
run_in "$srepo" env -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$sstore_root" SECRET_SCAN_PERSONAL_FILE="$SANDBOX/personal-absent" "$scan" leak.txt
check_status "block exits 1 with only an external store entry" 1 "$STATUS"
check_file "store entry alone records the event (no marker, no override)" "$sstore/impact-events.log"
check_contains "store event is a guard/secret-guard line" "$(cat "$sstore/impact-events.log" 2>/dev/null)" "	guard	secret-guard	blocked"

# (e) dir #251 review round 3: a genuine legacy marker (the gitignore line committed) whose .keel/
# directory doesn't physically exist yet — a fresh clone that carries the committed line but never
# recreated the untracked dir — must still record the event, not crash on a failed append redirect.
gonerepo="$(new_repo)"
printf '/.keel/impact-events.log\n' >> "$gonerepo/.gitignore"
git -C "$gonerepo" add .gitignore
git -C "$gonerepo" commit -qm "gitignore only, no .keel/ dir"
printf '%s\n' "aws = $(key 'AKIA' "$(rep A 16)")" > "$gonerepo/leak.txt"
run_in "$gonerepo" env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_STORE SECRET_SCAN_PERSONAL_FILE="$SANDBOX/personal-absent" "$scan" leak.txt
check_status "block exits 1 with a gitignore-only marker (no .keel/ dir yet)" 1 "$STATUS"
check_file "the event is recorded, creating .keel/ on demand" "$gonerepo/.keel/impact-events.log"
check_absent "no leaked bash redirect error on stderr" "$OUT" "No such file or directory"

# --- dir #251 sync: this file's inline copy must stay byte-identical to tools/lib/impact-store.sh's
# impact_log_path for the one behaviour both implement — a vendored file cannot `source` the shared
# lib (it may only source files vendored beside it), so drift here would be invisible until a real
# repo's guard-hook log silently diverged from keel-impact.sh's own resolution. Extract just the two
# inline functions (sourcing secret-scan.sh whole would run its real top-level scan logic) — the same
# technique test_keel_impact.sh already uses for _ledger_col_pos/_ledger_parse.
sync_lib="$REPO_ROOT/tools/lib/impact-store.sh"
check_file "tools/lib/impact-store.sh exists (sync target)" "$sync_lib"
inline_fn="$(sed -n '/^_impact_log_path_inline() {/,/^}/p' "$scan")"
if [ -z "$inline_fn" ]; then
  fail "secret-scan.sh's _impact_log_path_inline located" "no such function found in $scan"
else
  sync_repo="$(new_repo)"
  sync_store_root="$SANDBOX/sync-store"
  for sync_case in no-store with-store legacy-marker role3-only legacy-file-present; do
    case "$sync_case" in
      with-store) mkdir -p "$sync_store_root/$(cd "$sync_repo" && pwd -P | tr '/' '-')" ;;
      legacy-marker) rm -rf "$sync_store_root"; rm -rf "$sync_repo/.keel"; mkdir -p "$sync_repo/.keel"
        printf '/.keel/impact-events.log\n' >> "$sync_repo/.gitignore" ;;
      # dir #251 review: a bare `.keel/` holding ONLY a role-3 file (never gitignored — that line is
      # the genuine-marker signal) must NOT resolve as legacy in either implementation.
      role3-only) rm -rf "$sync_repo/.keel"; mkdir -p "$sync_repo/.keel"
        printf 'H-DEP-FLOATING\n' > "$sync_repo/.keel/doctor-accept" ;;
      # dir #251 review round 3: the load-bearing branch (a physically-present legacy file wins
      # outright, even with an existing store dir — the partial-migrate fix) was never independently
      # exercised by this sync test before; a real .keel/impact-events.log file now covers it.
      legacy-file-present) mkdir -p "$sync_store_root/$(cd "$sync_repo" && pwd -P | tr '/' '-')"
        : > "$sync_repo/.keel/impact-events.log" ;;
    esac
    lib_out="$(cd "$sync_repo" && env -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$sync_store_root" \
      bash -c ". '$sync_lib'; impact_log_path .")"
    inline_out="$(cd "$sync_repo" && env -u KEEL_IMPACT_LOG KEEL_IMPACT_STORE="$sync_store_root" \
      bash -c "$inline_fn"$'\n''_impact_log_path_inline .')"
    if [ "$inline_out" = "$lib_out" ]; then
      pass "sync ($sync_case): inline copy agrees with the shared lib"
    else
      fail "sync ($sync_case): inline copy agrees with the shared lib" "inline='$inline_out' lib='$lib_out'"
    fi
  done
  # dir #251 review round 3: the $HOME/$KEEL_HOME fallback branch — where an earlier bug lived (the
  # inline copy used to compute this BEFORE checking the legacy-file branch, so a repo with a genuine
  # legacy file but no $KEEL_IMPACT_STORE/$KEEL_HOME/$HOME set would crash instead of resolving
  # cleanly) — is never reached by the fixtures above (they all set $KEEL_IMPACT_STORE). Cover it
  # directly: a legacy file present, no store override, no HOME/KEEL_HOME at all.
  rm -rf "$sync_repo/.keel"; mkdir -p "$sync_repo/.keel"
  : > "$sync_repo/.keel/impact-events.log"
  lib_out="$(cd "$sync_repo" && env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_STORE -u KEEL_HOME -u HOME \
    bash -c ". '$sync_lib'; impact_log_path ." 2>&1)"
  inline_out="$(cd "$sync_repo" && env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_STORE -u KEEL_HOME -u HOME \
    bash -c "$inline_fn"$'\n''_impact_log_path_inline .' 2>&1)"
  if [ "$inline_out" = "$lib_out" ]; then
    pass "sync (no-home, legacy file present): inline copy agrees with the shared lib"
  else
    fail "sync (no-home, legacy file present): inline copy agrees with the shared lib" "inline='$inline_out' lib='$lib_out'"
  fi
  check_contains "no-home case resolves the legacy path cleanly, no HOME-unset crash" "$lib_out" "$sync_repo/.keel/impact-events.log"
  rm -rf "$sync_store_root" "$sync_repo/.keel"
fi

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

# =================================================================================================
# --- dir #508: four independent --staged bypasses (external audit run 1, F1/F3/F4/F5) — each
# reproduced with a real key-shaped secret that the direct FILE scan catches but the pre-fix
# --staged scan waved through. -------------------------------------------------------------------

# (a) F1 — an allowlist entry added in the SAME staged change as the secret it exempts must not be
# trusted (FRAMEWORK.md L701-702's own same-change restriction).
repo="$(new_repo)"
printf 'seed\n' > "$repo/seed.txt"; git -C "$repo" add seed.txt; git -C "$repo" commit -qm base
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/key.txt"
printf '%s\n' "$(key 'ghp_' 'A')" > "$repo/.secret-scan-allow"   # NEW file, same staged change
git -C "$repo" add key.txt .secret-scan-allow
run_in "$repo" "$scan" --staged
check_status "dir #508(a): same-change allowlist entry is untrusted → BLOCKED" 1 "$STATUS"
check_contains "dir #508(a): names the ignored entry" "$OUT" "ignoring an allowlist entry new in this change"

# a PRE-EXISTING allowlist entry (committed in an earlier change) still legitimately suppresses —
# the fix must not regress the ordinary, non-same-change case.
repo="$(new_repo)"
printf '%s\n' "$(key 'ghp_' 'A')" > "$repo/.secret-scan-allow"
git -C "$repo" add .secret-scan-allow; git -C "$repo" commit -qm "add allowlist"
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/key.txt"
git -C "$repo" add key.txt
run_in "$repo" "$scan" --staged
check_status "dir #508(a): a pre-existing allowlist entry still suppresses → exit 0" 0 "$STATUS"

# a pre-existing path:<glob> allowlist entry still suppresses too (channel 3, same provenance path)
repo="$(new_repo)"
mkdir -p "$repo/fixtures"
printf 'path:fixtures/*\n' > "$repo/.secret-scan-allow"
git -C "$repo" add .secret-scan-allow; git -C "$repo" commit -qm "add path allowlist"
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/fixtures/keys.txt"
git -C "$repo" add fixtures/keys.txt
run_in "$repo" "$scan" --staged
check_status "dir #508(a): a pre-existing path allowlist entry still suppresses → exit 0" 0 "$STATUS"

# (b) F3 — a non-ASCII (Cyrillic) staged filename must not evade the text scan: git C-quotes it
# by default, and the pre-fix enumeration fed that quoted/escaped text to emit_diff as a literal
# pathspec matching nothing.
repo="$(new_repo)"
cyrname="$(printf '\320\264\320\260\320\275\320\275\321\213\320\265')"   # "данные" (data) in UTF-8
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/$cyrname.txt"
git -C "$repo" add "$cyrname.txt"
run_in "$repo" "$scan" --staged
check_status "dir #508(b): non-ASCII staged filename is scanned, not C-quoted away → BLOCKED" 1 "$STATUS"

# (c) F4 — a git-mv'd (renamed) file with a newly appended secret must not be excluded by
# --diff-filter=ACM (which drops R — Renamed).
repo="$(new_repo)"
seq 1 100 > "$repo/before.txt"
git -C "$repo" add before.txt; git -C "$repo" commit -qm base
git -C "$repo" mv before.txt after.txt
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" >> "$repo/after.txt"
git -C "$repo" add after.txt
run_in "$repo" "$scan" --staged
check_status "dir #508(c): renamed file with a newly appended secret → BLOCKED" 1 "$STATUS"
check_contains "dir #508(c): names the renamed file" "$OUT" "after.txt"

# (c2) max-review finding: a RENAMED BINARY file with a modified/appended secret must not evade the
# numstat/binary loop — without --no-renames, that loop's numstat enumeration renders a rename as
# one combined "old => new" field (no -z), which fails to resolve as a path and is silently dropped.
repo="$(new_repo)"
printf '\000A%.0s' $(seq 1 200) > "$repo/before.bin"
git -C "$repo" add before.bin; git -C "$repo" commit -qm base
git -C "$repo" mv before.bin after.bin
printf '\000%s\000' "$(key 'ghp_' "$(rep A 36)")" >> "$repo/after.bin"
git -C "$repo" add after.bin
run_in "$repo" "$scan" --staged
check_status "dir #508(c2): renamed BINARY file with an appended secret → BLOCKED" 1 "$STATUS"
check_contains "dir #508(c2): names the renamed binary file" "$OUT" "after.bin"

# (d) F5 — an added line whose content starts with "++" must not be dropped as if it were a
# "+++ b/<path>" diff header.
repo="$(new_repo)"
printf 'placeholder\n' > "$repo/data.txt"
git -C "$repo" add data.txt; git -C "$repo" commit -qm base
printf 'placeholder\n++%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/data.txt"
git -C "$repo" add data.txt
run_in "$repo" "$scan" --staged
check_status "dir #508(d): a ++-prefixed added line is scanned, not dropped as a diff header → BLOCKED" 1 "$STATUS"

# (d2) max-review finding: a crafted added line shaped EXACTLY like the header ("++ b/..." — so once
# the diff's own leading "+" marker is prepended it reads "+++ b/...") must still be caught: the
# header is recognized by POSITION (immediately after a "--- " line), never by matching this shape,
# so an attacker who knows the exact anchor can't spoof it by crafting their secret line to match.
repo="$(new_repo)"
printf 'placeholder\n' > "$repo/data3.txt"
git -C "$repo" add data3.txt; git -C "$repo" commit -qm base
printf 'placeholder\n++ b/%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/data3.txt"
git -C "$repo" add data3.txt
run_in "$repo" "$scan" --staged
check_status "dir #508(d2): a crafted ++ b/-shaped added line is scanned, not spoofed as a header → BLOCKED" 1 "$STATUS"

# (d3) max-review sweep finding: an ORDINARY same-line edit — replacing a line whose OLD content
# starts with "-- " with new content starting with "++ " — renders in the diff as "--- x" / "+++
# <secret>" back-to-back, indistinguishable BY SHAPE from the real file header. A shape-based
# positional check (matching "--- "/"+++ " text) is spoofed by this; only a check anchored on the
# first HUNK header ("@@ ... @@", which has no +/- prefix and so can never come from file content)
# is safe. No rename, no binary, no unusual config — just an ordinary one-line replace.
repo="$(new_repo)"
printf -- '-- x\nkeep\n' > "$repo/mirror.txt"
git -C "$repo" add mirror.txt; git -C "$repo" commit -qm base
printf '++ %s\nkeep\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/mirror.txt"
git -C "$repo" add mirror.txt
run_in "$repo" "$scan" --staged
check_status "dir #508(d3): a same-line '-- x' -> '++ secret' edit can't spoof the header pair → BLOCKED" 1 "$STATUS"

# (a2) max-review finding: HEAD's committed .secret-scan-allow with NO trailing newline on its last
# line must not lose that line when read — a bare `read -r` (no `|| [ -n "$hl" ]`) silently drops an
# unterminated final line, which would false-block a legitimate pre-existing entry.
repo="$(new_repo)"
printf '%s' "$(key 'ghp_' 'A')" > "$repo/.secret-scan-allow"   # no trailing newline
git -C "$repo" add .secret-scan-allow; git -C "$repo" commit -qm "add allowlist, no trailing newline"
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/key2.txt"
git -C "$repo" add key2.txt
run_in "$repo" "$scan" --staged
check_status "dir #508(a2): a pre-existing entry with no trailing newline in HEAD's copy still suppresses → exit 0" 0 "$STATUS"

# =================================================================================================
# --- dir #524: `--literal-pathspecs` (dir #508's own fix — emit_diff's `git --literal-pathspecs
# diff ... -- "$path"` call) had ZERO regression coverage of its own. A file literally named "*"
# staged alongside a genuine secret in a SIBLING file: pre-fix, emit_diff("*", ...) ran a bare
# `git diff --cached -- "*"`, and git's own pathspec engine treats an unescaped "*" as a GLOB, not
# the literal one-character filename — folding the sibling file's added lines (the real secret)
# into the "*"-named file's own record. Exit status alone can't distinguish fixed from broken here
# (the sibling's own correct emit_diff call already blocks either way) — only the RECORD'S PATH can:
# fixed, the secret is attributed to its true home; broken, it is ALSO mis-attributed to "*", a path
# that never actually contained it (a human chasing "*:<secret>" down would never find it).
repo="$(new_repo)"
starsecret="$(key 'ghp_' "$(rep A 36)")"
printf 'harmless\n' > "$repo/*"
printf '%s\n' "$starsecret" > "$repo/real.txt"
git -C "$repo" add -A
run_in "$repo" "$scan" --staged
check_status "dir #524: literal '*' pathspec, secret in a sibling file → BLOCKED" 1 "$STATUS"
check_contains "dir #524: secret attributed to its own path (real.txt)" "$OUT" "real.txt:$starsecret"
check_absent  "dir #524: NOT mis-attributed to the literal '*' path via glob expansion" "$OUT" "*:$starsecret"

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

# --- install verifies the vendored SOURCE via selftest before touching the destination (a
# wired-but-broken gate must fail the install, but never leave it half-wired — see below) ----------
repo="$(new_repo)"
run "$isg" "$repo"
check_status "vendor install with selftest verify → exit 0" 0 "$STATUS"
check_contains "install runs the vendored scanner's selftest" "$OUT" "selftest: OK"

# --- dir #250 (the "second, smaller defect", one of two this ticket fixes — see CHANGELOG.md for
# the felt incident): a failing selftest must leave the destination EITHER fully wired or completely
# untouched, never half-wired (install_into() used to run the selftest LAST, after the cp's — see
# tools/install-secret-guard.sh's own comment). Simulate ANY broken vendored scanner — the trigger
# doesn't matter, only that --selftest exits non-zero — with a trivial stub in place of the real
# secret-scan.sh, so this fixture stays decoupled from that script's internals: install_into() calls
# nothing else in secret-guard/ before it fails, so the stub needs no siblings.
isg_scratch="$(mktemp -d "$SANDBOX/isg-broken.XXXXXX")"
cp "$isg" "$isg_scratch/install-secret-guard.sh"
mkdir -p "$isg_scratch/secret-guard"
broken_scan="$isg_scratch/secret-guard/secret-scan.sh"
printf '#!/usr/bin/env bash\necho "selftest: FAIL — synthetic failure for a test fixture" >&2\nexit 1\n' > "$broken_scan"
chmod +x "$broken_scan"

# per-repo vendor into a fresh repo with the broken source → refuses, destination untouched
brepo="$(new_repo)"
run bash "$isg_scratch/install-secret-guard.sh" "$brepo"
check_ne "per-repo install with a broken selftest → refuses (non-zero exit)" 0 "$STATUS"
check_nofile "broken selftest → no secret-scan.sh copied into the repo" "$brepo/.git/hooks/secret-scan.sh"
check_nofile "broken selftest → no pre-commit copied into the repo" "$brepo/.git/hooks/pre-commit"
check_nofile "broken selftest → no pre-push copied into the repo" "$brepo/.git/hooks/pre-push"
check_nofile "broken selftest → no .secret-scan-allow seed written" "$brepo/.secret-scan-allow"
check_absent "broken selftest → no 'vendored into' confirmation printed" "$OUT" "vendored into"

# --global with the broken source → refuses, core.hooksPath left untouched
gbroken_home="$SANDBOX/gbroken-home"; mkdir -p "$gbroken_home"
fresh_home_env "$gbroken_home"; gbroken_env=("${FRESH_HOME_ENV[@]}")
run env "${gbroken_env[@]}" bash "$isg_scratch/install-secret-guard.sh" --global
check_ne "broken-selftest --global install → refuses (non-zero exit)" 0 "$STATUS"
still_unset="$(env "${gbroken_env[@]}" git config --global core.hooksPath 2>/dev/null || true)"
check_status "broken selftest → --global leaves core.hooksPath unset" "" "$still_unset"
check_nofile "broken selftest → --global's staging dir has no secret-scan.sh" "$gbroken_home/.config/git/keel-hooks/secret-scan.sh"

# --- dir #570: the SOURCE selftest above is a PROXY — it can't catch a failure specific to the
# INSTALLED copy (a noexec mount, a permission/SELinux quirk unique to $hooks_dir). Simulate exactly
# that shape: a stub secret-scan.sh whose shebang names a nonexistent interpreter. Invoked via `bash
# file` (how the pre-copy check runs it, and how install_into's post-copy check deliberately does NOT
# run it — see its own comment) the shebang line is just a comment and the stub passes; invoked by
# DIRECT exec (how git itself runs an installed hook, and how the post-copy check runs it on purpose)
# the kernel tries to exec the missing interpreter and fails — a genuine post-copy-only failure, no
# root or real noexec mount needed to reproduce it.
isg_rb="$(mktemp -d "$SANDBOX/isg-rollback.XXXXXX")"
cp "$isg" "$isg_rb/install-secret-guard.sh"
mkdir -p "$isg_rb/secret-guard"
for f in pre-commit pre-push range-lib.sh; do
  cp "$REPO_ROOT/tools/secret-guard/$f" "$isg_rb/secret-guard/$f"
  chmod +x "$isg_rb/secret-guard/$f"
done
rb_scan="$isg_rb/secret-guard/secret-scan.sh"
printf '#!/nonexistent/not-a-real-interpreter\necho "selftest: OK (stub, bash-interpreted only)"\nexit 0\n' > "$rb_scan"
chmod +x "$rb_scan"

# confidence check on the stub's own two-faced behavior first, so a fixture bug can't masquerade as
# the rollback code working
run bash "$rb_scan" --selftest
check_status "rollback fixture: bash-interpreted stub passes" 0 "$STATUS"
run "$rb_scan" --selftest
check_ne "rollback fixture: directly-exec'd stub fails" 0 "$STATUS"

# per-repo vendor, no pre-existing hooks → post-copy verify fails → full rollback, nothing left behind
rbrepo="$(new_repo)"
run bash "$isg_rb/install-secret-guard.sh" "$rbrepo"
check_status "post-copy-only failure → exit 4" 4 "$STATUS"
check_contains "rollback names the installed copy" "$OUT" "INSTALLED copy"
check_contains "rollback confirms the destination is back to how it was" "$OUT" "rolled back"
for f in secret-scan.sh pre-commit pre-push range-lib.sh; do
  check_nofile "post-copy rollback → no $f left in the repo" "$rbrepo/.git/hooks/$f"
done
check_nofile "post-copy rollback → no .secret-scan-allow seed written" "$rbrepo/.secret-scan-allow"
check_absent "post-copy rollback → no 'vendored into' confirmation printed" "$OUT" "vendored into"

# per-repo vendor with --force over a FOREIGN pre-commit → post-copy verify fails → the foreign hook
# is restored from its own backup, never left stranded as a dangling .pre-keel.bak (dir #570, lead #1)
rbforeign="$(new_repo)"
mkdir -p "$rbforeign/.git/hooks"
printf '#!/bin/sh\n# my own pre-commit, pre-dating this install\nexit 0\n' > "$rbforeign/.git/hooks/pre-commit"
chmod +x "$rbforeign/.git/hooks/pre-commit"
run bash "$isg_rb/install-secret-guard.sh" --force "$rbforeign"
check_status "post-copy-only failure with --force → exit 4" 4 "$STATUS"
check_contains "foreign pre-commit restored verbatim after rollback" \
  "$(cat "$rbforeign/.git/hooks/pre-commit")" "my own pre-commit, pre-dating this install"
check_nofile "rollback removes the backup after restoring it" "$rbforeign/.git/hooks/pre-commit.pre-keel.bak"
for f in secret-scan.sh pre-push; do
  check_nofile "post-copy rollback (--force case) → no $f left" "$rbforeign/.git/hooks/$f"
done

# --- dir #570 (simplify pass, altitude finding): rollback covers a cp failure MID-COPY too, not just
# the post-copy verify — otherwise a destination-specific failure that trips on the copy itself (disk
# full, a permission quirk on $hooks_dir) would still exit under set -e with no rollback, leaving the
# exact half-wired state this ticket exists to close. A genuinely valid source with range-lib.sh
# missing makes the LAST of the four cp's fail, after three files are already in place — the source
# selftest above it stays real (byte-identical to the shipped files) so this exercises only the cp
# failure, nothing selftest-related.
isg_cpfail="$(mktemp -d "$SANDBOX/isg-cpfail.XXXXXX")"
cp "$isg" "$isg_cpfail/install-secret-guard.sh"
mkdir -p "$isg_cpfail/secret-guard"
for f in secret-scan.sh pre-commit pre-push; do
  cp "$REPO_ROOT/tools/secret-guard/$f" "$isg_cpfail/secret-guard/$f"
  chmod +x "$isg_cpfail/secret-guard/$f"
done
# range-lib.sh deliberately absent — the 4th cp targets a source file that doesn't exist

cpfrepo="$(new_repo)"
run bash "$isg_cpfail/install-secret-guard.sh" "$cpfrepo"
check_ne "a mid-copy cp failure → refuses (non-zero exit)" 0 "$STATUS"
check_contains "names the file it failed to copy" "$OUT" "range-lib.sh"
check_contains "rolls back the files copied before the failure" "$OUT" "rolled back"
for f in secret-scan.sh pre-commit pre-push range-lib.sh; do
  check_nofile "mid-copy rollback → no $f left in the repo" "$cpfrepo/.git/hooks/$f"
done
check_nofile "mid-copy rollback → no .secret-scan-allow seed written" "$cpfrepo/.secret-scan-allow"

# --- dir #570 (code review finding): re-vendoring over an ALREADY-INSTALLED Keel hook, then failing
# later in the same run, must restore the still-working hook — not delete it and leave the repo with
# NO hook at all. A real, successful install first (genuine files, real selftest) so the repo carries
# a real Keel-marked pre-commit/pre-push; then a re-install using the post-copy-failing rollback stub
# (isg_rb, built above) overwrites them and fails, and the ORIGINAL install must come back.
uprepo="$(new_repo)"
run bash "$isg" "$uprepo"
check_status "genuine first install → exit 0" 0 "$STATUS"
orig_pre_commit="$(cat "$uprepo/.git/hooks/pre-commit")"
orig_pre_push="$(cat "$uprepo/.git/hooks/pre-push")"

run bash "$isg_rb/install-secret-guard.sh" "$uprepo"
check_status "re-vendor over an existing Keel hook, then a post-copy failure → exit 4" 4 "$STATUS"
check_file "pre-commit still exists — the pre-fix bug deleted it outright" "$uprepo/.git/hooks/pre-commit"
check_file "pre-push still exists — the pre-fix bug deleted it outright" "$uprepo/.git/hooks/pre-push"
check_status "the original pre-commit is restored, byte-for-byte" \
  "$orig_pre_commit" "$(cat "$uprepo/.git/hooks/pre-commit")"
check_status "the original pre-push is restored, byte-for-byte" \
  "$orig_pre_push" "$(cat "$uprepo/.git/hooks/pre-push")"
check_contains "the restored pre-commit still carries the Keel marker" \
  "$(cat "$uprepo/.git/hooks/pre-commit")" "Keel secret-guard"
check_nofile "no stray backup left behind after the restore" "$uprepo/.git/hooks/pre-commit.pre-keel.bak"
check_nofile "no stray backup left behind after the restore (pre-push)" "$uprepo/.git/hooks/pre-push.pre-keel.bak"
# The still-working ORIGINAL hook actually still runs end-to-end after the restore, not just present
# as bytes — a real push through it must still block a real secret.
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$uprepo/root.txt"
git -C "$uprepo" add root.txt
git -C "$uprepo" commit -qm root --no-verify
usha="$(git -C "$uprepo" rev-parse HEAD)"
OUT="$(cd "$uprepo" && printf 'refs/heads/main %s refs/heads/main %s\n' "$usha" "$(rep 0 40)" | bash .git/hooks/pre-push 2>&1)"; STATUS=$?
check_status "the RESTORED pre-push hook still blocks a real secret" 1 "$STATUS"
check_contains "restored hook reports BLOCKED, not a missing-dependency crash" "$OUT" "BLOCKED"

# --- the INSTALLED pre-push hook actually runs end-to-end, not just secret-scan.sh's own --selftest:
# install used to vendor pre-push without its range-lib.sh dependency, so every real push through a
# freshly installed hook crashed on a missing sourced file, not just ones containing a secret --------
check_file "install vendors range-lib.sh next to pre-push" "$repo/.git/hooks/range-lib.sh"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/root.txt"
git -C "$repo" add root.txt
# --no-verify: the just-installed pre-commit hook would otherwise block this fixture commit itself
# (it contains the same key-shaped secret on purpose) before pre-push ever gets exercised. Bypassing a
# single commit this way is the mechanism install-secret-guard.sh's own header documents for it.
git -C "$repo" commit -qm root --no-verify
sha="$(git -C "$repo" rev-parse HEAD)"
OUT="$(cd "$repo" && printf 'refs/heads/main %s refs/heads/main %s\n' "$sha" "$(rep 0 40)" | bash .git/hooks/pre-push 2>&1)"; STATUS=$?
check_status "the INSTALLED pre-push hook blocks a first-push secret" 1 "$STATUS"
check_contains "installed hook reports BLOCKED (not a missing-dependency crash)" "$OUT" "BLOCKED"

# --- never clobber the user's own hook (SEC1): refuse by default, --force backs up ------------------
frepo="$(new_repo)"
mkdir -p "$frepo/.git/hooks"
printf '#!/bin/sh\n# my own pre-commit\nexit 0\n' > "$frepo/.git/hooks/pre-commit"
chmod +x "$frepo/.git/hooks/pre-commit"
run "$isg" "$frepo"
check_status "refuses to clobber a foreign pre-commit → exit 3" 3 "$STATUS"
check_contains "refusal names the user's data" "$OUT" "refusing to overwrite your data"
check_contains "foreign pre-commit preserved verbatim" "$(cat "$frepo/.git/hooks/pre-commit")" "my own pre-commit"
check_nofile "guard scanner NOT installed on refusal" "$frepo/.git/hooks/secret-scan.sh"
check_nofile "no backup written without --force" "$frepo/.git/hooks/pre-commit.pre-keel.bak"

run "$isg" --force "$frepo"
check_status "--force replaces the foreign hook → exit 0" 0 "$STATUS"
check_file "--force backs up the user's hook" "$frepo/.git/hooks/pre-commit.pre-keel.bak"
check_contains "backup keeps the user's content" "$(cat "$frepo/.git/hooks/pre-commit.pre-keel.bak")" "my own pre-commit"
check_contains "Keel guard now installed (marker present)" "$(cat "$frepo/.git/hooks/pre-commit")" "Keel secret-guard"

# re-vendor over OUR own hook is silent + idempotent — the marker recognizes it as ours, no false refusal
run "$isg" "$frepo"
check_status "re-vendor over Keel's own hook → exit 0 (no false refusal)" 0 "$STATUS"

# --- dir #85 (code audit, finding 26): the --global --force branch ---------------------------------
# The refuse-by-default half of the MACHINE-GLOBAL slot and the per-repo --force half were both covered;
# replacing a FOREIGN global core.hooksPath via --force was not, even though it is the one path that
# rewrites a machine-wide git setting. fresh_home_env gives this case its own HOME *and* global git
# config (lib.sh pins the latter to the shared sandbox config, so HOME alone would not isolate it).
gh_home="$SANDBOX/gforce-home"; mkdir -p "$gh_home"
# COPY the helper's output into this block's own array, so the function below is bound to $gh_home for
# good — expanding $FRESH_HOME_ENV inside the function would re-read it at every call, and a later test
# calling fresh_home_env for a different home would silently redirect every in_gh_home below it.
fresh_home_env "$gh_home"; gh_env=("${FRESH_HOME_ENV[@]}")
# NOT named `gh` — a file-scope function by that name would shadow the GitHub CLI for every later test
# in this file, and a silently-rewritten `gh` in a repo whose whole subject is gating `gh pr create`
# is a trap worth not setting. (Both points: operator-run /code-review high passes on dir #85.)
in_gh_home() { env "${gh_env[@]}" "$@"; }
foreign_hooks="$SANDBOX/gforce-foreign-hooks"; mkdir -p "$foreign_hooks"
printf '#!/bin/sh\n# someone elses global hook\nexit 0\n' > "$foreign_hooks/pre-commit"
chmod +x "$foreign_hooks/pre-commit"
in_gh_home git config --global core.hooksPath "$foreign_hooks"

run in_gh_home "$isg" --global
check_status "--global refuses a foreign global hooksPath → exit 3" 3 "$STATUS"
check_contains "--global refusal names the existing path" "$OUT" "$foreign_hooks"
check_status "--global refusal leaves the foreign hooksPath in place" \
  "$foreign_hooks" "$(in_gh_home git config --global core.hooksPath)"
check_contains "--global refusal leaves the foreign hook untouched" \
  "$(cat "$foreign_hooks/pre-commit")" "someone elses global hook"

run in_gh_home "$isg" --global --force
check_status "--global --force replaces the foreign hooksPath → exit 0" 0 "$STATUS"
check_status "--global --force repoints core.hooksPath at Keel's dir" \
  "$gh_home/.config/git/keel-hooks" "$(in_gh_home git config --global core.hooksPath)"
check_contains "--global --force installs Keel's own hook there" \
  "$(cat "$gh_home/.config/git/keel-hooks/pre-commit")" "Keel secret-guard"
# --force repoints the SETTING; it never deletes the hooks dir the user pointed at before.
check_contains "--global --force never touches the foreign hooks dir it displaced" \
  "$(cat "$foreign_hooks/pre-commit")" "someone elses global hook"

# --- vendoring honors an ABSOLUTE local core.hooksPath (2026-07-21 audit): joining it under $repo
# put the hooks in a junk dir while the real hooks dir stayed empty — guard reported success, inactive.
ahrepo="$(new_repo)"
ahooks="$(mktemp -d "$SANDBOX/abshooks.XXXXXX")"
git -C "$ahrepo" config core.hooksPath "$ahooks"
run "$isg" "$ahrepo"
check_status "vendor into absolute hooksPath → exit 0" 0 "$STATUS"
check_file "guard scanner lands in the REAL absolute hooks dir" "$ahooks/secret-scan.sh"
check_nofile "no junk copy under \$repo/<abs-path>" "$ahrepo$ahooks/secret-scan.sh"
printf 'tok = %s\n' "$(key 'ghp_' "$(rep A 36)")" > "$ahrepo/leak.txt"
git -C "$ahrepo" add leak.txt
OUT="$(git -C "$ahrepo" -c user.email=t@example.com -c user.name=t commit -qm leak 2>&1)"; STATUS=$?
check_status "commit with a key is BLOCKED via the absolute-hooksPath guard" 1 "$STATUS"

# --- a second non-flag argument is a usage error, not a silent overwrite of the first ------------
run "$isg" "$frepo" "$ahrepo"
check_status "two repo paths → exit 2 (usage error)" 2 "$STATUS"
check_contains "extra-argument error names the surplus arg" "$OUT" "unexpected extra argument"

# --- fail-closed on caller/config errors (2026-07-21 audit): a bad range or a repo-less --staged
# must exit 2 per the header contract, never read as "clean" over unscanned content.
errepo="$(new_repo)"
git -C "$errepo" -c user.email=t@example.com -c user.name=t commit -qm root --allow-empty --no-verify
run_in "$errepo" "$scan" --range "deadbeef..cafebabe"
check_status "--range with unresolvable revs → exit 2, not clean" 2 "$STATUS"
check_contains "bad-range error names the range" "$OUT" "bad range"
norepo="$(mktemp -d "$SANDBOX/norepo.XXXXXX")"
run_in "$norepo" "$scan" --staged
check_status "--staged outside a git repo → exit 2, not clean" 2 "$STATUS"

# --- FILE mode dispatches on a bare $1 — a real filename that collides with a mode keyword must
# not silently re-dispatch (dir #495 code review high, Angle C: reproduced live against a file
# literally named "staged", which without `--` reported "clean" without ever reading its content).
# `--` is the fix: force every remaining argument to be a literal filename.
mdrepo="$(new_repo)"
printf 'ghp_%s\n' "$(rep a 36)" > "$mdrepo/staged"
git -C "$mdrepo" add -A
git -C "$mdrepo" -c user.email=t@example.com -c user.name=t commit -qm plant --no-verify
run_in "$mdrepo" "$scan" staged
check_status "FILE mode: a file named 'staged' with no -- silently mode-collides -> exit 0 (the bug)" 0 "$STATUS"
check_contains "...and reports clean without ever reading it" "$OUT" "clean"
run_in "$mdrepo" "$scan" -- staged
check_status "FILE mode: the SAME file, with --, is correctly scanned -> BLOCKED" 1 "$STATUS"
check_contains "-- correctly names the file as the hit" "$OUT" "staged"

# =================================================================================================
# --- dir #518: `--range` shares dir #508(a)'s hole — an allowlist entry added in the SAME pushed
# range as the secret it exempts was trusted with no baseline check at all (ALLOW_BASELINE_REF stayed
# "" for --range, the shared compare block's own "no baseline ref → no check" case). Fixed via
# `git rev-list --boundary $rng`, which resolves a baseline for EITHER pushed-ref shape the pre-push
# hook's range-lib.sh emits.

# (1) the "A..B" shape — the common case (an existing branch's ordinary push, resolve_range_local's
# non-zero-before arm). Boundary = A. An allowlist entry added in the SAME range as the secret →
# untrusted → BLOCKED, exactly dir #508(a)'s own same-change rule, now reaching --range too.
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
rbase="$(git -C "$repo" rev-parse HEAD)"
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/key.txt"
printf '%s\n' "$(key 'ghp_' 'A')" > "$repo/.secret-scan-allow"   # NEW file, same pushed range
git -C "$repo" add key.txt .secret-scan-allow; git -C "$repo" commit -qm "add key + same-range allowlist entry"
run_in "$repo" "$scan" --range "$rbase..HEAD"
check_status "dir #518: 'A..B' baseline — same-range allowlist entry untrusted → BLOCKED" 1 "$STATUS"
check_contains "dir #518: names the ignored entry (A..B shape)" "$OUT" "ignoring an allowlist entry new in this change"

# a range whose allowlist entry PREDATES the range (committed before A) still legitimately suppresses.
repo="$(new_repo)"
printf '%s\n' "$(key 'ghp_' 'A')" > "$repo/.secret-scan-allow"
git -C "$repo" add .secret-scan-allow; git -C "$repo" commit -qm "add allowlist"
rbase="$(git -C "$repo" rev-parse HEAD)"
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/key.txt"
git -C "$repo" add key.txt; git -C "$repo" commit -qm "add key"
run_in "$repo" "$scan" --range "$rbase..HEAD"
check_status "dir #518: 'A..B' baseline — a pre-existing allowlist entry still suppresses → exit 0" 0 "$STATUS"

# (2) the "<tip> --not --remotes" shape (resolve_range_local's zero-before arm — a brand-new local
# ref that forked from an already-known remote branch). Boundary = merge-base(tip, the remote branch)
# — resolved without this scanner ever learning the remote's name or a specific tracking-ref path.
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
printf '%s\n' "$(key 'ghp_' 'A')" > "$repo/.secret-scan-allow"
git -C "$repo" add .secret-scan-allow; git -C "$repo" commit -qm "add allowlist"
new_bare_origin "$repo" >/dev/null
git -C "$repo" push -q origin "$(branch_raw_for "$repo")"   # a real, fetched origin/<branch> tracking ref
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/key.txt"
git -C "$repo" add key.txt; git -C "$repo" commit -qm "add key"
rtip="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" "$scan" --range "$rtip --not --remotes"
check_status "dir #518: '--not --remotes' merge-base baseline — pre-existing entry suppresses → exit 0" 0 "$STATUS"

# same shape, entry added in the SAME pushed range → untrusted → BLOCKED
repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
new_bare_origin "$repo" >/dev/null
git -C "$repo" push -q origin "$(branch_raw_for "$repo")"   # a real, fetched origin/<branch> tracking ref
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/key.txt"
printf '%s\n' "$(key 'ghp_' 'A')" > "$repo/.secret-scan-allow"
git -C "$repo" add key.txt .secret-scan-allow; git -C "$repo" commit -qm "add key + same-range allowlist entry"
rtip="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" "$scan" --range "$rtip --not --remotes"
check_status "dir #518: '--not --remotes' merge-base baseline — same-range entry untrusted → BLOCKED" 1 "$STATUS"
check_contains "dir #518: names the ignored entry (--not --remotes shape)" "$OUT" "ignoring an allowlist entry new in this change"

# (3) fail-closed: NO remote-tracking ref at all (dir #518 lead 1 — the very first push of a
# brand-new branch, no upstream anywhere yet). No baseline resolves, so EVERY current entry —
# even one committed several commits back, well before the secret — is treated as new-this-push;
# over-blocking, not a silent pass, and the message names the escape hatch.
repo="$(new_repo)"
printf '%s\n' "$(key 'ghp_' 'A')" > "$repo/.secret-scan-allow"
git -C "$repo" add .secret-scan-allow; git -C "$repo" commit -qm "add allowlist"
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/key.txt"
git -C "$repo" add key.txt; git -C "$repo" commit -qm "add key"
rtip="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" "$scan" --range "$rtip --not --remotes"
check_status "dir #518: no remote-tracking ref at all → fail CLOSED, BLOCKED even for a pre-existing entry" 1 "$STATUS"
check_contains "dir #518: fail-closed message names the escape hatch" "$OUT" "commit a legitimate allowlist entry by itself"

# the same fail-closed shape with NO secret at all must still resolve (the range itself scans clean;
# fail-closed only affects the allowlist-trust decision, never fabricates a finding out of nothing)
repo="$(new_repo)"
printf 'nothing secret here\n' > "$repo/ok.txt"
git -C "$repo" add ok.txt; git -C "$repo" commit -qm "clean commit, no remote at all"
rtip="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" "$scan" --range "$rtip --not --remotes"
check_status "dir #518: no remote-tracking ref, genuinely clean range → exit 0" 0 "$STATUS"

# (4) max-review completeness finding: a genuinely clean push must not pay for the boundary walk at
# all (nor print its "no baseline" WARN) just because the repo happens to carry a .secret-scan-allow
# — the baseline resolution now runs only after `records` is known non-empty, moved out of the
# --range arm itself and into the shared allowlist-apply block, which a clean push exits before ever
# reaching.
repo="$(new_repo)"
printf '%s\n' "$(key 'ghp_' 'A')" > "$repo/.secret-scan-allow"
git -C "$repo" add .secret-scan-allow; git -C "$repo" commit -qm "add allowlist"
cbase="$(git -C "$repo" rev-parse HEAD)"
printf 'clean content\n' > "$repo/ok.txt"
git -C "$repo" add ok.txt; git -C "$repo" commit -qm "clean commit"
run_in "$repo" "$scan" --range "$cbase..HEAD"
check_status "dir #518: clean push, allowlist file present → exit 0" 0 "$STATUS"
check_contains "dir #518: clean push reports clean, not a baseline WARN" "$OUT" "clean"
check_absent  "dir #518: clean push never runs/reports the boundary resolution" "$OUT" "found no pre-push history"

# =================================================================================================
# --- dir #518 (max-review correctness finding, confirmed live — 3 independent reviewer angles):
# an ORDINARY `git merge origin/main` before push — the standard way a feature branch picks up
# upstream, and literally what THIS release's own workflow does before every PR — makes
# `git rev-list --boundary` return TWO already-known ancestors (the old pushed tip, and the shared
# root the merge brings back into view), not one. An earlier cut of this fix required EXACTLY one
# boundary commit and fail-closed otherwise, which would have false-blocked every pre-existing
# allowlist entry on this everyday workflow. Fixed by UNIONING every boundary commit's committed
# allow file rather than requiring a single one (see the --range arm's own comment).
two_boundary_repo() {  # $1 = optional content for .secret-scan-allow, planted at the ROOT commit.
                        # Sets $repo and $oldtip (the feature tip a prior push already put on the
                        # remote) DIRECTLY — never via `$(...)`, which runs the function in a
                        # subshell and silently discards any plain variable it sets (same footgun
                        # tests/lib.sh's own new_repo_with_origin() comment names). Leaves the
                        # caller on "feature", merged with "mainline".
  repo="$(new_repo)"
  [ -n "${1:-}" ] && printf '%s\n' "$1" > "$repo/.secret-scan-allow"
  printf 'root\n' > "$repo/root.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm root
  git -C "$repo" checkout -qb mainline
  printf 'unrelated mainline work\n' > "$repo/m.txt"; git -C "$repo" add m.txt; git -C "$repo" commit -qm mainline
  git -C "$repo" checkout -q -
  git -C "$repo" checkout -qb feature
  printf 'feature work\n' > "$repo/f.txt"; git -C "$repo" add f.txt; git -C "$repo" commit -qm feature
  oldtip="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" merge -q --no-edit mainline
}

# (1) the pre-existing entry (planted at the shared root, before either boundary commit) still
# suppresses across a 2-boundary range.
two_boundary_repo "$(key 'ghp_' 'A')"
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/key.txt"
git -C "$repo" add key.txt; git -C "$repo" commit -qm "add key, exempted by the pre-existing entry"
tip="$(git -C "$repo" rev-parse HEAD)"
boundary_n="$(git -C "$repo" rev-list --boundary "$oldtip..$tip" | grep -c '^-' || true)"
if [ "$boundary_n" -ge 2 ]; then
  pass "dir #518 fixture setup: merge-before-push really does yield 2+ boundary commits ($boundary_n)"
else
  fail "dir #518 fixture setup: merge-before-push really does yield 2+ boundary commits" "got $boundary_n, want >=2"
fi
run_in "$repo" "$scan" --range "$oldtip..$tip"
check_status "dir #518: merge-before-push (2+ boundary commits) — pre-existing entry still suppresses → exit 0" 0 "$STATUS"

# (2) security preserved: an entry added WITHIN the same 2-boundary range is still untrusted → BLOCKED
two_boundary_repo
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/key.txt"
printf '%s\n' "$(key 'ghp_' 'A')" > "$repo/.secret-scan-allow"
git -C "$repo" add key.txt .secret-scan-allow; git -C "$repo" commit -qm "add key + same-range allowlist entry"
tip="$(git -C "$repo" rev-parse HEAD)"
run_in "$repo" "$scan" --range "$oldtip..$tip"
check_status "dir #518: merge-before-push (2+ boundary commits) — same-range entry still untrusted → BLOCKED" 1 "$STATUS"

# (3) max-review correctness finding (in-session cross-model Gemini second opinion), fixed for the
# LOCAL pre-push hook and mutation-proved here: an entry that arrives INSIDE the pushed range via a
# merge, even one that genuinely predates the secret it exempts on the branch it came from, must still
# be trusted — not invisible to the boundary union the way a same-change entry correctly is. `main`
# (already pushed, known via a real origin/main remote-tracking ref — new_bare_origin + push, not a
# hand-forged ref) legitimately adds an allowlist entry in one commit and, in a LATER commit, the
# secret it exempts (each individually clean against main's own push-time baseline); `feature` then
# `git merge origin/main`s both commits in together and pushes. `SECRET_SCAN_LOCAL_PUSH=1` (what the
# real pre-push hook sets) is what makes the merge commit that introduced the secret — itself already
# reachable from origin/main — correctly resolve as a boundary commit carrying the earlier entry.
range_repo() {  # $1 = allow entry content (empty = none), $2 = 1 to push main to a real origin
  repo="$(new_repo)"
  git -C "$repo" checkout -qb main
  git -C "$repo" commit -q --allow-empty -m root
  git -C "$repo" checkout -qb feature
  git -C "$repo" commit -q --allow-empty -m F1
  oldtip="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" checkout -q main
  printf '%s\n' "$1" > "$repo/.secret-scan-allow"
  git -C "$repo" add .secret-scan-allow; git -C "$repo" commit -qm "main: add allowlist entry"
  printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/key.txt"
  git -C "$repo" add key.txt; git -C "$repo" commit -qm "main: add the key the entry already exempts"
  if [ "${2:-}" = 1 ]; then
    new_bare_origin "$repo" >/dev/null
    git -C "$repo" push -q origin main   # main's own commits are now known via a real origin/main ref
  fi
  git -C "$repo" checkout -q feature
  git -C "$repo" merge -q --no-edit main
  tip="$(git -C "$repo" rev-parse HEAD)"
}

range_repo "$(key 'ghp_' 'A')" 1
run_in "$repo" env SECRET_SCAN_LOCAL_PUSH=1 "$scan" --range "$oldtip..$tip"
check_status "dir #518: LOCAL_PUSH=1, main already pushed → merged-in entry trusted, exit 0 (not BLOCKED)" 0 "$STATUS"

# security sanity check: LOCAL_PUSH=1 set, but main was NEVER pushed anywhere (no remote-tracking ref
# knows about it at all) — the flag only trusts content reachable via a REAL remote-tracking ref, never
# merely "on some other local branch".
range_repo "$(key 'ghp_' 'A')"
run_in "$repo" env SECRET_SCAN_LOCAL_PUSH=1 "$scan" --range "$oldtip..$tip"
check_status "dir #518: LOCAL_PUSH=1, main NEVER pushed anywhere → still fails CLOSED, BLOCKED" 1 "$STATUS"

# CI-safety regression (the SECOND max-review round's own finding, fixed by gating on the flag): the
# IDENTICAL already-pushed-main scenario, but WITHOUT SECRET_SCAN_LOCAL_PUSH (exactly how ci-scan.sh
# invokes --range) must NOT get the fix applied — falls back to the pre-fourth-gap plain-boundary
# behavior instead (over-blocking, same as before this ticket's fourth gap was found, never the
# whole-baseline collapse a real CI checkout's own already-remote-known tip would otherwise cause).
range_repo "$(key 'ghp_' 'A')" 1
run_in "$repo" "$scan" --range "$oldtip..$tip"
check_status "dir #518: NO LOCAL_PUSH flag (ci-scan.sh's own shape) → fix not applied, BLOCKED (safe)" 1 "$STATUS"

summary
