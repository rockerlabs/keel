#!/usr/bin/env bash
# secret-guard — the only fires-by-itself mechanism. Cover block (every pattern), allow
# (clean + bare prefix), the three allowlist channels, and real git-hook integration.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

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

  # dir #637 A5: the HOME-set, KEEL_IMPACT_STORE-unset ladder (B2's rungs for `impact`). Every case above
  # sets KEEL_IMPACT_STORE, so the inline copy's own fallback was never compared with the lib's. Five
  # fixtures under a throwaway HOME — legacy only, new only, both, neither, legacy under KEEL_HOME —
  # each run through both implementations under identical env, byte-compared.
  sync_id="$(cd "$sync_repo" && pwd -P | tr '/' '-')"
  for sync_case in legacy-only new-only both neither legacy-under-keel-home; do
    sync_h="$SANDBOX/sync637-$sync_case"; sync_k=""
    rm -rf "$sync_h"; mkdir -p "$sync_h"
    case "$sync_case" in
      legacy-only) mkdir -p "$sync_h/.claude/.keel/impact/$sync_id" ;;
      new-only) mkdir -p "$sync_h/.keel/impact/$sync_id" ;;
      both) mkdir -p "$sync_h/.claude/.keel/impact/$sync_id" "$sync_h/.keel/impact/$sync_id" ;;
      neither) : ;;
      legacy-under-keel-home) sync_k="$sync_h/harness"; mkdir -p "$sync_k/.keel/impact/$sync_id" ;;
    esac
    sync_env=(env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_STORE -u KEEL_HOME HOME="$sync_h")
    [ -z "$sync_k" ] || sync_env+=(KEEL_HOME="$sync_k")
    lib_out="$(cd "$sync_repo" && "${sync_env[@]}" bash -c ". '$sync_lib'; impact_log_path .")"
    inline_out="$(cd "$sync_repo" && "${sync_env[@]}" bash -c "$inline_fn"$'\n''_impact_log_path_inline .')"
    if [ "$inline_out" = "$lib_out" ]; then
      pass "sync637 ($sync_case): inline copy agrees with the shared lib"
    else
      fail "sync637 ($sync_case): inline copy agrees with the shared lib" "inline='$inline_out' lib='$lib_out'"
    fi
    case "$sync_case" in
      legacy-only) check_eq "sync637 (legacy-only): resolves into the legacy store (transition rung)" "$sync_h/.claude/.keel/impact/$sync_id/impact-events.log" "$lib_out" ;;
      new-only|both) check_eq "sync637 ($sync_case): resolves into \$HOME/.keel/impact" "$sync_h/.keel/impact/$sync_id/impact-events.log" "$lib_out" ;;
      legacy-under-keel-home) check_eq "sync637 (legacy-under-keel-home): resolves into the KEEL_HOME legacy store" "$sync_k/.keel/impact/$sync_id/impact-events.log" "$lib_out" ;;
    esac
  done
  # ...and the no-home case names the right override (KEEL_IMPACT_STORE; KEEL_HOME no longer places state).
  inline_out="$(cd "$sync_repo" && env -u KEEL_IMPACT_LOG -u KEEL_IMPACT_STORE -u KEEL_HOME -u HOME \
    bash -c "$inline_fn"$'\n''_impact_log_path_inline .' 2>&1)"
  check_contains "sync637 (no home, no legacy file): the inline copy's message names KEEL_IMPACT_STORE" \
    "$inline_out" "secret-scan: set HOME, or export KEEL_IMPACT_STORE"
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
check_nofile "no stray backup left behind after the restore" "$uprepo/.git/hooks/pre-commit.keel-upgrade.bak"
check_nofile "no stray backup left behind after the restore (pre-push)" "$uprepo/.git/hooks/pre-push.keel-upgrade.bak"
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
if cmp -s "$REPO_ROOT/tools/secret-guard/pre-commit" "$frepo/.git/hooks/pre-commit"; then
  pass "Keel guard now installed (the shipped pre-commit, byte for byte)"
else fail "Keel guard now installed (the shipped pre-commit, byte for byte)" "installed pre-commit differs from the shipped one"; fi

# re-vendor over OUR own hook is silent + idempotent — the marker recognizes it as ours, no false refusal
run "$isg" "$frepo"
check_status "re-vendor over Keel's own hook → exit 0 (no false refusal)" 0 "$STATUS"

# RC audit regression, RED before the dir #570 backup-suffix fix: --force over a foreign hook backs
# it up to the PERMANENT .pre-keel.bak; the hook is Keel's now, so this ordinary re-install (no
# --force) takes the "already ours" branch. Before the fix that branch reused the SAME .pre-keel.bak
# path for its own run-scoped safety net, and the success path then deleted it — silently destroying
# the user's --force backup, unrecoverably, on a completely ordinary re-install.
check_file "--force backup survives an ordinary re-install (RC audit regression)" \
  "$frepo/.git/hooks/pre-commit.pre-keel.bak"
check_contains "surviving backup still holds the user's original content" \
  "$(cat "$frepo/.git/hooks/pre-commit.pre-keel.bak")" "my own pre-commit"
check_nofile "the re-install's own run-scoped safety net leaves no stray .keel-upgrade.bak" \
  "$frepo/.git/hooks/pre-commit.keel-upgrade.bak"

# --- dir #625: a second --force over a DIFFERENT foreign hook must not destroy the first backup -----
# --force over foreign hook A keeps A at the PERMANENT .pre-keel.bak. If something external later
# replaces the installed hook with a different foreign hook B, a second --force used to `cp` B over
# that backup — A gone, no warning. Now it refuses (exit 3), names the saved file, and changes nothing.
f2repo="$(new_repo)"
f2h="$f2repo/.git/hooks"
mkdir -p "$f2h"
printf '#!/bin/sh\n# foreign hook A\nexit 0\n' > "$f2h/pre-commit"
chmod +x "$f2h/pre-commit"
run "$isg" --force "$f2repo"
check_status "first --force over foreign A → exit 0" 0 "$STATUS"
check_contains "first backup holds foreign A" "$(cat "$f2h/pre-commit.pre-keel.bak")" "foreign hook A"
# something external swaps in a DIFFERENT foreign hook B (and a foreign pre-push, so the pair is mixed)
printf '#!/bin/sh\n# foreign hook B\nexit 0\n' > "$f2h/pre-commit"
printf '#!/bin/sh\n# foreign push C\nexit 0\n' > "$f2h/pre-push"
run "$isg" --force "$f2repo"
check_status "second --force over foreign B with a saved backup → exit 3 (refused)" 3 "$STATUS"
check_contains "refusal names the already-saved backup file" "$OUT" "pre-commit.pre-keel.bak"
check_contains "the first backup (foreign A) survives the second --force" \
  "$(cat "$f2h/pre-commit.pre-keel.bak")" "foreign hook A"
check_contains "foreign B is left in place, untouched" "$(cat "$f2h/pre-commit")" "foreign hook B"
check_contains "foreign pre-push is left in place, untouched" "$(cat "$f2h/pre-push")" "foreign push C"
check_nofile "refusal leaves no pre-push backup behind (nothing half-done)" "$f2h/pre-push.pre-keel.bak"
check_nofile "refusal leaves no stray .keel-upgrade.bak" "$f2h/pre-commit.keel-upgrade.bak"
# the user moves the saved backup aside → --force proceeds, and backs B up
mv "$f2h/pre-commit.pre-keel.bak" "$f2h/pre-commit.pre-keel.bak.mine"
run "$isg" --force "$f2repo"
check_status "--force after the backup is moved aside → exit 0" 0 "$STATUS"
check_contains "the new backup holds foreign B" "$(cat "$f2h/pre-commit.pre-keel.bak")" "foreign hook B"
check_contains "the moved-aside backup is untouched" "$(cat "$f2h/pre-commit.pre-keel.bak.mine")" "foreign hook A"

# A DANGLING symlink at the backup path: `-e` is false for it, yet `cp` would write through the link
# (to wherever it points). The pre-flight's `-L` arm must refuse exactly as it does for a real file.
f3repo="$(new_repo)"
f3h="$f3repo/.git/hooks"
mkdir -p "$f3h"
printf '#!/bin/sh\n# foreign hook D\nexit 0\n' > "$f3h/pre-commit"
chmod +x "$f3h/pre-commit"
f3target="$SANDBOX/f3-dangling-target"
rm -f "$f3target"
ln -s "$f3target" "$f3h/pre-commit.pre-keel.bak"
run "$isg" --force "$f3repo"
check_status "--force with a DANGLING symlink at the backup path → exit 3 (refused)" 3 "$STATUS"
check_contains "dangling-symlink refusal names the backup path" "$OUT" "pre-commit.pre-keel.bak"
check_nofile "the refusal did not write through the dangling link" "$f3target"
check_contains "foreign hook D is left in place, untouched" "$(cat "$f3h/pre-commit")" "foreign hook D"

