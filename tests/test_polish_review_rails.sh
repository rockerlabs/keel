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
. "$(dirname "$0")/lib.sh"

delegation="$REPO_ROOT/docs/delegation.md"
polish="$REPO_ROOT/commands/polish.md"

check_file "docs/delegation.md exists" "$delegation"
check_file "commands/polish.md exists" "$polish"

# strip_indent=1 on both sides: polish.md's copy sits inside a nested list item and needs its leading
# whitespace normalized before comparison; it's a no-op on delegation.md's already-flush-left canonical
# text, so one call shape covers both. The byte-identity check below is sufficient on its own to catch a
# dropped or reworded dirty-tree discriminator line — no separate substring pin needed alongside it.
canonical_rails="$(extract_rails_block "$delegation" 1)"
polish_rails="$(extract_rails_block "$polish" 1)"
check_block_equal "commands/polish.md's dir #70 fallback rails block is byte-identical (mod indent) to docs/delegation.md's canonical text" \
  "$polish_rails" "$canonical_rails"

summary
