#!/usr/bin/env bash
# test_go_command.sh — dir #636: pins the `/go` rework — GO11's word budget, GO12's legend-token
# contract with commands/backlog.md, the claim/escapes literal formats, the nine step names, the
# adopter-generic constraint, and one distinguishing needle per new rule clause (leg-1 F-1's class:
# a rule with no pin can be dropped silently, spec §8 A1(g)). Reads
# ${KEEL_GO_MD:-$REPO_ROOT/commands/go.md} and ${KEEL_BACKLOG_MD:-$REPO_ROOT/commands/backlog.md},
# so every case below is shown red first by re-invoking THIS file against a mutated SCRATCH copy via
# those two overrides — no tracked file is ever edited to prove a case.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

go_md="${KEEL_GO_MD:-$REPO_ROOT/commands/go.md}"
backlog_md="${KEEL_BACKLOG_MD:-$REPO_ROOT/commands/backlog.md}"

check_file "go.md target exists" "$go_md"
check_file "backlog.md target exists" "$backlog_md"

# --- (a) budget: GO11 -----------------------------------------------------------------------------
# Raising this constant is an operator decision (GO11) — never bump it here just to make a case fit.
GO_MD_WORD_BUDGET=965
word_count="$(wc -w < "$go_md" | tr -d ' ')"
if [ "$word_count" -le "$GO_MD_WORD_BUDGET" ]; then
  pass "(a) budget: go.md is <= $GO_MD_WORD_BUDGET words (got $word_count)"
else
  fail "(a) budget: go.md is <= $GO_MD_WORD_BUDGET words" "got $word_count words"
fi

# --- (b) contract: GO12 — DERIVED from commands/backlog.md's fenced token list, never a hard-coded
# copy (a copy would not turn red when the legend grows, leg-1 F-2) -------------------------------
fence_tokens="$(awk '
  /<!-- go-contract:begin -->/ { f = 1; next }
  /<!-- go-contract:end -->/   { f = 0 }
  f
' "$backlog_md")"

if [ -n "$fence_tokens" ]; then
  pass "(b) contract: go-contract fences present and non-empty in backlog.md"
else
  fail "(b) contract: go-contract fences present and non-empty in backlog.md" \
    "no <!-- go-contract:begin/end --> block, or an empty one, in $backlog_md"
fi

missing_tokens=()
while IFS= read -r fence_line; do
  # Skip anything that isn't a "token — meaning" line (GO12's declared format) — a future prose or
  # heading line dir #635 adds inside the same fences must not be misread as an unmatched token.
  case "$fence_line" in *" — "*) ;; *) continue ;; esac
  token="${fence_line%% — *}"
  [ -n "$token" ] || continue
  grep -qF -- "$token" "$go_md" || missing_tokens+=("$token")
done <<<"$fence_tokens"

if [ -z "$fence_tokens" ]; then
  fail "(b) contract: every backlog.md legend token appears in go.md" "fences empty — nothing to derive"
elif [ "${#missing_tokens[@]}" -eq 0 ]; then
  pass "(b) contract: every backlog.md legend token appears in go.md"
else
  fail "(b) contract: every backlog.md legend token appears in go.md" "missing: ${missing_tokens[*]}"
fi

# --- (c) claim format -------------------------------------------------------------------------------
pin "(c) claim format: the literal claim marker is byte-identical" "$go_md" \
  '⏳ IN FLIGHT (YYYY-MM-DD, branch <name>)' \
  "expected the literal '⏳ IN FLIGHT (YYYY-MM-DD, branch <name>)' in $go_md"

# --- (d) step names ----------------------------------------------------------------------------------
step_names=(resolve readiness read inflight-check worktree claim acceptance-tests escapes close)
for name in "${step_names[@]}"; do
  if grep -qE "\\*\\*[0-9]+\\. ${name}\\.\\*\\*" "$go_md"; then
    pass "(d) step names: '$name' appears as a step label"
  else
    fail "(d) step names: '$name' appears as a step label" "no '**N. $name.**' heading found in $go_md"
  fi
done

# --- (e) escapes format ------------------------------------------------------------------------------
pin "(e) escapes format: the literal escapes-line format is present" "$go_md" \
  'Escapes at implementation (YYYY-MM-DD, <branch>): <n>' \
  "expected the literal 'Escapes at implementation (YYYY-MM-DD, <branch>): <n>' in $go_md"

