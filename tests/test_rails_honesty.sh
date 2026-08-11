#!/usr/bin/env bash
# test_rails_honesty.sh — pins the wording fixes of dir #99/#110/#111/#112/#119: places where a shipped
# rail described a guarantee it does not give, or a mechanism no shipped command carries. Grep-based,
# same idiom as test_conveyor_stages.sh — the failure mode these guard against is a later edit quietly
# restoring the overclaim, which nothing else would notice.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

checklist="$REPO_ROOT/docs/publishing-checklist.md"
going="$REPO_ROOT/docs/going-public.md"
go="$REPO_ROOT/commands/go.md"
wrap="$REPO_ROOT/commands/wrap.md"
polish="$REPO_ROOT/commands/polish.md"

# pin LABEL FILE PATTERN HINT — one fixed-string grep, reported under one label. Fixed-string on
# purpose: every pin here is literal prose, so nothing needs regex escaping to stay readable.
pin() {
  if grep -qF -- "$3" "$2"; then
    pass "$1"
  else
    fail "$1" "$4"
  fi
}

check_file "docs/publishing-checklist.md exists" "$checklist"
check_file "docs/going-public.md exists" "$going"
check_file "commands/go.md exists" "$go"
check_file "commands/wrap.md exists" "$wrap"
check_file "commands/polish.md exists" "$polish"

# --- dir #99: neither go-public doc may read as "green exit = no personal data" ------------------
# public-audit's personal-data heuristics are all WARN-tier and leave the exit code at 0, so both
# documents have to say what exit 0 does and does not prove, and hand the WARN read to the human.
pin "publishing-checklist: §0's [auto] tag is scoped to the exit code, not the whole item" \
  "$checklist" '**[auto]** for the exit code' \
  "expected the item to split [auto] (the exit code) from [you] (the WARNs)"
pin "publishing-checklist: §0 states a green exit is not proof of a clean tree" \
  "$checklist" 'A clean exit is not a clean tree' \
  "expected an explicit 'a clean exit is not a clean tree' disclaimer next to the WARN tier"
# One pin per SITE, keyed on a literal unique to that site. A single shared phrase would let any one
# site satisfy the guard for all three — and the site most worth holding is the scrub gate, the last
# check before a `--force` push.
pin "going-public: the flip step requires a WARN read, not just exit 0" \
  "$going" 'have read its WARNs' \
  "step 4 must name the WARN read alongside the exit code — exit 0 clears the GAP tier only"
pin "going-public: the §0 detect block hands the WARN list to the human" \
  "$going" 'then read the WARNs yourself' \
  "§0 must say the WARNs are yours to read, not something the exit code covered"
pin "going-public: the scrub gate before the force-push names the WARN read" \
  "$going" 'exit 0 AND its WARNs read' \
  "the third scrub gate must not read as satisfied by a green exit alone — a WARN-tier leak would ship"

# --- dir #110: no shipped rail may route work through a command Keel does not ship ---------------
# Class-level, not site-level (the dir #98 lesson): scan every tracked adopter-facing Markdown file —
# rails, templates, commands AND docs, since docs/reference.md is the command catalogue and
# getting-started.md is the onboarding path — for backticked slash-command references, and require a
# matching commands/<name>.md. CHANGELOG.md is excluded: it records what past releases said, including
# wording since corrected, so pinning it would forbid describing this very fix.
#
# Every citation style in the tree counts, not just the bare one: `/design`, the argument form
# `/design <topic>` (the dominant style — `/go <n>`, `/code-review <level>` — and so the likeliest shape
# for a dir #110 regression), bold-wrapped **`/design`**, and slash-joined `/go`/`/design` (FRAMEWORK.md
# writes pairs that way today). That is what the leading-delimiter class is for: it admits a space, an
# opening paren or quote, a `*` and a `/` before the backtick, while still refusing to match `X`/`Y`
# prose, where the backtick before the slash is a code span's CLOSING one.
#
# Know the edge of what it covers, so nobody over-trusts it: backticked refs only, in Markdown, in these
# four flat directories. A bare /design written without backticks, or one inside tools/ or a nested
# docs subdirectory, still gets through.
#
# Two allowlists, deliberately separate — they mean different things and must not blur into one:
#   harness-provided commands, each of whose call sites already handles its absence explicitly
#   (polish.md step 2's inline-cleanup fallback, step 5's agent fallback, step 5's do-not-substitute note)
harness_commands=" code-review simplify review "
#   not commands at all — a filesystem path, and prose about a name an adopter may already have
not_commands=" tmp setup "