# --- dir #659 (S3-1): ownership is an EXACT marker line, not a substring. A user's own hook that only
# MENTIONS the tool by name (the refusal text itself tells users to call secret-scan.sh from their own
# hook) used to read as Keel's: a plain install overwrote it, exit 0, and deleted the run-scoped backup.
m1repo="$(new_repo)"
m1h="$m1repo/.git/hooks"
mkdir -p "$m1h"
printf '#!/bin/sh\n# my wrapper: runs lint, then calls Keel secret-guard by hand\nexit 0\n' > "$m1h/pre-commit"
chmod +x "$m1h/pre-commit"
run "$isg" "$m1repo"
check_status "dir #659 S3-1: a foreign hook that only MENTIONS the name is refused → exit 3" 3 "$STATUS"
check_contains "dir #659 S3-1: the mentioning hook is left verbatim" "$(cat "$m1h/pre-commit")" "my wrapper: runs lint"
check_nofile "dir #659 S3-1: nothing installed on refusal" "$m1h/secret-scan.sh"
# The marker line is a compatibility contract: every installed copy since the hooks first shipped
# carries exactly this line 2, so a plain re-install keeps recognizing an OLDER Keel hook as ours.
# Rewording either line orphans every existing install (each re-install would refuse it as foreign).
check_eq "dir #659: pre-commit's line 2 is the unchanged ownership marker" \
  "# Keel secret-guard — pre-commit hook. Catches a key-shaped secret before it enters local history." \
  "$(sed -n 2p "$REPO_ROOT/tools/secret-guard/pre-commit")"
check_eq "dir #659: pre-push's line 2 is the unchanged ownership marker" \
  "# Keel secret-guard — pre-push hook. The hard outward boundary: scan the commits being pushed." \
  "$(sed -n 2p "$REPO_ROOT/tools/secret-guard/pre-push")"
# A marker line in the WRONG hook does not count: pre-push's marker inside a pre-commit is not ours.
m1brepo="$(new_repo)"
mkdir -p "$m1brepo/.git/hooks"
{ echo '#!/bin/sh'; sed -n 2p "$REPO_ROOT/tools/secret-guard/pre-push"; echo '# my own pre-commit'; } > "$m1brepo/.git/hooks/pre-commit"
run "$isg" "$m1brepo"
check_status "dir #659 S3-1: pre-push's marker inside a pre-commit is not ownership → exit 3" 3 "$STATUS"

# --- dir #659 (S3-2): a symlinked hook path is refused, its target named — never written through. `cp`
# onto a symlink follows it: --force used to rewrite a dotfiles target, and a plain install over a link to
# a shared Keel-marked hook rewrote that shared file (its edits unrecoverable).
s2repo="$(new_repo)"
s2h="$s2repo/.git/hooks"
mkdir -p "$s2h"
s2shared="$SANDBOX/s2-shared-pre-commit"
{ cat "$REPO_ROOT/tools/secret-guard/pre-commit"; echo '# EDITED-SHARED-MARKER'; } > "$s2shared"
ln -s "$s2shared" "$s2h/pre-commit"
run "$isg" "$s2repo"
check_status "dir #659 S3-2: a symlinked (Keel-marked) hook is refused → exit 3" 3 "$STATUS"
check_contains "dir #659 S3-2: the refusal names the link's target" "$OUT" "$s2shared"
check_contains "dir #659 S3-2: the shared target keeps its edit" "$(cat "$s2shared")" "EDITED-SHARED-MARKER"
check_link "dir #659 S3-2: the link itself is left in place" "$s2h/pre-commit"
check_nofile "dir #659 S3-2: nothing installed on refusal" "$s2h/secret-scan.sh"
s2frepo="$(new_repo)"
s2fh="$s2frepo/.git/hooks"
mkdir -p "$s2fh"
s2dot="$SANDBOX/s2-dotfiles-pre-push"
printf '#!/bin/sh\n# my dotfiles hook\nexit 0\n' > "$s2dot"
ln -s "$s2dot" "$s2fh/pre-push"
run "$isg" --force "$s2frepo"
check_status "dir #659 S3-2: --force does not write through a symlinked foreign hook → exit 3" 3 "$STATUS"
check_contains "dir #659 S3-2: the dotfiles target is untouched under --force" "$(cat "$s2dot")" "my dotfiles hook"
check_nofile "dir #659 S3-2: --force refusal leaves no backup behind" "$s2fh/pre-push.pre-keel.bak"
check_nofile "dir #659 S3-2: --force refusal installs no pre-commit either (nothing half-done)" "$s2fh/pre-commit"
# The always-Keel files are copied with the same `cp`, so a link at their path is refused too.
s2srepo="$(new_repo)"
mkdir -p "$s2srepo/.git/hooks"
s2scan="$SANDBOX/s2-shared-scanner"
printf '# a scanner shared from elsewhere\n' > "$s2scan"
ln -s "$s2scan" "$s2srepo/.git/hooks/secret-scan.sh"
run "$isg" "$s2srepo"
check_status "dir #659 S3-2: a symlinked secret-scan.sh is refused → exit 3" 3 "$STATUS"
check_contains "dir #659 S3-2: the shared scanner target is untouched" "$(cat "$s2scan")" "a scanner shared from elsewhere"
# A re-install's run-scoped .keel-upgrade.bak is a `cp` destination too. That name is Keel's own scratch
# path, so a link left there is removed (never followed) rather than refused — a refusal would ask the
# user to put a file at a path the next run overwrites and deletes. Its target is never written.
s2urepo="$(new_repo)"
s2uh="$s2urepo/.git/hooks"
mkdir -p "$s2uh"
cp "$REPO_ROOT/tools/secret-guard/pre-commit" "$s2uh/pre-commit"
s2utarget="$SANDBOX/s2-upgrade-bak-target"
printf '# someone elses file\n' > "$s2utarget"
ln -s "$s2utarget" "$s2uh/pre-commit.keel-upgrade.bak"
run "$isg" "$s2urepo"
check_status "dir #659 S3-2: a link at Keel's own .keel-upgrade.bak path does not block a re-install → exit 0" 0 "$STATUS"
check_contains "dir #659 S3-2: the .keel-upgrade.bak link's target is never written" "$(cat "$s2utarget")" "someone elses file"
check_nolink "dir #659 S3-2: the run-scoped .keel-upgrade.bak link is gone after the run" "$s2uh/pre-commit.keel-upgrade.bak"
# A foreign pre-push after an already-Keel pre-commit: the refusal now happens before ANY write, so
# "Nothing was changed" is true — no stray pre-commit.keel-upgrade.bak is left behind (it used to be).
s2rrepo="$(new_repo)"
s2rh="$s2rrepo/.git/hooks"
mkdir -p "$s2rh"
cp "$REPO_ROOT/tools/secret-guard/pre-commit" "$s2rh/pre-commit"
printf '#!/bin/sh\n# my own pre-push\nexit 0\n' > "$s2rh/pre-push"
run "$isg" "$s2rrepo"
check_status "dir #659: Keel pre-commit + foreign pre-push → refused, exit 3" 3 "$STATUS"
check_nofile "dir #659: that refusal leaves no stray pre-commit.keel-upgrade.bak" "$s2rh/pre-commit.keel-upgrade.bak"
check_absent "dir #659: that refusal comes before the source selftest" "$OUT" "selftest"
# The allowlist seed is a write too: a dangling link at .secret-scan-allow is not followed.
s2arepo="$(new_repo)"
s2atarget="$SANDBOX/s2-allow-target"
rm -f "$s2atarget"
ln -s "$s2atarget" "$s2arepo/.secret-scan-allow"
run "$isg" "$s2arepo"
check_status "dir #659: a vendor install with a dangling .secret-scan-allow link → exit 0" 0 "$STATUS"
check_nofile "dir #659: the seed did not write through the dangling .secret-scan-allow link" "$s2atarget"

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
if cmp -s "$REPO_ROOT/tools/secret-guard/pre-commit" "$gh_home/.config/git/keel-hooks/pre-commit"; then
  pass "--global --force installs Keel's own hook there (the shipped pre-commit, byte for byte)"
else fail "--global --force installs Keel's own hook there (the shipped pre-commit, byte for byte)" "installed pre-commit differs"; fi
# --force repoints the SETTING; it never deletes the hooks dir the user pointed at before.
check_contains "--global --force never touches the foreign hooks dir it displaced" \
  "$(cat "$foreign_hooks/pre-commit")" "someone elses global hook"

# --- dir #659 (S3-3): --global --force RECORDS the hooksPath it displaces, and --global --uninstall
# restores it. Before, the old value was printed nowhere and written nowhere — the pointer was lost.
check_contains "dir #659 S3-3: --global --force names the displaced hooksPath" "$OUT" "$foreign_hooks"
check_eq "dir #659 S3-3: the displaced hooksPath is recorded in global git config" \
  "$foreign_hooks" "$(in_gh_home git config --global keel.displacedHooksPath)"
# An ordinary re-install over Keel's own wiring keeps the record (it is still the value to restore).
run in_gh_home "$isg" --global
check_status "dir #659 S3-3: a plain --global re-install → exit 0" 0 "$STATUS"
check_eq "dir #659 S3-3: the re-install keeps the record" \
  "$foreign_hooks" "$(in_gh_home git config --global keel.displacedHooksPath)"
run in_gh_home "$isg" --global --uninstall
check_status "dir #659 S3-3: --global --uninstall → exit 0" 0 "$STATUS"
check_eq "dir #659 S3-3: --uninstall restores the displaced hooksPath" \
  "$foreign_hooks" "$(in_gh_home git config --global core.hooksPath)"
check_eq "dir #659 S3-3: --uninstall clears the record once restored" \
  "" "$(in_gh_home git config --global keel.displacedHooksPath || true)"
check_file "dir #659 S3-3: --uninstall leaves Keel's hook files on disk (it unwires, never deletes)" \
  "$gh_home/.config/git/keel-hooks/pre-commit"