# --- (f) adopter-generic: the shipped command names neither the personal KB path nor its file -------
if grep -qF -- '.keel/kb' "$go_md" || grep -qF -- 'REVIEW_HISTORY' "$go_md"; then
  fail "(f) adopter-generic: go.md names neither '.keel/kb' nor 'REVIEW_HISTORY'" \
    "found a personal-KB reference in $go_md"
else
  pass "(f) adopter-generic: go.md names neither '.keel/kb' nor 'REVIEW_HISTORY'"
fi

# --- (g) one needle per NEW rule clause (leg-1 F-1's class) -------------------------------------------
# Two parallel arrays, not a delimited "rule|needle" string (a needle containing a literal "|" would
# silently truncate). If the implementer rewords a clause, the needle moves with it, in the same
# commit (spec A1(g)).
needle_rules=(
  "GO1 <root>"
  "GO1 phrase notice"
  "GO2 arm j scope / override"
  "GO3 TO VERIFY"
  "GO4 model check"
  "GO5 not-your-own"
  "GO5 stale heading"
  "GO6 spent branch"
  "GO10 carve-out"
)
# Each needle is distinguishing on its own line — not shared with an unrelated clause that would
# still satisfy the pin after the actual clause was dropped (a mutation-verified false-negative:
# "first reply" alone matched both GO1's and GO2's own text; "spent" alone matched go.md's
# pre-existing "a spent branch" AND the new "unless spent" exception).
needle_texts=(
  "git worktree list"
  "nothing to act on"
  "a stop in this step"
  "TO VERIFY"
  "Model rec"
  "not your own"
  "heading is stale"
  "qualifies unless spent"
  "direct-to-default"
)
i=0
while [ "$i" -lt "${#needle_rules[@]}" ]; do
  rule="${needle_rules[$i]}"
  needle="${needle_texts[$i]}"
  pin "(g) needle [$rule]: '$needle' present" "$go_md" "$needle" "missing needle for $rule in $go_md"
  i=$((i + 1))
done

# =====================================================================================================
# Mutation proof: each case above is shown red first — never on a tracked file (spec A1). Every helper
# here works on a SCRATCH copy under $SANDBOX and re-invokes THIS file with KEEL_GO_MD/KEEL_BACKLOG_MD
# pointed at it, so the positive checks above and their negative controls below share one definition
# of each case, never a second hard-coded copy.

# scratch_copy SRC NAME — copy SRC into a fresh scratch dir under $SANDBOX as NAME, print the copy's
# path. One helper for both go.md and backlog.md copies — they differed only in source/destination.
scratch_copy() {
  local src="$1" name="$2" dir
  dir="$(mktemp -d "$SANDBOX/go-cmd-copy.XXXXXX")"
  require_sandbox_path "$dir" scratch_copy
  cp "$src" "$dir/$name"
  printf '%s' "$dir/$name"
}

