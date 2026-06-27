#!/usr/bin/env bash
# secret-guard — the only fires-by-itself mechanism. Cover block (every pattern), allow
# (clean + bare prefix), the three allowlist channels, and real git-hook integration.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

scan="$REPO_ROOT/tools/secret-guard/secret-scan.sh"

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
block_file "generic sk- key"         "k = $(key 'sk-' "$(rep A 32)")"
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

# --- integration: the real pre-commit hook blocks a staged key ----------------------------------
repo="$(new_repo)"
"$REPO_ROOT/tools/install-secret-guard.sh" "$repo" >/dev/null
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

summary