# A second --uninstall finds a hooksPath that is not Keel's: refuse, change nothing.
run in_gh_home "$isg" --global --uninstall
check_status "dir #659 S3-3: --uninstall over a foreign hooksPath → exit 3" 3 "$STATUS"
check_eq "dir #659 S3-3: the refused --uninstall leaves the foreign hooksPath" \
  "$foreign_hooks" "$(in_gh_home git config --global core.hooksPath)"
# A record left from an earlier --force must never be overwritten by a second --force that would
# displace a DIFFERENT path (dir #625's rule, applied to the setting): refuse before any change.
other_hooks="$SANDBOX/gforce-other-hooks"; mkdir -p "$other_hooks"
in_gh_home git config --global keel.displacedHooksPath "$foreign_hooks"
in_gh_home git config --global core.hooksPath "$other_hooks"
run in_gh_home "$isg" --global --force
check_status "dir #659 S3-3: --force with a record of a DIFFERENT path → exit 3" 3 "$STATUS"
check_contains "dir #659 S3-3: that refusal names the recorded path" "$OUT" "$foreign_hooks"
check_eq "dir #659 S3-3: that refusal leaves core.hooksPath alone" \
  "$other_hooks" "$(in_gh_home git config --global core.hooksPath)"
check_eq "dir #659 S3-3: that refusal leaves the earlier record alone" \
  "$foreign_hooks" "$(in_gh_home git config --global keel.displacedHooksPath)"

# No hooksPath before: install then --uninstall leaves it unset, as it was. A record left behind while
# Keel was NOT wired (an earlier --force, then a hand `--unset core.hooksPath`) is stale: this install
# displaces nothing, so it drops that record — a later --uninstall must not resurrect a path the user
# had already removed.
gu_home="$SANDBOX/guninstall-home"; mkdir -p "$gu_home"
fresh_home_env "$gu_home"; gu_env=("${FRESH_HOME_ENV[@]}")
in_gu_home() { env "${gu_env[@]}" "$@"; }
gu_keel="$gu_home/.config/git/keel-hooks"
in_gu_home git config --global keel.displacedHooksPath "$SANDBOX/gu-stale-hooks"
run in_gu_home "$isg" --global
check_status "dir #659 S3-3: --global with no prior hooksPath → exit 0" 0 "$STATUS"
check_eq "dir #659 S3-3: nothing displaced — the stale record is dropped, not kept" \
  "" "$(in_gu_home git config --global keel.displacedHooksPath || true)"
check_contains "dir #659 S3-3: dropping the stale record names it" "$OUT" "$SANDBOX/gu-stale-hooks"
run in_gu_home "$isg" --global --uninstall
check_status "dir #659 S3-3: --uninstall with nothing recorded → exit 0" 0 "$STATUS"
check_eq "dir #659 S3-3: --uninstall with nothing recorded unsets core.hooksPath" \
  "" "$(in_gu_home git config --global core.hooksPath || true)"
# Unwired, but a record exists: --uninstall reports it and drops it rather than staying silent.
in_gu_home git config --global keel.displacedHooksPath "$SANDBOX/gu-stale-hooks-2"
run in_gu_home "$isg" --global --uninstall
check_status "dir #659 S3-3: --uninstall when unwired, with a stale record → exit 0" 0 "$STATUS"
check_contains "dir #659 S3-3: that run names the stale record" "$OUT" "$SANDBOX/gu-stale-hooks-2"
check_eq "dir #659 S3-3: that run drops the stale record" \
  "" "$(in_gu_home git config --global keel.displacedHooksPath || true)"
# Keel's own dir spelled with a literal ~/ (git expands it; a portable dotfiles gitconfig writes it) is
# Keel's, not foreign: even --force records nothing (it used to record Keel's own dir as "displaced"),
# keeps the user's spelling, and --uninstall unwires it.
# shellcheck disable=SC2088  # the LITERAL ~ is the point: git stores it verbatim
in_gu_home git config --global core.hooksPath '~/.config/git/keel-hooks'
run in_gu_home "$isg" --global --force
check_status "dir #659: a ~/-spelled Keel hooksPath is Keel's — --global --force → exit 0" 0 "$STATUS"
check_eq "dir #659: the ~/-spelled Keel dir is never recorded as displaced" \
  "" "$(in_gu_home git config --global keel.displacedHooksPath || true)"
# shellcheck disable=SC2088  # the LITERAL ~ is the point
check_eq "dir #659: the user's ~/ spelling of Keel's dir is kept, not rewritten" \
  '~/.config/git/keel-hooks' "$(in_gu_home git config --global core.hooksPath)"
run in_gu_home "$isg" --global --uninstall
check_status "dir #659: --uninstall unwires a ~/-spelled Keel hooksPath → exit 0" 0 "$STATUS"
check_eq "dir #659: … leaving core.hooksPath unset" \
  "" "$(in_gu_home git config --global core.hooksPath || true)"
# Any other spelling of the same dir — a trailing slash — is Keel's too (compared as a path).
in_gu_home git config --global core.hooksPath "$gu_keel/"
run in_gu_home "$isg" --global --uninstall
check_status "dir #659: --uninstall unwires a trailing-slash Keel hooksPath → exit 0" 0 "$STATUS"
check_eq "dir #659: … leaving core.hooksPath unset" \
  "" "$(in_gu_home git config --global core.hooksPath || true)"
# A RELATIVE hooksPath names a dir inside each repo, never Keel's: even run from the dir it would
# resolve to here, --uninstall must not read it as Keel's and unset it (no cwd-dependent `-ef`).
in_gu_home git config --global core.hooksPath ".config/git/keel-hooks"
run env "${gu_env[@]}" bash -c 'cd "$0" && exec "$1" --global --uninstall' "$gu_home" "$isg"
check_status "dir #659: a relative hooksPath is not Keel's, whatever the cwd → exit 3" 3 "$STATUS"
check_eq "dir #659: … and it is left in place" \
  ".config/git/keel-hooks" "$(in_gu_home git config --global core.hooksPath)"
in_gu_home git config --global --unset core.hooksPath
# A record that names Keel's own dir displaced nothing: --uninstall drops it and unsets, never
# "restores" Keel's own wiring while reporting it unwired.
in_gu_home git config --global core.hooksPath "$gu_keel"
in_gu_home git config --global keel.displacedHooksPath "$gu_keel/"
run in_gu_home "$isg" --global --uninstall
check_status "dir #659: --uninstall with a record naming Keel's own dir → exit 0" 0 "$STATUS"
check_eq "dir #659: … core.hooksPath is unset, not 'restored' to Keel's dir" \
  "" "$(in_gu_home git config --global core.hooksPath || true)"
check_eq "dir #659: … and that record is dropped" \
  "" "$(in_gu_home git config --global keel.displacedHooksPath || true)"
# A record with several values is refused, never compared against just the last one and wiped. (Both
# dirs exist, so it is the several-values rule that refuses, not the missing-dir one.)
mkdir -p "$SANDBOX/gu-multi-a" "$SANDBOX/gu-multi-b"
in_gu_home git config --global core.hooksPath "$gu_keel"
in_gu_home git config --global --add keel.displacedHooksPath "$SANDBOX/gu-multi-a"
in_gu_home git config --global --add keel.displacedHooksPath "$SANDBOX/gu-multi-b"
run in_gu_home "$isg" --global --uninstall
check_status "dir #659: a multi-valued record → refused, exit 3" 3 "$STATUS"
check_eq "dir #659: … both recorded values survive" \
  "2" "$(in_gu_home git config --global --get-all keel.displacedHooksPath | wc -l | tr -d ' ')"
in_gu_home git config --global --unset-all keel.displacedHooksPath
# A recorded path that no longer exists is not restored: a global hooksPath naming a missing dir makes
# git skip every repo's own hooks. Refuse and change nothing.
in_gu_home git config --global core.hooksPath "$gu_keel"
in_gu_home git config --global keel.displacedHooksPath "$SANDBOX/gu-deleted-hooks"
run in_gu_home "$isg" --global --uninstall
check_status "dir #659 S3-3: --uninstall with a recorded dir that no longer exists → exit 3" 3 "$STATUS"
check_eq "dir #659 S3-3: that refusal leaves Keel's hooksPath in place" \
  "$gu_keel" "$(in_gu_home git config --global core.hooksPath)"
check_eq "dir #659 S3-3: that refusal leaves the record in place" \
  "$SANDBOX/gu-deleted-hooks" "$(in_gu_home git config --global keel.displacedHooksPath)"
run in_gu_home "$isg" --global --uninstall --force
check_status "dir #659: --uninstall and --force don't combine → exit 2 (as the sibling installers)" 2 "$STATUS"
run "$isg" --uninstall "$frepo"
check_status "dir #659 S3-3: --uninstall is --global only → exit 2 for a repo path" 2 "$STATUS"
check_contains "dir #659 S3-3: the repo-path --uninstall refusal says why" "$OUT" "--uninstall works with --global only"
check_contains "dir #659: the repo-path refusal names the --force backup to move back" "$OUT" ".pre-keel.bak"

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

