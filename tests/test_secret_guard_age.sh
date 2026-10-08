#!/usr/bin/env bash
# secret-guard — the age private-key pattern (dir #631 slice 2). The secrets recipe puts an age key on
# disk (`age-keygen -o`), and until this pattern the guard was blind to it: a file holding a full
# `AGE-SECRET-KEY-1…` line scanned clean. The pattern is length-anchored like its siblings (a bare prefix, or the
# pattern line in the scanner's own source, never trips it); the fixtures are built at RUNTIME — a full-length
# key literal in a committed file would block the very commit that adds it. SOPS ciphertext must keep
# passing: the recipe commits it.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

scan="$REPO_ROOT/tools/secret-guard/secret-scan.sh"
export SECRET_SCAN_PERSONAL_FILE=/dev/null

# scan_text TEXT — scans TEXT as a file; sets OUT/STATUS through run().
scan_text() {
  local d; d="$(mktemp -d "$SANDBOX/age.XXXXXX")"
  printf '%s\n' "$1" > "$d/f.txt"
  run "$scan" "$d/f.txt"
}

# --- A17: the pattern -------------------------------------------------------------------------------------
body58="$(rep Q 58)"
scan_text "$(key 'AGE-SECRET-KEY-1' "$body58")"
check_status "A17: AGE-SECRET-KEY-1 + 58 charset chars → exit 1" 1 "$STATUS"
check_contains "A17: … BLOCKED" "$OUT" "BLOCKED"

scan_text "$(key 'AGE-SECRET-KEY-1' "$(rep Q 57)")"
check_status "A17: 57 chars → exit 0 (length-anchored)" 0 "$STATUS"

scan_text "AGE-SECRET-KEY-1"
check_status "A17: the bare prefix → exit 0" 0 "$STATUS"

scan_text "$(key 'AGE-SECRET-KEY-1' "$(rep Q 20)")$(rep b 40)"
check_status "A17: a 20-char key body followed by out-of-charset chars → exit 0" 0 "$STATUS"

scan_text "$(key 'AGE-SECRET-KEY-PQ-1' "$body58")"
check_status "A17: the post-quantum variant (AGE-SECRET-KEY-PQ-1…) → exit 1" 1 "$STATUS"

scan_text "# private key follows
$(key 'AGE-SECRET-KEY-1' "$(printf '%s' "$body58" | tr 'Q' 'P')")"
check_status "A17: a key in a keys.txt-shaped file (comment + key line) → exit 1" 1 "$STATUS"

run "$scan" "$scan"
check_status "A17: the scanner's own source (it names the pattern) → exit 0" 0 "$STATUS"

# SOPS ciphertext, in the shape a real `sops` produced (checked live against sops 3.13.3): flat ENC[...] values,
# then a `sops:` block with the armoured age envelope, lastmodified, mac, version. Dummy base64 only.
cipher="DATABASE_URL: ENC[AES256_GCM,data:m/RONPBVzLOU29ibXqCj6FHg/Q==,iv:voFX0vqJwFHR8IbUKw+NQMBiRzh20d2w5DMycamKLZ0=,tag:j1oyxO9fQf3Qn1o2m0QqNw==,type:str]
API_TOKEN: ENC[AES256_GCM,data:uhsytlvYqKFKw6tgUw==,iv:qeucKCs76ACP5BimEL508zhXn6JbydmZFy/nYWLvn0M=,tag:Z3Rlc3R0YWd0ZXN0dGFnMTIzNA==,type:str]
sops:
    age:
        - recipient: age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBiOHVEUk52dmkyajFmcGIr
            S09qdnM5WmtQZzZrbURIVkdDNFY4RnQ4WjJnCmZMY2dhdVpCUGpxSi9KZk9kN0hp
            -----END AGE ENCRYPTED FILE-----
    lastmodified: \"2026-10-06T09:17:08Z\"
    mac: ENC[AES256_GCM,data:EyKRBtP50unGRVQMN556lseFhfpakSTvwjf0DOFMBQdFBdGhF2HMiGdlqlqYqq,iv:abc=,tag:def=,type:str]
    unencrypted_suffix: _unencrypted
    version: 3.13.3"
scan_text "$cipher"
check_status "A17: SOPS-shaped YAML ciphertext → exit 0 (the recipe commits it)" 0 "$STATUS"
check_contains "A17: … reported clean" "$OUT" "clean"

# --- A18: the tree itself holds no key literal ---------------------------------------------------------------------------
run_in "$REPO_ROOT" "$scan" --tracked
check_status "A18: --tracked → exit 0 (no key literal in the tracked tree)" 0 "$STATUS"

summary