# delete_line_containing FILE SUBSTR — drop every line containing SUBSTR (literal).
delete_line_containing() {
  local file="$1" substr="$2"
  awk -v s="$substr" 'index($0, s) == 0' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# replace_in_line_containing FILE ANCHOR FIND REPL — on the line(s) containing ANCHOR literally,
# replace the first occurrence of FIND with REPL; every other line is untouched.
replace_in_line_containing() {
  local file="$1" anchor="$2" find="$3" repl="$4"
  awk -v a="$anchor" -v f="$find" -v r="$repl" '
    index($0, a) > 0 {
      i = index($0, f)
      if (i > 0) { $0 = substr($0, 1, i - 1) r substr($0, i + length(f)) }
    }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

append_line() { printf '%s\n' "$2" >> "$1"; }

# insert_before_line_containing FILE ANCHOR TEXT — insert one line just before the (single) line
# containing ANCHOR literally.
insert_before_line_containing() {
  local file="$1" anchor="$2" text="$3"
  awk -v a="$anchor" -v t="$text" '
    index($0, a) > 0 { print t }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# assert_case_turns_red LABEL FAIL_NEEDLE ENV_ASSIGN — re-invoke this file with ENV_ASSIGN
# (KEEL_GO_MD=<scratch> or KEEL_BACKLOG_MD=<scratch>) and assert the run exits nonzero AND reports
# FAIL_NEEDLE as a FAIL line — the check is not vacuously true (leg-1 F-1's class).
assert_case_turns_red() {
  local label="$1" fail_needle="$2" env_assign="$3"
  # KEEL_GO_TEST_SKIP_MUTATIONS=1 stops the child from running THIS section again — without it every
  # child re-runs its own full mutation section, each spawning its own children without bound.
  run env "$env_assign" KEEL_GO_TEST_SKIP_MUTATIONS=1 bash "$REPO_ROOT/tests/test_go_command.sh"
  check_ne "$label: mutated copy makes the suite exit nonzero" "$STATUS" "0"
  check_contains "$label: the mutated case itself is reported FAIL" "$OUT" "FAIL  $fail_needle"
}

if [ -n "${KEEL_GO_TEST_SKIP_MUTATIONS:-}" ]; then
  summary
  exit $?
fi

# (a) budget — append enough words to a go.md copy to cross the budget on every wc(1) this suite runs
# under. Found live on the alpine-busybox CI leg (dir #636): busybox's wc -w counts this file's
# non-ASCII characters (—, →, ⏳, 📐, …) differently from GNU/BSD wc, undercounting the real file by
# ~45 words there (919 vs macOS's 964) — a fixed +10-word nudge crossed 965 on macOS but not on
# busybox. 80 padding words clears that gap with margin on any wc's word-boundary handling.
a_copy="$(scratch_copy "$go_md" go.md)"
append_line "$a_copy" "$(printf 'filler %.0s' {1..80})"
assert_case_turns_red "(a) budget mutation" \
  "(a) budget: go.md is <= $GO_MD_WORD_BUDGET words" "KEEL_GO_MD=$a_copy"

# (b) contract — two independent negative controls: delete the R2 bullet from a go.md copy, and add
# an unhandled token inside the fences of a backlog.md copy.
b1_copy="$(scratch_copy "$go_md" go.md)"
delete_line_containing "$b1_copy" "- R2 → stop:"
assert_case_turns_red "(b) contract mutation: R2 bullet removed from go.md" \
  "(b) contract: every backlog.md legend token appears in go.md" "KEEL_GO_MD=$b1_copy"

b2_copy="$(scratch_copy "$backlog_md" backlog.md)"
insert_before_line_containing "$b2_copy" "<!-- go-contract:end -->" "R5 — a token go.md does not yet handle"
assert_case_turns_red "(b) contract mutation: unhandled token added to backlog.md fence" \
  "(b) contract: every backlog.md legend token appears in go.md" "KEEL_BACKLOG_MD=$b2_copy"

# (c) claim format — `branch` -> `br`, scoped to the claim-marker line only.
c_copy="$(scratch_copy "$go_md" go.md)"
replace_in_line_containing "$c_copy" "⏳ IN FLIGHT (YYYY-MM-DD," "branch" "br"
assert_case_turns_red "(c) claim format mutation" \
  "(c) claim format: the literal claim marker is byte-identical" "KEEL_GO_MD=$c_copy"

# (d) step names — rename `inflight-check`, scoped to its own step-label line.
d_copy="$(scratch_copy "$go_md" go.md)"
replace_in_line_containing "$d_copy" "4. inflight-check." "inflight-check" "in-flight-check"
assert_case_turns_red "(d) step names mutation" \
  "(d) step names: 'inflight-check' appears as a step label" "KEEL_GO_MD=$d_copy"

# (e) escapes format — drop the `(YYYY-MM-DD, <branch>)` parenthetical from the escapes literal.
e_copy="$(scratch_copy "$go_md" go.md)"
replace_in_line_containing "$e_copy" "Escapes at implementation" "(YYYY-MM-DD, <branch>)" ""
assert_case_turns_red "(e) escapes format mutation" \
  "(e) escapes format: the literal escapes-line format is present" "KEEL_GO_MD=$e_copy"

# (f) adopter-generic — add a personal-KB path.
f_copy="$(scratch_copy "$go_md" go.md)"
append_line "$f_copy" "See also ~/.keel/kb for personal notes."
assert_case_turns_red "(f) adopter-generic mutation" \
  "(f) adopter-generic: go.md names neither '.keel/kb' nor 'REVIEW_HISTORY'" "KEEL_GO_MD=$f_copy"

# (g) needle — drop GO4's sentence (the one carrying the `Model rec` needle).
g_copy="$(scratch_copy "$go_md" go.md)"
delete_line_containing "$g_copy" "Model rec"
assert_case_turns_red "(g) needle mutation: GO4 sentence removed" \
  "(g) needle [GO4 model check]: 'Model rec' present" "KEEL_GO_MD=$g_copy"

summary
