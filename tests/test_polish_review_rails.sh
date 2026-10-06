#!/usr/bin/env bash
# test_polish_review_rails.sh — dir #375: two live incidents (v0.8.2 wave 3, and PR #349's own round-2
# review) show a review subagent spawned with a paraphrased "read-only" instruction can still rationalize
# a mutating git command as a "restore" rather than an edit. commands/polish.md's own dir #70 fallback
# subagent — the one ad-hoc review-subagent spawn point this repo's own tracked commands control (the
# built-in `/code-review` skill's internal fan-out is not part of this tree) — used to carry a bespoke,
# weaker paraphrase instead of docs/delegation.md's canonical Worker rails block. This pins that the
# fallback now inlines the SAME block, byte-identical modulo the list-item indentation markdown needs.
# Uses tests/lib.sh's extract_rails_block/check_block_equal (dir #375 promoted both there once this
# became the third file needing the same idiom test_drydock_doc.sh and test_delta_audit_doc.sh each
# already had independently).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

delegation="$REPO_ROOT/docs/delegation.md"
polish="$REPO_ROOT/commands/polish.md"

check_file "docs/delegation.md exists" "$delegation"
check_file "commands/polish.md exists" "$polish"

# strip_indent=1 on both sides: polish.md's copy sits inside a nested list item and needs its leading
# whitespace normalized before comparison; it's a no-op on delegation.md's already-flush-left canonical
# text, so one call shape covers both.
# dir #670: the Worker rails block now appears in two places — step 5's K2 review subagent prompt, in the
# core (commands/polish.md), and the dir #70 fallback's, in the guide (commands/polish-guide.md, moved
# verbatim by K1). Each must equal the canonical text exactly once.
guide="$REPO_ROOT/commands/polish-guide.md"
check_file "commands/polish-guide.md exists" "$guide"
canonical_rails="$(extract_rails_block "$delegation" 1)"
polish_rails="$(extract_rails_block "$polish" 1)"
guide_rails="$(extract_rails_block "$guide" 1)"
check_block_equal "commands/polish.md's K2 review-subagent rails copy is byte-identical (mod indent) to docs/delegation.md's canonical text" \
  "$polish_rails" "$canonical_rails"
check_block_equal "commands/polish-guide.md's dir #70 fallback rails copy is byte-identical (mod indent) to docs/delegation.md's canonical text" \
  "$guide_rails" "$canonical_rails"

# The byte-equality check above only catches ASYMMETRIC drift (one side losing the line while the
# other keeps it) — reproduced live: stripping the dirty-tree bullet from BOTH delegation.md and
# polish.md at once leaves the two sides equal, so check_block_equal alone stays green (found by this
# ticket's own /code-review medium pass, angle B, which mutated a scratch clone to confirm). An
# independent pin on the canonical source closes the gap: if the bullet vanishes from delegation.md —
# alone or together with every copy — this fails regardless of what any copy still says.
pin "docs/delegation.md's rails block states the dirty-tree discriminator" \
  "$delegation" 'is normal — it'"'"'s the parent' \
  "expected the canonical Worker rails block to say a dirty tree is normal work in progress, not corruption (dir #375)"

# dir #505 (a): the retest caution. A worker who commits or edits the checkout while one of its own
# background suite runs is still alive trips dir #318's self-corruption canary — a false positive that
# costs a full rerun (hit twice in 0.10.1, ten trips in 0.12.0). /polish's test and retest steps are
# where a worker starts those runs, so the caution lives there. Single-line needles (pin() is line-mode).
pin "commands/polish-guide.md's retest step warns against committing or editing while a background suite run is alive" \
  "$guide" 'Never commit, amend or edit while a background suite run is alive' \
  "expected the retest caution naming commit, amend and edit (dir #505)"
pin "commands/polish-guide.md's retest caution names the canary it would trip" \
  "$guide" 'self-corruption canary' \
  "expected the caution to say what trips (dir #505)"

# --- dir #413 slice 2 (A7): the flip — every spawn site but K2's names keel-polish-reviewer ----------------
# Exactly ONE `subagent_type: "general-purpose"` may remain across the two files: dir #670's K2 default-review
# spawn, which dir #413 deliberately does not floor (F4), identified by the needle `step 5's review subagent`
# on that line or the line before. Every OTHER line that names general-purpose at all must say NOT (a rewritten
# sentence saying the type is NOT trusted). Counts are over the raw files, line by line, exactly as the spec's
# `grep -n` reads them.
needle="step 5's review subagent"
n_gp="$(cat "$polish" "$guide" | grep -cF 'subagent_type: "general-purpose"')"
check_eq "A7: exactly ONE subagent_type: \"general-purpose\" remains across polish.md + polish-guide.md (K2's)" 1 "$n_gp"
for f in "$polish" "$guide"; do
  awk -v n="$needle" '
    index($0, "subagent_type: \"general-purpose\"") && !(index($0, n) || index(prev, n)) { bad++ }
    { prev = $0 }
    END { print bad + 0 }' "$f" > "$SANDBOX/a7-unexempt-$(basename "$f")"
done
check_eq "A7: the one remaining general-purpose spawn line is K2's (needle on it or the line before) — core" 0 "$(cat "$SANDBOX/a7-unexempt-polish.md")"
check_eq "A7: ...and none in the guide is un-exempted" 0 "$(cat "$SANDBOX/a7-unexempt-polish-guide.md")"
# every other general-purpose line says NOT
bare_gp="$(for f in "$polish" "$guide"; do
  awk -v n="$needle" '
    /general-purpose/ {
      if (index($0, "subagent_type: \"general-purpose\"") && (index($0, n) || index(prev, n))) { prev = $0; next }
      if ($0 !~ /NOT/) print FILENAME ":" NR ": " $0
    }
    { prev = $0 }' "$f"
done)"
check_eq "A7: every other line naming general-purpose also says NOT (none names it as the traced type)" "" "$bare_gp"
check_eq "A7: both spawn sites name keel-polish-reviewer (two subagent_type lines)" 2 \
  "$(cat "$polish" "$guide" | grep -cF 'subagent_type: "keel-polish-reviewer"')"
for nd in 'OMITTED (no hunks supplied):' 'CONTINUES with the next file' "deleted files' diffs first" \
          'deleted — not reviewable' 'no diff is ever cut inside a file' 'longer than any backtick run' \
          'done-criterion' 'last-reviewed' 'not found'; do
  pin "A7: polish-guide.md carries B3/B4's needle: $nd" "$guide" "$nd" "expected B3/B4's wording to carry this exact string (dir #413 A7)"
done
pin "A7: B4 — never retry as general-purpose" "$guide" 'Never retry as `general-purpose`' \
  "expected B4's refusal to fall back to the unfloored type (F2)"
pin "A7: B3 — the 65536-byte cap" "$guide" '65536 bytes' "expected B3's diff cap"
pin "A7: B4 names the remedy install.sh" "$guide" 're-run `install.sh`' "expected B4 to name install.sh as the remedy"

summary
