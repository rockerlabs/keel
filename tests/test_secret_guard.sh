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
  for sync_case in no-store with-store legacy-marker role3-only; do
    case "$sync_case" in
      with-store) mkdir -p "$sync_store_root/$(cd "$sync_repo" && pwd -P | tr '/' '-')" ;;
      legacy-marker) rm -rf "$sync_store_root"; rm -rf "$sync_repo/.keel"; mkdir -p "$sync_repo/.keel"
        printf '/.keel/impact-events.log\n' >> "$sync_repo/.gitignore" ;;
      # dir #251 review: a bare `.keel/` holding ONLY a role-3 file (never gitignored — that line is
      # the genuine-marker signal) must NOT resolve as legacy in either implementation.
      role3-only) rm -rf "$sync_repo/.keel"; mkdir -p "$sync_repo/.keel"
        printf 'H-DEP-FLOATING\n' > "$sync_repo/.keel/doctor-accept" ;;
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

summary