# An ARRAY, not a space-joined string: a checkout path containing a space would split into fragments,
# grep would read none of the intended files, and an empty result is this check's own pass condition —
# a vacuous green over a live violation.
#
# The empty case needs its own sentinel, though: an empty array is NOT self-limiting. Expanding
# "${scan_files[@]}" empty aborts the file outright under lib.sh's `set -u` on bash 3.2 (what
# `env bash` resolves to on macOS), and on bash 4.4+ it leaves grep with no file operands, so it reads
# stdin — a hang from a terminal, a vacuous empty result in CI. `/dev/null` gives grep a real operand
# that matches nothing, while the check just above has already turned the file red.
scan_files=()
for f in "$REPO_ROOT"/*.md "$REPO_ROOT"/docs/*.md "$REPO_ROOT"/commands/*.md "$REPO_ROOT"/templates/*.md; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in CHANGELOG.md | BACKLOG.md) continue ;; esac
  scan_files+=("$f")
done

if [ "${#scan_files[@]}" -gt 0 ]; then
  pass "slash-command scan has files to scan"
else
  fail "slash-command scan has files to scan" \
    "found no Markdown under $REPO_ROOT — the glob list needs updating for the new layout"
  scan_files=(/dev/null)
fi

# grep exits 0 with matches, 1 with none, 2 on error. Only 2 is a broken scan; treat it as a failure
# rather than as "nothing to report", which is what silently swallowing it would look like.
raw_refs="$(grep -rhoE '(^|[[:space:]("*/])`/[a-z][a-z0-9-]+[` ]' "${scan_files[@]}")"
grep_status=$?   # captured off grep itself, not off a pipeline whose last stage would mask it
refs="$(printf '%s\n' "$raw_refs" | tr -d '`/ ("*' | sort -u)"

unshipped=""
for name in $refs; do
  case "$harness_commands$not_commands" in *" $name "*) continue ;; esac
  [ -f "$REPO_ROOT/commands/$name.md" ] || unshipped="$unshipped $name"
done

if [ "$grep_status" -gt 1 ]; then
  fail "rails, templates, commands and docs reference no slash command Keel does not ship" \
    "the scan itself failed (grep exit $grep_status) — the result below proves nothing"
elif [ -z "$unshipped" ]; then
  pass "rails, templates, commands and docs reference no slash command Keel does not ship"
else
  fail "rails, templates, commands and docs reference no slash command Keel does not ship" \
    "no commands/<name>.md for:$unshipped — ship it, or word it generically; allowlist it only if it is
        harness-provided AND every call site handles its absence (say which, in the comment above)"
fi

# --- dir #111: /wrap must actually carry the fold FRAMEWORK.md calls its serialization point -----
pin "wrap.md: step 2 names the BACKLOG.drafts fold" \
  "$wrap" 'BACKLOG.drafts' \
  "FRAMEWORK.md calls the session's own wrap the single serialization point; wrap.md must carry the step"
pin "wrap.md: claims the serialization point FRAMEWORK.md assigns it" \
  "$wrap" 'serialization point' \
  "expected wrap.md to name itself the drafts' serialization point"
pin "FRAMEWORK.md: points the serialization point at the command that implements it" \
  "$REPO_ROOT/FRAMEWORK.md" '`/wrap` step 2' \
  "expected the drafts convention to name '/wrap step 2'"
pin "FRAMEWORK.md: says Keel ships the fold side of the convention, not the producer" \
  "$REPO_ROOT/FRAMEWORK.md" 'Keel ships the fold side' \
  "the drafts are written by your own design/planning flow; no shipped command creates them — say so"

# --- dir #112: /go's test-first rail must disclose that nothing enforces it ----------------------
pin "go.md: says the test-first rail is self-reported, with no receipt or gate behind it" \
  "$go" 'no receipt, no gate' \
  "expected an explicit 'self-reported' + 'no receipt, no gate' disclosure, not a bare /polish analogy"
pin "go.md: gives the decision a home that outlives the ticket (the PR's test plan)" \
  "$go" 'tests: infeasible' \
  "expected the test decision written into the PR test plan and the IN FLIGHT marker, not only the chat"

# --- dir #119: a step-7 finding triggers the same convergence round as a step-5 one --------------
pin "polish.md: step 1's convergence branch names a step-7 self-check trigger" \
  "$polish" "step 7's self-check" \
  "expected the convergence-round question to cover step 7, not only step 5's review"
pin "polish.md: step 7 itself names the convergence round its finding triggers" \
  "$polish" 'you are in a convergence round' \
  "expected step 7 to state that a fix commit puts the run into step 1's convergence branch"

summary
