#!/usr/bin/env bash
# docs/secrets-in-the-working-tree.md — the SOPS + age recipe (dir #631 slice 1). Guards the shape of the
# adopter-facing doc: no fenced example hands the agent plaintext (decrypt to stdout, an exec-env/exec-file
# whose command prints, a full age private-key literal, indented sops/age code), the `## Limits` section
# carries its seven labelled items, migration and rotation sections exist, SECURITY.md links the recipe and
# CHANGELOG cites the ticket. The shape checker is proven on good and bad samples first — a
# checker that flags nothing would pass the doc for the wrong reason.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

doc="$REPO_ROOT/docs/secrets-in-the-working-tree.md"

# fenced_text FILE — only the lines between ``` or ~~~ fences (the fence lines themselves dropped).
fenced_text() {
  awk '
    /^ {0,3}(```|~~~)/ { m = ($0 ~ /^ {0,3}```/) ? "`" : "~"
                         if (!infence) { infence = 1; fence = m; next }
                         if (m == fence) { infence = 0; next } }
    infence { print }
  ' "$1"
}
# The three plaintext-printing shapes (B7): (a) a sops decrypt, bounded at the first quote so a -d inside
# the child command is not a decrypt; (b) an exec-env/exec-file whose command prints; (c) an age key.
RE_A="sops[^|;&'\"]*[[:space:]](-d|--decrypt|decrypt)([[:space:]]|\$)"
RE_B1="exec-(env|file)[^|;&]*[[:space:]'\"(/](cat|printenv|echo|printf|env)([[:space:]'\";)]|\$)"
RE_B2="exec-env[[:space:]]+[^[:space:]]+[[:space:]]+['\"]?(/[^[:space:]'\"]*/)?env([[:space:]'\"]|\$)"
RE_C='AGE-SECRET-KEY-(PQ-)?1[QPZRY9X8GF2TVDW0S3JN54KHCE6MUA7L]{58,}'
RE_IND='^ {4,}(sops |age)'
# flags TEXT — true when any plaintext-printing shape is present in TEXT.
flags() {
  grep -Eq -e "$RE_A" -e "$RE_B1" -e "$RE_B2" -e "$RE_C" -e "$RE_IND" <<< "$1"
}

# --- the checker, on samples (A12's proof) -----------------------------------------------------------
bad=(
  'sops -d secrets.enc.yaml'
  'sops --input-type yaml -d secrets.enc.yaml'
  'sops decrypt secrets.enc.yaml'
  "sops exec-file secrets.enc.yaml 'cat {}'"
  'sops exec-env secrets.enc.yaml env'
  "sops exec-env secrets.enc.yaml '/usr/bin/env'"
  "sops exec-env secrets.enc.yaml 'echo secret: \$X'"
  "sops exec-env secrets.enc.yaml 'printenv X'"
  "sops exec-env secrets.enc.yaml 'env -i FOO=1 ./run'"
  "    sops edit secrets.enc.yaml"
)
good=(
  "sops exec-env secrets.enc.yaml './run-my-app'"
  "sops exec-env secrets.enc.yaml './deploy -d prod'"
  "sops exec-file --output-type dotenv secrets.enc.yaml './import --file {}'"
  'sops encrypt --in-place secrets.enc.yaml'
)
for s in "${bad[@]}"; do
  if flags "$s"; then pass "checker flags: $s"; else fail "checker flags: $s" "a plaintext-printing shape went unflagged"; fi
done
for s in "${good[@]}"; do
  if flags "$s"; then fail "checker passes: $s" "a safe line was flagged"; else pass "checker passes: $s"; fi
done
key="AGE-SECRET-KEY-1$(printf 'Q%.0s' $(seq 1 58))"       # built at runtime — a literal would block this very commit
if flags "$key"; then pass "checker flags a full-length age key literal"; else fail "checker flags a full-length age key literal" "unflagged"; fi
if flags "${key%Q}"; then fail "checker passes a 57-char near-key" "flagged"; else pass "checker passes a 57-char near-key"; fi
tilde="$SANDBOX/tilde-fence.md"
printf '%s\n' 'prose' '~~~bash' 'sops -d secrets.enc.yaml' '~~~' 'after' > "$tilde"
if flags "$(fenced_text "$tilde")"; then pass "a ~~~-fenced decrypt is flagged"; else fail "a ~~~-fenced decrypt is flagged" "fence extraction missed it"; fi
printf '%s\n' 'sops -d secrets.enc.yaml in prose is not code' '```bash' 'ls' '```' > "$tilde"
if flags "$(fenced_text "$tilde")"; then fail "prose outside a fence is ignored" "flagged"; else pass "prose outside a fence is ignored"; fi