# =================================================================================================
# --- dir #617(a): a repo argument to install-secret-guard.sh must never cause a write outside that
# repo's own git dir — the mechanism behind two felt incidents (0.11.0 RC's F1: a review subagent's
# own install_into reproduction flipped a mode bit on the real live ~/.keel/kb/githooks-global;
# 0.11.0 W12: an ad-hoc verification script hit the same class). `git rev-parse --git-path hooks`
# (the pre-fix resolution for a repo with no LOCAL hooksPath override) honors core.hooksPath from ANY
# scope, including GLOBAL or SYSTEM — so on a machine that already ran `install-secret-guard.sh
# --global` (or has any unrelated global/system hooksPath set), every plain `install-secret-guard.sh
# <repo>` call for a repo with no local override silently redirected into that machine-wide dir
# instead of the repo. This is a NEGATIVE claim ("cannot write outside") — proven the way memory
# reference_deny_assertion_does_not_bind_in_fail_closed_system insists on: snapshot the fake hooks
# dir's CONTENT before and after each vendor call, not just its exit status — an exit-0-only check
# would have passed on the pre-fix code too, whose own (misdirected) vendor call also exits 0. Two
# independent axes, each covered on its own: TOPOLOGY (a plain repo, a worktree — hooks live in the
# MAIN checkout's common dir, not the linked worktree's own gitdir — and a submodule — hooks live in
# the SUPERPROJECT's .git/modules/<name>, outside the submodule's own working tree) via the loop
# below, and CONFIG SCOPE (GLOBAL vs SYSTEM) via the separate SYSTEM-scope case further down — the two
# are independent, so one topology is enough to prove the scope axis. Isolated via fresh_home_env, not
# a bare `git config --global` on the file-wide shared sandbox config — this fixture's whole point is
# a machine-wide hooksPath override, and mutating the SHARED config directly would leak that override
# to every later test in the file if anything went wrong before an eventual unset (the dir #85
# --global-force block above already established this exact idiom for the same core.hooksPath key).
gh617_home="$SANDBOX/gh617-home"; mkdir -p "$gh617_home"
fresh_home_env "$gh617_home"; gh617_env=("${FRESH_HOME_ENV[@]}")
in_gh617_home() { env "${gh617_env[@]}" "$@"; }

grepo="$(new_repo)"

gwtbase="$(new_repo)"; git -C "$gwtbase" commit -qm seed --allow-empty
gwt="$SANDBOX/gwt-617"
git -C "$gwtbase" worktree add -q -b wt-617 "$gwt"

gsuper="$(new_repo)"; git -C "$gsuper" commit -qm seed --allow-empty
gsubsrc="$(new_repo)"; git -C "$gsubsrc" commit -qm seed --allow-empty
run git -c protocol.file.allow=always -C "$gsuper" submodule add -q "$gsubsrc" sub
check_status "dir #617(a) setup: submodule add succeeds" 0 "$STATUS"

# One record per shape (label|target|expected), not three parallel arrays matched only by numeric
# position — a future edit to one array without the other two would silently mispair label/target/
# expected instead of erroring (code review finding). WORKTREE gets its OWN base repo ($gwtbase, not
# $grepo) so its expected path is never one an earlier shape's own check already populated — sharing
# $grepo's path made that assertion vacuous: it would still pass even if worktree resolution broke
# entirely elsewhere (code review finding, confirmed by mutation test). Each shape also gets its OWN
# fresh fake-global directory, created right before its own vendor call — sharing one directory across
# iterations let a same-name/same-size overwrite within the same wall-clock minute go invisible to an
# `ls -la` text diff, silently losing the "untouched" check's power for two of the three shapes (code
# review finding, confirmed by mutation-testing against the pre-fix installer).
shapes=(
  "repo|$grepo|$grepo/.git/hooks/secret-scan.sh"
  "WORKTREE|$gwt|$gwtbase/.git/hooks/secret-scan.sh"
  "SUBMODULE|$gsuper/sub|$gsuper/.git/modules/sub/hooks/secret-scan.sh"
)
for shape in "${shapes[@]}"; do
  IFS='|' read -r label target expected <<< "$shape"
  fake_global="$SANDBOX/fake-global-hooks-617-$label"
  mkdir -p "$fake_global"
  in_gh617_home git config --global core.hooksPath "$fake_global"
  before_global="$(ls -la "$fake_global")"
  run in_gh617_home "$isg" "$target"
  check_status "dir #617(a): vendor into a $label, global hooksPath set elsewhere → still succeeds" 0 "$STATUS"
  check_block_equal "dir #617(a): $label vendor leaves the global hooks dir untouched" "$before_global" "$(ls -la "$fake_global")"
  check_file "dir #617(a): the $label's hooks dir got the vendored copy" "$expected"
done

# SYSTEM scope is a genuinely distinct leak vector from GLOBAL, not just the same case retested — old
# `git rev-parse --git-path hooks` honors it too, but `fresh_home_env` only isolates HOME/
# GIT_CONFIG_GLOBAL, so the loop above never exercises it (code review finding: this file's own
# comment above, CHANGELOG.md, and install-secret-guard.sh's own comment all claim "GLOBAL or SYSTEM"
# coverage, but SYSTEM was asserted, never tested). A dedicated GIT_CONFIG_SYSTEM override, on its own
# isolated home with no global hooksPath set at all, isolates the axis cleanly; one topology (plain
# repo) is enough since topology is already covered above and the two axes are independent.
gh617_sys_home="$SANDBOX/gh617-sys-home"; mkdir -p "$gh617_sys_home"
fresh_home_env "$gh617_sys_home"
gh617_sys_env=("${FRESH_HOME_ENV[@]}" "GIT_CONFIG_SYSTEM=$gh617_sys_home/gitconfig-system")
in_gh617_sys_home() { env "${gh617_sys_env[@]}" "$@"; }
fake_system="$SANDBOX/fake-system-hooks-617"; mkdir -p "$fake_system"
in_gh617_sys_home git config --system core.hooksPath "$fake_system"

gsysrepo="$(new_repo)"
before_system="$(ls -la "$fake_system")"
run in_gh617_sys_home "$isg" "$gsysrepo"
check_status "dir #617(a): vendor into a repo, SYSTEM hooksPath set elsewhere → still succeeds" 0 "$STATUS"
check_block_equal "dir #617(a): SYSTEM-scope vendor leaves the system hooks dir untouched" "$before_system" "$(ls -la "$fake_system")"
check_file "dir #617(a): the repo's own hooks dir got the vendored copy (SYSTEM-scope case)" "$gsysrepo/.git/hooks/secret-scan.sh"

