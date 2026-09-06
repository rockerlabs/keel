#!/usr/bin/env bash
# test_polish_review_rails.sh — dir #375: two live incidents (v0.8.2 wave 3, and PR #349's own round-2
# review) show a review subagent spawned with a paraphrased "read-only" instruction can still rationalize
# a mutating git command as a "restore" rather than an edit. commands/polish.md's own dir #70 fallback
# subagent — the one ad-hoc review-subagent spawn point this repo's own tracked commands control (the
# built-in `/code-review` skill's internal fan-out is not part of this tree) — used to carry a bespoke,
# weaker paraphrase instead of docs/delegation.md's canonical Worker rails block. This pins that the
# fallback now inlines the SAME block, byte-identical modulo the list-item indentation markdown needs,
# same idiom as test_drydock_doc.sh's check_block_equal but tolerant of a leading-whitespace difference
# since polish.md's copy has to sit inside a nested list item to render correctly.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

delegation="$REPO_ROOT/docs/delegation.md"
polish="$REPO_ROOT/commands/polish.md"

check_file "docs/delegation.md exists" "$delegation"
check_file "commands/polish.md exists" "$polish"

# Block-extract, stripping leading whitespace per line so a copy indented to sit inside polish.md's
# nested list item still compares byte-identical in content — see test_drydock_doc.sh's own
# check_block_equal for the non-indented sibling of this idiom (dir #209: presence isn't agreement).
extract_rails() {
  awk '/^[[:space:]]*- You are read-only:/,/^[[:space:]]*- DELEGATION RUN:/' "$1" | sed 's/^[[:space:]]*//'
}

check_block_equal() {
  local label="$1" a="$2" b="$3"
  if [ -n "$a" ] && [ "$a" = "$b" ]; then
    pass "$label"
  else
    fail "$label" "block-extracted text differs or is empty — diff:
$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"))"
  fi
}

canonical_rails="$(extract_rails "$delegation")"
polish_rails="$(extract_rails "$polish")"
check_block_equal "commands/polish.md's dir #70 fallback rails block is byte-identical (mod indent) to docs/delegation.md's canonical text" \
  "$polish_rails" "$canonical_rails"

# The dirty-tree discriminator is the one line dir #375 actually needed — pin its presence directly too,
# not only via the block-equality check above, so a future edit that keeps the block "close enough" but
# drops this exact line fails loudly on ITS OWN, named check rather than a generic block diff.
pin "docs/delegation.md's rails block states the dirty-tree discriminator" \
  "$delegation" 'is normal — it'"'"'s the parent' \
  "expected the Worker rails block to say a dirty tree is normal work in progress, not corruption (dir #375)"
pin "commands/polish.md's fallback subagent inherits the dirty-tree discriminator" \
  "$polish" 'is normal — it'"'"'s the parent' \
  "expected the dir #70 fallback's inlined rails block to carry the same discriminator delegation.md ships"

# Every other verbatim-copy surface (drydock's worker/verifier templates, delta-audit.md's session
# prompts) must carry the same line too — test_drydock_doc.sh/test_delta_audit_doc.sh already
# byte-diff these files' rails blocks against docs/delegation.md's canonical text, so once the canonical
# text carries the line, those existing checks fail unless every copy was updated in lockstep. This test
# only adds the one NEW surface (polish.md) those files don't cover.

summary