# --- A12: the doc ---------------------------------------------------------------------------------------
check_file "A12: the recipe doc exists" "$doc"
if [ -f "$doc" ]; then
  code="$(fenced_text "$doc")"
  [ -n "$code" ] && pass "A12: the doc has fenced command blocks" || fail "A12: the doc has fenced command blocks" "no fenced lines found"
  if flags "$code"; then
    fail "A12: no fenced block prints plaintext" "$(printf '%s\n' "$code" | grep -En -e "$RE_A" -e "$RE_B1" -e "$RE_B2" -e "$RE_C" -e "$RE_IND" | head -n3)"
  else pass "A12: no fenced block prints plaintext, holds a key, or is indented sops/age code"; fi
  if grep -Eq "$RE_IND" "$doc"; then fail "A12: no indented sops/age code anywhere in the doc" "$(grep -En "$RE_IND" "$doc" | head -n2)"
  else pass "A12: no indented sops/age code anywhere in the doc"; fi

  # --- A13: the Limits section and the two other required sections ----------------------------------------
  limits="$(awk '/^## /{ on = ($0 == "## Limits") } on' "$doc" | tr '\n' ' ')"
  [ -n "$limits" ] && pass "A13: a ## Limits section" || fail "A13: a ## Limits section" "heading absent"
  for label in 'Honest threat model.' 'Key on disk.' 'Other channels.' 'Transcripts.' 'Names, not content.' \
               'Read deny covers Read only.' 'Scanner and ciphertext.'; do
    case "$limits" in *"**$label**"*) pass "A13: Limits label — $label" ;; *) fail "A13: Limits label — $label" "missing" ;; esac
  done
  case "$limits" in *"honestly erring"*) pass "A13: the threat model says 'honestly erring'" ;; *) fail "A13: the threat model says 'honestly erring'" "missing" ;; esac
  grep -q '^## Migrating an existing env file$' "$doc" && pass "A13: ## Migrating an existing env file" || fail "A13: ## Migrating an existing env file" "heading absent"
  grep -q '^## Rotation$' "$doc" && pass "A13: ## Rotation" || fail "A13: ## Rotation" "heading absent"
  for w in exec-env exec-file; do grep -q "$w" "$doc" && pass "A13: names $w" || fail "A13: names $w" "absent"; done
  # adopter-facing text carries no Keel-internal ticket id
  if grep -Eq 'dir #[0-9]+' "$doc"; then fail "A13: no internal ticket ids in the doc" "$(grep -En 'dir #[0-9]+' "$doc" | head -n2)"
  else pass "A13: no internal ticket ids in the doc"; fi
fi

# --- A14: SECURITY.md -----------------------------------------------------------------------------------------
sec="$REPO_ROOT/SECURITY.md"
grep -qx '## Secrets in the working tree' "$sec" && pass "A14: SECURITY.md has the section heading" || fail "A14: SECURITY.md has the section heading" "absent"
sec_body="$(awk '/^## /{ on = ($0 == "## Secrets in the working tree") } on' "$sec")"
case "$sec_body" in *secrets-in-the-working-tree.md*) pass "A14: the section links the recipe" ;; *) fail "A14: the section links the recipe" "no link" ;; esac

# --- A15: CHANGELOG cite -------------------------------------------------------------------------------------------
# The whole file PLUS the changelog.d/ fragments (dir #744), never the live [Unreleased] section and never
# one fragment: the release cut empties that section and deletes the fragments, and the cite then lives in
# the dated section below it.
clog="$(sed 's/`[^`]*`//g' <<< "$(cat "$REPO_ROOT/CHANGELOG.md"; bash "$REPO_ROOT/tools/self/changelog-fragments.sh" --repo "$REPO_ROOT")")"
for n in 631 379; do
  case "$clog" in *"dir #$n"*) pass "A15: CHANGELOG cites dir #$n, not backtick-wrapped" ;; *) fail "A15: CHANGELOG cites dir #$n, not backtick-wrapped" "absent (after dropping backtick spans)" ;; esac
done

summary