# =================================================================================================
# --- dir #644: an inherited GIT_DIR / GIT_COMMON_DIR must never redirect install-secret-guard.sh's
# <repo> branch into a DIFFERENT repository than the one named on the command line — including its
# own validity gate: the ticket's own claim is that this hijack works "even when $repo is not a git
# repo at all", i.e. the ambient vars can make the FIRST `git -C "$repo" rev-parse
# --is-inside-work-tree` falsely pass for a non-git path. `decoy644` stands in for whatever repo an
# operator's (or a peer process's) already-exported GIT_DIR/GIT_COMMON_DIR happens to name; `repo644`
# is the repo actually named on the command line, the one the vendor write is SUPPOSED to land in.
#
# `snapshot_tree_cksum` (tests/lib.sh) is a stronger byte-identical proof than the dir #617(a) block's
# own `ls -la`: this ticket's write is a HOOK FILE (content, not just presence/size/mtime-minute), so
# a path+content-hash snapshot of every file under decoy644/.git is what actually rules out a leak,
# the same reasoning check_block_equal's own header comment gives for choosing content over a
# directory listing.
# =================================================================================================
decoy644="$(new_repo)"; git -C "$decoy644" commit -qm seed --allow-empty
decoy644_gitdir="$(git -C "$decoy644" rev-parse --git-dir)"
case "$decoy644_gitdir" in /*) ;; *) decoy644_gitdir="$decoy644/$decoy644_gitdir" ;; esac
decoy644_common="$(git -C "$decoy644" rev-parse --git-common-dir)"
case "$decoy644_common" in /*) ;; *) decoy644_common="$decoy644/$decoy644_common" ;; esac
in_ambient644() { env GIT_DIR="$decoy644_gitdir" GIT_COMMON_DIR="$decoy644_common" "$@"; }
decoy644_before="$(snapshot_tree_cksum "$decoy644/.git")"

repo644="$(new_repo)"
run in_ambient644 "$isg" "$repo644"
check_status "dir #644: vendor into a valid <repo> under an ambient GIT_DIR/GIT_COMMON_DIR → still succeeds" 0 "$STATUS"
check_file "dir #644: the vendor write landed in repo644's own hooks dir, not the decoy" "$repo644/.git/hooks/secret-scan.sh"
check_block_equal "dir #644: the decoy repo is byte-identical before/after the valid-<repo> vendor" \
  "$decoy644_before" "$(snapshot_tree_cksum "$decoy644/.git")"

notrepo644="$(mktemp -d "$SANDBOX/notrepo644.XXXXXX")"
run in_ambient644 "$isg" "$notrepo644"
check_ne "dir #644: a non-git <repo> is refused regardless of the ambient GIT_DIR/GIT_COMMON_DIR" 0 "$STATUS"
check_contains "dir #644: the refusal names it as not a git repo" "$OUT" "not a git repo"
check_nofile "dir #644: no hooks were written into the non-git <repo>" "$notrepo644/.git/hooks/secret-scan.sh"
check_block_equal "dir #644: the decoy repo is STILL byte-identical after the refused non-git attempt" \
  "$decoy644_before" "$(snapshot_tree_cksum "$decoy644/.git")"

# --- dir #647 (A5): --selftest builds throwaway probe repos with `git -C "$x" ...`. Under an inherited
# GIT_DIR (git exports one to hooks, `!` aliases and `rebase --exec` in a worktree) those commits and
# tags landed in the REAL repo GIT_DIR named (E7). R is a repo the selftest must never touch.
r647="$(new_repo)"
git -C "$r647" commit -q --allow-empty -m seed
r647_head="$(git -C "$r647" rev-parse HEAD)"
r647_refs="$(git -C "$r647" for-each-ref)"
run env GIT_DIR="$r647/.git" "$scan" --selftest
check_status "dir #647 A5: --selftest under GIT_DIR=<real repo> -> exit 0" 0 "$STATUS"
check_absent "dir #647 A5: --selftest under GIT_DIR=<real repo> reports no FAIL" "$OUT" "selftest: FAIL"
check_eq "dir #647 A5: the real repo's HEAD is unchanged by the selftest" "$r647_head" "$(git -C "$r647" rev-parse HEAD)"
check_eq "dir #647 A5: the real repo's refs are unchanged (no probe commit/tag landed in it)" "$r647_refs" "$(git -C "$r647" for-each-ref)"

# --- dir #647 (A6, pins B4): the hook modes must KEEP the inherited variables. Inside a linked worktree
# git hands the pre-commit hook GIT_DIR=<main>/.git/worktrees/<wt> and, for `git commit -a` / `git commit
# <path>`, a GIT_INDEX_FILE naming a TEMPORARY index that holds the change being committed (E2, E8).
# Dropping GIT_INDEX_FILE at the scanner's top level makes `git diff --cached` read the stale real index
# and scan nothing — the guard opens. A real fake key, unstaged, committed with `-a` from a worktree must
# still be blocked.
h647="$(new_repo)"
git -C "$h647" commit -q --allow-empty -m seed
printf 'clean\n' > "$h647/f.txt"; git -C "$h647" add f.txt; git -C "$h647" commit -q -m base
run bash "$isg" "$h647"
check_status "dir #647 A6: vendoring the guard into the fixture repo -> exit 0" 0 "$STATUS"
hw647="$SANDBOX/h647-wt"
git -C "$h647" worktree add -q -b wt-h647 "$hw647" >/dev/null 2>&1
printf '%s\n' "aws = $(key 'AKIA' "$(rep A 16)")" > "$hw647/f.txt"   # modified, NOT staged
head647="$(git -C "$hw647" rev-parse HEAD)"
run_in "$hw647" git commit -a -m "leak via -a"
check_ne "dir #647 A6: git commit -a of an unstaged key from a worktree is blocked (non-zero)" "$STATUS" "0"
check_contains "dir #647 A6: the block names the secret guard" "$OUT" "BLOCKED"
check_eq "dir #647 A6: HEAD did not move" "$head647" "$(git -C "$hw647" rev-parse HEAD)"
# Mutation proof, kept as an assertion: the SAME vendored scanner with the guard line added at TOP LEVEL
# lets that commit through — i.e. the carve-out above is load-bearing, not decorative.
insert_before_line_containing "$h647/.git/hooks/secret-scan.sh" "selftest() {" "unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE"
chmod +x "$h647/.git/hooks/secret-scan.sh"   # the helper rewrites through a temp file and mv
run_in "$hw647" git commit -a -m "leak via -a, top-level unset"
check_status "dir #647 A6 mutation: a top-level unset in the scanner lets the key commit through (the carve-out is load-bearing)" 0 "$STATUS"

# --- dir #546: the pre-push hook must not refuse a push whose remote tip is UNKNOWN locally (a force-push
# from a fresh `git filter-repo` clone — filter-repo drops `origin` and the old objects by design — or any
# push from a clone that never fetched the old tip). BEFORE = a non-zero sha that is no object here, so
# `BEFORE..AFTER` is unresolvable; the guard must scan what it CAN (everything not already on a remote,
# the zero-sha shape) instead of exiting on "bad range". The fixtures have no remote at all — the
# filter-repo'd shape — so the scan is the whole history.
unknown_before="$(rep b 40)"
prepush_unknown() {  # REPO — feed the hook one push: HEAD over a remote tip that is not an object here
  local sha; sha="$(git -C "$1" rev-parse HEAD)"
  OUT="$(cd "$1" && printf 'refs/heads/main %s refs/heads/main %s\n' "$sha" "$unknown_before" | bash "$prepush" 2>&1)"; STATUS=$?
}

repo="$(new_repo)"
printf 'nothing secret here\n' > "$repo/ok.txt"; git -C "$repo" add ok.txt; git -C "$repo" commit -qm base
printf 'still nothing\n' > "$repo/ok2.txt"; git -C "$repo" add ok2.txt; git -C "$repo" commit -qm second
prepush_unknown "$repo"
check_status "dir #546: pre-push over an unknown remote tip, clean history → exit 0 (not 'bad range')" 0 "$STATUS"
check_absent "dir #546: ...and never prints the unresolvable-range error" "$OUT" "not resolvable"
check_contains "dir #546: ...but says the remote tip is unknown, so the operator knows the scan widened" "$OUT" "not known in this repo"

repo="$(new_repo)"
printf 'hello\n' > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm base
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$repo/b.txt"
git -C "$repo" add b.txt; git -C "$repo" commit -qm withkey
printf 'more\n' > "$repo/c.txt"; git -C "$repo" add c.txt; git -C "$repo" commit -qm after
prepush_unknown "$repo"
check_status "dir #546: a planted secret behind an unknown remote tip is still BLOCKED (the fallback never scans nothing)" 1 "$STATUS"
check_contains "dir #546: ...and reports BLOCKED" "$OUT" "BLOCKED"
check_contains "dir #546: ...naming the planted file" "$OUT" "b.txt"

# the allow-list arm (G6 finding 7): with no remote the boundary set is EMPTY. An allow-list file in the repo
# that exempts nothing in this history costs nothing — a clean scan returns before the baseline is read.
repo="$(new_repo)"
printf '%s\n' "$(key 'ghp_' 'A')" > "$repo/.secret-scan-allow"
printf 'nothing secret here\n' > "$repo/ok.txt"
git -C "$repo" add .secret-scan-allow ok.txt; git -C "$repo" commit -qm "base + allowlist"
prepush_unknown "$repo"
check_status "dir #546: an allow-list file in use that exempts nothing here, unknown remote tip → exit 0" 0 "$STATUS"

# An entry that DOES exempt a match in the pushed history stays untrusted: no remote means no pre-push
# baseline to prove the entry predates this push, and the same-change rule (dir #508 (a)) is the
# security property — it fails closed, with the recipe naming the way through. Pinned so a later
# "make it pass" cannot silently trust an entry the guard cannot date.
repo="$(new_repo)"
printf '%s\n' "$(key 'ghp_' 'A')" > "$repo/.secret-scan-allow"
git -C "$repo" add .secret-scan-allow; git -C "$repo" commit -qm "add allowlist"
printf '%s\n' "$(key 'ghp_' "$(rep A 36)")" > "$repo/key.txt"
git -C "$repo" add key.txt; git -C "$repo" commit -qm "add key the allowlist exempts"
prepush_unknown "$repo"
check_status "dir #546: an allow-list entry exempting a match, unknown remote tip and no remote → fail closed (no baseline)" 1 "$STATUS"
check_contains "dir #546: ...with the same-change message" "$OUT" "ignoring an allowlist entry new in this change"

# =================================================================================================
# --- dir #148: ONE parser for the personal-literals file. tools/lib/personal-literals.sh is the
# canonical copy (public-audit.sh sources it); secret-scan.sh is vendored and may source only what
# ships beside it, so it carries an inline IN-SYNC twin, _personal_literals_parse_inline. This section
# is the sync + golden test the twin's comment names: lib and twin run on shared fixtures, both must
# match the expected output written LITERALLY below, and their bodies must be textually identical (a
# branch no fixture reaches cannot drift either). ------------------------------------------------
pl_lib="$REPO_ROOT/tools/lib/personal-literals.sh"
pa="$REPO_ROOT/tools/public-audit.sh"

# A1/A3/A4 structural pins (the spec's grep checks, kept as assertions).
check_file "dir #148: tools/lib/personal-literals.sh exists" "$pl_lib"
if [ -f "$pl_lib" ] && grep -q '^personal_literals_parse()' "$pl_lib" \
   && grep -qF '[ -f "$1" ] || return 0' "$pl_lib"; then
  pass "dir #148 A1: the lib defines personal_literals_parse and tests [ -f ] exactly"
else
  fail "dir #148 A1: the lib defines personal_literals_parse and tests [ -f ] exactly" "missing in $pl_lib"
fi
pl_sed='s/[[:space:]][[:space:]]*#.*$//'
check_eq "dir #148 A3: public-audit.sh no longer carries the comment-strip sed" 0 "$(grep -cF "$pl_sed" "$pa")"
check_eq "dir #148 A3: public-audit.sh sources the lib on a real line" 1 "$(grep -cE '^\. .*lib/personal-literals\.sh"' "$pa")"
if [ "$(grep -cE '^[^#]*personal_literals_parse "\$PERSONAL_FILE"' "$pa")" -ge 1 ]; then
  pass "dir #148 A3: public-audit.sh CALLS the parser on a non-comment line"
else
  fail "dir #148 A3: public-audit.sh CALLS the parser on a non-comment line" "no call line"
fi
check_eq "dir #148 A4: secret-scan.sh carries the one comment-strip sed (the twin's)" 1 "$(grep -cF "$pl_sed" "$scan")"
check_eq "dir #148 A4: secret-scan.sh defines the inline twin once" 1 "$(grep -c '^_personal_literals_parse_inline() {' "$scan")"
check_eq "dir #148 A4: secret-scan.sh sources nothing" 0 "$(grep -cE '^[[:space:]]*(\.|source)[[:space:]]' "$scan")"
check_eq "dir #148 A4: the PERSONAL_FILE= default line is byte-identical (kb-secret-scan.sh sed-extracts it)" 1 \
  "$(grep -cF 'PERSONAL_FILE="${SECRET_SCAN_PERSONAL_FILE:-$HOME/.claude/secret-scan-personal}"' "$scan")"
# dir #680: the capture keeps its status (`|| _personal_rc=$?`) for the explicit exit-2 handling right
# below it — a bare capture, a `|| true` or a process substitution fails this pin.
check_eq "dir #148 A4: the twin is CALLED by a plain top-level capture of \$PERSONAL_FILE (status kept)" 1 \
  "$(grep -cE '^[A-Za-z_][A-Za-z0-9_]*="\$\(_personal_literals_parse_inline "\$PERSONAL_FILE"\)" \|\| [A-Za-z_][A-Za-z0-9_]*=\$\?$' "$scan")"
# the scanner joins with `tr`: ${var//$'\n'/|} is roughly cubic on bash <= 4.1 (macOS /bin/bash 3.2)
check_eq "dir #148: the scanner's join is not the cubic-on-bash-3.2 expansion" 0 "$(grep -cF '${_personal_lines//' "$scan")"

# The fixture (v3): CRLF, inline comment, tabs, `a#b`, a backslash, internal spaces, a glob, non-ASCII
# (octal bytes, so this file stays ASCII), a `-n` line (an echo-based emit would swallow it), and a last
# line without a newline. The expected output is literal text — never produced by running either copy.
pl_fixture="$SANDBOX/pl148-fixture"
printf '# header comment\n\n   \nalpha\r\n  beta  \ngamma # trailing comment\n\tdelta\t\nep#silon\n   # indented comment\nzeta\\.eta\n  two  words  \nglob*[x]?\n\320\230\320\262\320\260\320\275\n-n\nlast-no-newline' > "$pl_fixture"
pl_golden="$(printf 'alpha\nbeta\ngamma\ndelta\nep#silon\nzeta\\.eta\ntwo  words\nglob*[x]?\n\320\230\320\262\320\260\320\275\n-n\nlast-no-newline\n')"

pl_twin_fn="$(sed -n '/^_personal_literals_parse_inline() {/,/^}/p' "$scan")"
if [ -z "$pl_twin_fn" ]; then
  fail "dir #148: secret-scan.sh's _personal_literals_parse_inline located" "no such function found in $scan"
else
  pass "dir #148: secret-scan.sh's _personal_literals_parse_inline located"
fi
pl_lib_fn="$(sed -n '/^personal_literals_parse() {/,/^}/p' "$pl_lib" 2>/dev/null)"
if [ -z "$pl_lib_fn" ]; then
  fail "dir #148: the lib's personal_literals_parse located" "no such function found in $pl_lib"
else
  pass "dir #148: the lib's personal_literals_parse located"
fi

# Run each copy on FILE; sets PL_LIB_OUT/ERR/RC and PL_TWIN_OUT/ERR/RC. The twin is the function
# extracted from the scanner file (never the lib twice); both run under plain `bash`.
pl_run_both() {
  PL_LIB_OUT="$(bash -c '. "$1"; personal_literals_parse "$2"' _ "$pl_lib" "$1" 2>"$SANDBOX/pl148-err")"; PL_LIB_RC=$?
  PL_LIB_ERR="$(cat "$SANDBOX/pl148-err")"
  PL_TWIN_OUT="$(bash -c "$pl_twin_fn"$'\n''_personal_literals_parse_inline "$1"' _ "$1" 2>"$SANDBOX/pl148-err")"; PL_TWIN_RC=$?
  PL_TWIN_ERR="$(cat "$SANDBOX/pl148-err")"
}
pl_case() {  # desc file expected-output [expected-status, default 0]
  pl_run_both "$2"
  check_eq "dir #148 sync ($1): lib output = the literal expected output" "$3" "$PL_LIB_OUT"
  check_eq "dir #148 sync ($1): twin output = the literal expected output" "$3" "$PL_TWIN_OUT"
  check_eq "dir #148 sync ($1): lib status" "${4:-0}" "$PL_LIB_RC"
  check_eq "dir #148 sync ($1): twin status" "${4:-0}" "$PL_TWIN_RC"
}
pl_case "full fixture" "$pl_fixture" "$pl_golden"
pl_case "absent file" "$SANDBOX/pl148-absent" ""
: > "$SANDBOX/pl148-empty"
pl_case "empty file" "$SANDBOX/pl148-empty" ""
printf '# only a comment\n\n   \n\t# indented\n' > "$SANDBOX/pl148-comments"
pl_case "comments and blanks only" "$SANDBOX/pl148-comments" ""
printf 'dup\ndup\n' > "$SANDBOX/pl148-dup"
pl_case "duplicates are kept" "$SANDBOX/pl148-dup" "$(printf 'dup\ndup')"
# Not a regular file: nothing printed, NOTHING on stderr, rc 0 (a `[ -e ]` reads a directory with a read
# error; /dev/null is what kb-secret-scan.sh's selftest sets).
mkdir -p "$SANDBOX/pl148-dir"
for pl_nf in "$SANDBOX/pl148-dir" /dev/null; do
  pl_run_both "$pl_nf"
  check_eq "dir #148 sync (non-regular $pl_nf): lib prints nothing" "" "$PL_LIB_OUT"
  check_eq "dir #148 sync (non-regular $pl_nf): twin prints nothing" "" "$PL_TWIN_OUT"
  check_eq "dir #148 sync (non-regular $pl_nf): lib stderr empty" "" "$PL_LIB_ERR"
  check_eq "dir #148 sync (non-regular $pl_nf): twin stderr empty" "" "$PL_TWIN_ERR"
  check_eq "dir #148 sync (non-regular $pl_nf): lib rc 0" 0 "$PL_LIB_RC"
  check_eq "dir #148 sync (non-regular $pl_nf): twin rc 0" 0 "$PL_TWIN_RC"
done
# Textual body identity (B5): both extracted functions, declaration line dropped, byte-identical — so an
# edit to a branch no fixture reaches in ONE copy still fails here.
check_block_equal "dir #148 sync: lib and twin function bodies are byte-identical (edit BOTH copies)" \
  "$(printf '%s\n' "$pl_lib_fn" | sed 1d)" "$(printf '%s\n' "$pl_twin_fn" | sed 1d)"

# --- end to end over the JOIN (parse-level cases cannot see it): both tools join the parsed lines.
# `zetaXeta` must NOT match the correct regex `zeta\.eta`; a build that loses the backslash (a `read`
# without -r) matches it. (`two  words` is one of the per-literal samples below.)
pl_scan_exit() {  # sample [personal-file]; sets STATUS/OUT from the staged scan of a file holding ONLY the sample
  local r; r="$(new_repo)"
  printf '%s\n' "$1" > "$r/sample.txt"
  git -C "$r" add sample.txt
  [ "$1" != glo ] || : > "$r/globxy"   # glob-expansion decoy: a real file, cwd = repo root
  run_in "$r" env SECRET_SCAN_PERSONAL_FILE="${2:-$pl_fixture}" "$scan" --staged
}
PL_TREE_LABEL="personal literal (secret-scan-personal) in tracked tree"
pl_audit_has_tree_label() {  # sample [personal-file]; sets OUT, returns 0 when the tree label is reported
  local d; d="$(new_repo)"
  printf '%s\n' "$1" > "$d/sample.txt"
  [ "$1" != glo ] || printf 'decoy\n' > "$d/globxy"
  git -C "$d" add -A
  git -C "$d" commit -qm init
  run_in "$d" env SECRET_SCAN_PERSONAL_FILE="${2:-$pl_fixture}" bash "$pa" --no-history "$d"
  case "$OUT" in *"$PL_TREE_LABEL"*) return 0 ;; *) return 1 ;; esac
}
pl_scan_exit zetaXeta
check_status "dir #148 e2e: scanner, zetaXeta does not match zeta\\.eta → exit 0" 0 "$STATUS"
if pl_audit_has_tree_label zetaXeta; then
  fail "dir #148 e2e: audit, zetaXeta reports no personal tree hit" "$OUT"
else
  pass "dir #148 e2e: audit, zetaXeta reports no personal tree hit"
fi

# Per-literal e2e: EACH of the 11 golden literals, one sample its ERE matches, one separate run per tool.
# Kills a tool that parses with a private loop (CRLF `alpha`, inline-comment `gamma` stop matching), a
# dropped last-line guard (`last-no-newline`), and a join that glob-expands (`glo` is matched by
# `glob*[x]?`; the repo holds a file NAMED globxy, and both tools run with the repo root as cwd).
pl_cyr="$(printf '\320\230\320\262\320\260\320\275')"
for pl_sample in alpha beta gamma delta 'ep#silon' 'zeta.eta' 'two  words' glo "$pl_cyr" 'x-n' 'last-no-newline'; do
  pl_scan_exit "$pl_sample"
  check_status "dir #148 e2e per-literal: scanner blocks '$pl_sample'" 1 "$STATUS"
  if pl_audit_has_tree_label "$pl_sample"; then
    pass "dir #148 e2e per-literal: audit reports the tree label for '$pl_sample'"
  else
    fail "dir #148 e2e per-literal: audit reports the tree label for '$pl_sample'" "$OUT"
  fi
done

# Default path: SECRET_SCAN_PERSONAL_FILE UNSET (env -u), the fixture at $HOME/.claude/secret-scan-personal.
mkdir -p "$HOME/.claude"
cp "$pl_fixture" "$HOME/.claude/secret-scan-personal"
pl_dr="$(new_repo)"; printf 'alpha\n' > "$pl_dr/sample.txt"; git -C "$pl_dr" add sample.txt
run_in "$pl_dr" env -u SECRET_SCAN_PERSONAL_FILE "$scan" --staged
check_status "dir #148 default path: scanner reads \$HOME/.claude/secret-scan-personal → blocks 'alpha'" 1 "$STATUS"
pl_dd="$(new_repo)"; printf 'alpha\n' > "$pl_dd/sample.txt"
git -C "$pl_dd" add -A; git -C "$pl_dd" commit -qm init
run_in "$pl_dd" env -u SECRET_SCAN_PERSONAL_FILE bash "$pa" --no-history "$pl_dd"
check_contains "dir #148 default path: audit reads the default file → tree label" "$OUT" "$PL_TREE_LABEL"
rm -f "$HOME/.claude/secret-scan-personal"

# (The unreadable-file contract — status 2, scanner exit 2, audit GAP — is pinned in the dir #680 section below.)

# =================================================================================================
# --- dir #680: the personal-literals file's three fail-opens, fixed once in the parser (lib + inline
# twin, kept in sync by the dir #148 section above) and acted on by each caller's own policy.
#   unreadable file, or a symlink to nothing → parser returns 2; scanner says so and exits 2, audit GAP
#   the per-line sed failing → parser returns 4 (a locale-aware sed errors on an invalid byte; it used to
#       be swallowed inside the $(...) capture, where errexit is off, and the literal silently dropped)
#   a UTF-8 BOM at the start of any line → stripped (it used to ride into the literal)
#   a line ending in an ODD run of `\` → not emitted, parser returns 3 (it used to join the next line
#       into `prev\|next`, a VALID ERE matching neither literal); scanner exits 2, audit raises its own GAP
# Fixtures are printf-built with octal bytes so this file stays ASCII.

# parser level: lib and twin agree on output AND status, against literal expectations.
printf '\357\273\277zorblaxname\nsecond\n' > "$SANDBOX/pl680-bom"
pl_case "BOM before the first literal is stripped" "$SANDBOX/pl680-bom" "$(printf 'zorblaxname\nsecond')" 0
printf '\357\273\277# a comment after the BOM\nreal\n' > "$SANDBOX/pl680-bomcomment"
pl_case "BOM before a comment line: the line is still a comment" "$SANDBOX/pl680-bomcomment" "real" 0
printf 'first\n\357\273\277second\n' > "$SANDBOX/pl680-bom2"
pl_case "a BOM at the start of a LATER line (cat a b > file) is stripped too" "$SANDBOX/pl680-bom2" "$(printf 'first\nsecond')" 0
printf 'prevlit\\\nnextlit\n' > "$SANDBOX/pl680-trail"
pl_case "a line ending in a backslash is withheld, the rest still parses, status 3" "$SANDBOX/pl680-trail" "nextlit" 3
printf 'evenback\\\\\nafter\n' > "$SANDBOX/pl680-even"
pl_case "an EVEN trailing backslash run is a valid literal backslash: kept, status 0" "$SANDBOX/pl680-even" "$(printf 'evenback\\\\\nafter')" 0
printf 'a b \\ \nnext\n' > "$SANDBOX/pl680-trailspace"
pl_case "a backslash followed by trailing whitespace is trimmed first, then flagged" "$SANDBOX/pl680-trailspace" "next" 3
printf 'lonely\\' > "$SANDBOX/pl680-nonl"
pl_case "a final line with no newline ending in a backslash is flagged too" "$SANDBOX/pl680-nonl" "" 3

# end to end — scanner: the BOM'd first literal now blocks; a trailing backslash fails CLOSED (exit 2).
pl_scan_exit "hi zorblaxname" "$SANDBOX/pl680-bom"
check_status "dir #680 e2e: scanner blocks the BOM-prefixed first literal" 1 "$STATUS"
pl_scan_exit "has nextlit here" "$SANDBOX/pl680-trail"
check_status "dir #680 e2e: scanner exits 2 on a line ending in a backslash (not 'clean' rc 0)" 2 "$STATUS"
check_contains "dir #680 e2e: ...and says why" "$OUT" "backslash"
check_absent "dir #680 e2e: ...without printing the offending literal" "$OUT" "prevlit"
check_absent "dir #680 e2e: ...and never 'secret-scan: clean'" "$OUT" "secret-scan: clean"
pl_scan_exit "has evenback\\ here" "$SANDBOX/pl680-even"
check_status "dir #680 e2e: scanner accepts an even trailing backslash run and blocks its literal" 1 "$STATUS"
# end to end — audit: BOM'd literal → tree label; trailing backslash → GAP naming the invalid line, the
# remaining literals still scanned.
if pl_audit_has_tree_label "hi zorblaxname" "$SANDBOX/pl680-bom"; then
  pass "dir #680 e2e: audit reports the BOM-prefixed first literal"
else
  fail "dir #680 e2e: audit reports the BOM-prefixed first literal" "$OUT"
fi
if pl_audit_has_tree_label "has nextlit here" "$SANDBOX/pl680-trail"; then
  pass "dir #680 e2e: audit still scans the literals after a flagged line"
else
  fail "dir #680 e2e: audit still scans the literals after a flagged line" "$OUT"
fi
check_status "dir #680 e2e: audit exits 1 on a flagged line" 1 "$STATUS"
check_contains "dir #680 e2e: audit says a line ends in a backslash / coverage incomplete" "$OUT" "end in a backslash"
check_absent "dir #680 e2e: audit never echoes the flagged literal" "$OUT" "prevlit"

# a symlink to nothing is an existing-but-unusable file, not an absent one (the operator's default
# ~/.claude/secret-scan-personal is a symlink into the KB: a moved KB must not silently turn the class off).
# Works as root too, so it is not behind the uid guard.
ln -s "$SANDBOX/pl680-no-such-target" "$SANDBOX/pl680-dangling"
pl_case "a symlink to nothing is unusable, not absent: status 2, nothing printed" "$SANDBOX/pl680-dangling" "" 2
ln -s "$pl_fixture" "$SANDBOX/pl680-link-ok"
pl_case "a symlink to a real file still parses (the full fixture)" "$SANDBOX/pl680-link-ok" "$pl_golden"
pl_scan_exit "hello zebracorn" "$SANDBOX/pl680-dangling"
check_status "dir #680: scanner exits 2 on a symlink to nothing" 2 "$STATUS"
check_contains "dir #680: ...and says it cannot read or parse the file" "$OUT" "cannot read or parse"
check_absent "dir #680: ...and never 'secret-scan: clean'" "$OUT" "secret-scan: clean"
pl_ad="$(new_repo)"; printf 'hello zebracorn\n' > "$pl_ad/sample.txt"
git -C "$pl_ad" add -A; git -C "$pl_ad" commit -qm init
run env SECRET_SCAN_PERSONAL_FILE="$SANDBOX/pl680-dangling" bash "$pa" --no-history "$pl_ad"
check_status "dir #680: audit exits 1 (a GAP) on a symlink to nothing" 1 "$STATUS"
check_contains "dir #680: ...the GAP says coverage is ZERO" "$OUT" "coverage is ZERO"

# the per-line sed failing (a sed that exits 1 first on PATH — deterministic stand-in for BSD sed's
# 'illegal byte sequence' under a UTF-8 locale, which no ambient-C-locale test can reach): parser status 4,
# scanner exit 2, audit GAP — never a silently dropped literal.
pl_shim="$SANDBOX/pl680-sedshim"; mkdir -p "$pl_shim"
printf '#!/bin/sh\nexit 1\n' > "$pl_shim/sed"; chmod +x "$pl_shim/sed"
printf 'zebracorn\n' > "$SANDBOX/pl680-onelit"
pl680_lib_rc=0; PATH="$pl_shim:$PATH" bash -c '. "$1"; personal_literals_parse "$2"' _ "$pl_lib" "$SANDBOX/pl680-onelit" >/dev/null 2>&1 || pl680_lib_rc=$?
pl680_twin_rc=0; PATH="$pl_shim:$PATH" bash -c "$pl_twin_fn"$'\n''_personal_literals_parse_inline "$1"' _ "$SANDBOX/pl680-onelit" >/dev/null 2>&1 || pl680_twin_rc=$?
check_eq "dir #680: a failing per-line sed makes the lib return 4" 4 "$pl680_lib_rc"
check_eq "dir #680: ...and the twin" 4 "$pl680_twin_rc"
pl680_r="$(new_repo)"; printf 'hello zebracorn\n' > "$pl680_r/sample.txt"; git -C "$pl680_r" add sample.txt
run_in "$pl680_r" env PATH="$pl_shim:$PATH" SECRET_SCAN_PERSONAL_FILE="$SANDBOX/pl680-onelit" "$scan" --staged
check_status "dir #680: scanner exits 2 when the per-line sed fails (not 'clean')" 2 "$STATUS"
check_contains "dir #680: ...and says it cannot read or parse the file" "$OUT" "cannot read or parse"
run env PATH="$pl_shim:$PATH" SECRET_SCAN_PERSONAL_FILE="$SANDBOX/pl680-onelit" bash "$pa" --no-history "$pl_ad"
check_contains "dir #680: the audit raises the coverage-ZERO GAP when the per-line sed fails" "$OUT" "coverage is ZERO"

# The same two behaviours under a REAL UTF-8 locale, where this host's sed decides (every test above runs
# in the ambient C locale — dir #250's blind spot). Each block runs only where the sed behaves that way:
# BSD sed errors on an invalid byte (the parse must then fail loud: status 4 / scanner exit 2), and a
# locale-aware sed that treats NBSP as whitespace trims it, as the pre-dir-#148 loop did (the parse must
# not stop doing so just because the parser moved into a function).
pl_u8="$(pick_utf8_locale)" || pl_u8=""
if [ -n "$pl_u8" ] && ! printf 'a\351\n' | LC_ALL="$pl_u8" sed 's/a//' >/dev/null 2>&1; then
  printf 'zebracorn  # caf\351\n' > "$SANDBOX/pl680-latin1"
  pl680_lib_rc=0; LC_ALL="$pl_u8" bash -c '. "$1"; personal_literals_parse "$2"' _ "$pl_lib" "$SANDBOX/pl680-latin1" >/dev/null 2>&1 || pl680_lib_rc=$?
  check_eq "dir #680: under a UTF-8 locale an invalid byte makes this host's sed fail -> the lib returns 4" 4 "$pl680_lib_rc"
  run_in "$pl680_r" env LC_ALL="$pl_u8" SECRET_SCAN_PERSONAL_FILE="$SANDBOX/pl680-latin1" "$scan" --staged
  check_status "dir #680: ...and the scanner exits 2 (not 'clean', not a bare tool error rc 1)" 2 "$STATUS"
  check_contains "dir #680: ...with its own message" "$OUT" "cannot read or parse"
else
  pass "dir #680: (no UTF-8 locale where this host's sed rejects an invalid byte — the BSD-sed case is not applicable here)"
fi
if [ -n "$pl_u8" ] && [ -z "$(printf '\302\240' | LC_ALL="$pl_u8" sed 's/[[:space:]][[:space:]]*$//')" ]; then
  printf 'zebracorn\302\240\n' > "$SANDBOX/pl680-nbsp"
  pl680_nbsp="$(LC_ALL="$pl_u8" bash -c '. "$1"; personal_literals_parse "$2"' _ "$pl_lib" "$SANDBOX/pl680-nbsp" 2>/dev/null)"
  check_eq "dir #680: a trailing NBSP is still trimmed where this host's UTF-8 sed counts it as whitespace" "zebracorn" "$pl680_nbsp"
else
  pass "dir #680: (this host's sed does not treat NBSP as whitespace — the trim case is not applicable here)"
fi

# unreadable (non-root only: chmod 000 is a no-op for root — CLAUDE.md Linux-leg trap 2). The status 2 /
# exit 2 contract holds for every platform's bash, so the whole block is guarded together.
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  pl_unread="$SANDBOX/pl680-unreadable"; printf 'zebracorn\n' > "$pl_unread"; chmod 000 "$pl_unread"
  pl_run_both "$pl_unread"
  check_eq "dir #680: lib returns 2 on an existing-but-unreadable file" 2 "$PL_LIB_RC"
  check_eq "dir #680: twin returns 2 on an existing-but-unreadable file" 2 "$PL_TWIN_RC"
  check_eq "dir #680: lib prints nothing on stdout" "" "$PL_LIB_OUT"
  check_eq "dir #680: lib prints nothing on stderr (the callers speak, in their own words)" "" "$PL_LIB_ERR"
  check_eq "dir #680: twin prints nothing on stderr" "" "$PL_TWIN_ERR"
  pl_scan_exit "hello zebracorn" "$pl_unread"
  check_status "dir #680: scanner exits 2 on an unreadable personal file" 2 "$STATUS"
  check_contains "dir #680: ...and says it cannot read or parse the file" "$OUT" "cannot read or parse"
  check_absent "dir #680: ...and never 'secret-scan: clean'" "$OUT" "secret-scan: clean"
  run env SECRET_SCAN_PERSONAL_FILE="$pl_unread" bash "$pa" --no-history "$pl_ad"
  check_status "dir #680: audit exits 1 (a GAP) on an unreadable personal file" 1 "$STATUS"
  check_contains "dir #680: ...the GAP says coverage is ZERO" "$OUT" "coverage is ZERO"
  check_absent "dir #680: ...and never echoes the file's content" "$OUT" "zebracorn"
  # the other readable-file path is untouched: the same repo with a READABLE file is the usual tree hit.
  chmod 600 "$pl_unread"
  run env SECRET_SCAN_PERSONAL_FILE="$pl_unread" bash "$pa" --no-history "$pl_ad"
  check_contains "dir #680: once readable, the same file is the usual tree hit" "$OUT" "$PL_TREE_LABEL"
fi

# =================================================================================================
# --- dir #682: on bash 3.2 (macOS /bin/bash), a bare `trap 'rm -rf "$SCRATCH"' EXIT` turned a top-level
# FATAL shell error (a `.` of a missing file, a `set -u` unbound variable) into exit 0 — the commit hook
# failed OPEN and --selftest reported success. `$?` is already 0 when the trap reads it for that failure
# class, so capturing it is not enough: the scanner uses a completion marker (_scan_done, set only on a
# legitimate exit-0 path). The probe: a COPY of the scanner with a fatal error injected right after its
# trap lines, run on a staged AWS-key-shaped string. A fail-open exits 0 (and a key-shaped string passes);
# a fixed scanner exits non-zero. alpine's bash 5 may not reproduce the original bug — the macOS leg is the
# binding one — but the assertion (non-zero, never 'clean') holds on every bash.
pl682_repo="$(new_repo)"
printf 'aws = %s\n' "$(key 'AKIA' "$(rep A 16)")" > "$pl682_repo/conf.txt"
git -C "$pl682_repo" add conf.txt
pl682_shells="bash"
[ -x /bin/bash ] && [ "$(command -v bash)" != /bin/bash ] && pl682_shells="bash /bin/bash"
# The fault goes in right AFTER the EXIT trap is armed (just before the INT trap line): a probe injected
# before the trap exists would pass vacuously. Both anchors are pinned exactly-once so a reorder fails here.
pin_exact "dir #682: the EXIT-trap line is unique in the scanner" "$scan" "trap _scan_exit EXIT" "EXIT trap not found exactly once"
pin_exact "dir #682: the INT-trap line (the injection anchor) is unique in the scanner" "$scan" "trap 'exit 130' INT" "anchor not found exactly once"
pl682_n=0
for pl682_inject in '. "$(dirname "$0")/pl682-missing-sibling.sh"' ': "$pl682_never_set_scalar"'; do
  pl682_n=$((pl682_n + 1))
  pl682_copy="$SANDBOX/pl682-scan-$pl682_n.sh"
  cp "$scan" "$pl682_copy"
  insert_before_line_containing "$pl682_copy" "trap 'exit 130' INT" "$pl682_inject"
  chmod +x "$pl682_copy"   # the helper rewrites through mv; --selftest executes the script directly
  pin_exact "dir #682: fatal-error probe $pl682_n injected" "$pl682_copy" "$pl682_inject" "injection missing"
  for pl682_sh in $pl682_shells; do
    run_in "$pl682_repo" "$pl682_sh" "$pl682_copy" --staged
    if [ "$STATUS" -ne 0 ]; then
      pass "dir #682: probe $pl682_n under $pl682_sh — a top-level fatal error exits non-zero (status $STATUS)"
    else
      fail "dir #682: probe $pl682_n under $pl682_sh — a top-level fatal error exits non-zero" "exit 0 (fail-open): $OUT"
    fi
    check_absent "dir #682: probe $pl682_n under $pl682_sh — never 'secret-scan: clean'" "$OUT" "secret-scan: clean"
    run_in "$pl682_repo" "$pl682_sh" "$pl682_copy" --selftest
    if [ "$STATUS" -ne 0 ]; then
      pass "dir #682: probe $pl682_n under $pl682_sh — --selftest does not report success after a fatal error"
    else
      fail "dir #682: probe $pl682_n under $pl682_sh — --selftest does not report success after a fatal error" "exit 0: $OUT"
    fi
  done
done
# The legitimate paths still exit 0 under the marker (an over-eager fix would make every clean run fail).
for pl682_sh in $pl682_shells; do
  pl682_clean="$(new_repo)"; printf 'nothing here\n' > "$pl682_clean/ok.txt"; git -C "$pl682_clean" add ok.txt
  run_in "$pl682_clean" "$pl682_sh" "$scan" --staged
  check_status "dir #682: a clean staged run still exits 0 under $pl682_sh" 0 "$STATUS"
  check_contains "dir #682: ...and says clean ($pl682_sh)" "$OUT" "secret-scan: clean"
  # the legit --selftest success path under the marker, for a shell the rest of the file does not use
  if [ "$pl682_sh" != bash ]; then
    run_in "$pl682_clean" "$pl682_sh" "$scan" --selftest
    check_status "dir #682: --selftest still exits 0 under $pl682_sh" 0 "$STATUS"
  fi
done
run_in "$pl682_repo" bash "$scan" --staged
check_status "dir #682: a real block still exits 1" 1 "$STATUS"
# The audit of every `trap … EXIT` in the VENDORED set (tools/secret-guard/): none may be a bare
# quoted-command trap — only a named handler (the completion-marker shape) is allowed.
pl682_bare="$(grep -rnE "^[[:space:]]*trap ['\"].*['\"][[:space:]]+EXIT" "$REPO_ROOT/tools/secret-guard/" || true)"
check_eq "dir #682: no bare quoted-command EXIT trap in the vendored secret-guard set" "" "$pl682_bare"

summary
