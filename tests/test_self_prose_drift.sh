#!/usr/bin/env bash
# tools/self/prose-drift.sh — signal 1 (advisory anomalous-line-length-in-a-wrapped-block WARN) and
# signal 2 (hard dead-relative-link GAP) against synthetic sandbox fixtures, plus --help/bad-args
# and a smoke test on the real checkout.
#
# Every "does NOT fire" case below is paired with a mutation of the SAME content that DOES fire
# (dir #110's lesson: fired != catches) — a negative test that never has a positive counterpart could
# just as easily be passing because the checker is blind to that content entirely, not because the
# exemption is working.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

pd="$REPO_ROOT/tools/self/prose-drift.sh"

# --- --help / bad args ---------------------------------------------------------------------------
run "$pd" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$pd" --bogus
check_status "unknown flag -> exit 2" 2 "$STATUS"
run "$pd" /no/such/dir
check_status "missing REPO_DIR -> exit 2" 2 "$STATUS"

# --- smoke test: the real keel checkout has no dead relative link --------------------------------
# Deliberately not asserting on signal 1's WARN count here — the real tree's prose changes session to
# session, and a WARN never fails this script anyway (only signal 2 does).
run "$pd" "$REPO_ROOT" --quiet
check_status "the real keel checkout has no dead relative link (no GAP)" 0 "$STATUS"

# --- fixture builder: a throwaway repo with the given files, committed -----------------------------
mk_repo_with() {   # mk_repo_with REL_PATH CONTENT [REL_PATH CONTENT ...]
  local d; d="$(new_repo)"
  while [ "$#" -gt 0 ]; do
    local rel="$1" content="$2"; shift 2
    mkdir -p "$d/$(dirname "$rel")"
    printf '%s' "$content" > "$d/$rel"
  done
  ( cd "$d" && git add -A && git commit -q -m fixture )
  printf '%s' "$d"
}

a100="$(rep a 100)"
b100="$(rep b 100)"
c140="$(rep c 140)"

# --- signal 1: a plain wrapped paragraph, one line running well past its neighbors -> WARN --------
d="$(mk_repo_with doc.md "# doc

$a100
$b100
$c140
")"
run "$pd" "$d" --quiet
check_status "anomalous line in a wrapped paragraph doesn't fail the script -> exit 0 (advisory)" 0 "$STATUS"
check_contains "flags the anomalous line" "$OUT" "doc.md:5"

# --- signal 1: a 2-line block never fires (MIN_BLOCK=3 guard) -------------------------------------
d="$(mk_repo_with doc.md "# doc

$a100
$c140
")"
run "$pd" "$d" --quiet
check_absent "a 2-line block is never flagged, however long the 2nd line runs" "$OUT" "WARN"

# --- signal 1: a legitimate table row does NOT fire, however long -> and the SAME content as plain
# prose in a wrapped block DOES (dir #110 mutation pairing) --------------------------------------
tablerow="| $c140 | short |"
d="$(mk_repo_with doc.md "# doc

$tablerow
| short | short |
")"
run "$pd" "$d" --quiet
check_absent "a long table row is not flagged" "$OUT" "WARN"

d="$(mk_repo_with doc.md "# doc

$a100
$b100
$c140
")"
run "$pd" "$d" --quiet
check_contains "the SAME long content, as plain prose (not a table row), IS flagged" "$OUT" "doc.md:5"

# --- signal 1: a fenced code block does NOT fire -> the SAME content unfenced DOES ----------------
d="$(mk_repo_with doc.md "# doc

\`\`\`
$a100
$b100
$c140
\`\`\`
")"
run "$pd" "$d" --quiet
check_absent "a long line inside a fenced code block is not flagged" "$OUT" "WARN"

d="$(mk_repo_with doc.md "# doc

$a100
$b100
$c140
")"
run "$pd" "$d" --quiet
check_contains "the SAME content, unfenced, IS flagged" "$OUT" "doc.md:5"

# --- signal 1: YAML frontmatter does NOT fire -> the SAME content as a body line DOES -------------
d="$(mk_repo_with doc.md "---
description: $c140
title: x
---
# doc
")"
run "$pd" "$d" --quiet
check_absent "a long frontmatter value is not flagged" "$OUT" "WARN"

d="$(mk_repo_with doc.md "# doc

$a100
$b100
description: $c140
")"
run "$pd" "$d" --quiet
check_contains "the SAME content, as a body line, IS flagged" "$OUT" "doc.md:5"

# --- signal 1: independent top-level bullets are never cross-compared ------------------------------
d="$(mk_repo_with doc.md "# doc

- $(rep a 30)
- $c140
- $(rep b 30)
")"
run "$pd" "$d" --quiet
check_absent "three independent one-line bullets are never flagged against each other" "$OUT" "WARN"

# --- signal 1: a wrapped bullet's OWN continuation lines DO compare against each other -------------
d="$(mk_repo_with doc.md "# doc

- $a100
  $b100
  $c140
")"
run "$pd" "$d" --quiet
check_contains "a wrapped bullet's continuation anomaly IS flagged" "$OUT" "doc.md:5"

# --- signal 1: a standalone link/image line and a URL-carrying line do NOT fire --------------------
d="$(mk_repo_with doc.md "# doc

[$c140](https://example.invalid/x)
")"
run "$pd" "$d" --quiet
check_absent "a standalone link line is not flagged" "$OUT" "WARN"

d="$(mk_repo_with doc.md "# doc

$a100
$b100
https://example.invalid/$c140
")"
run "$pd" "$d" --quiet
check_absent "a line carrying a literal URL is not flagged even if it runs long" "$OUT" "WARN"

# --- signal 1: is_linkline only excludes actual link/image syntax, not any '[...' line -------------
# A genuinely anomalous line that happens to start with '[' but is NOT a markdown link (a footnote,
# a bracketed aside) must still be flagged — a real link line pairs with the "not flagged" case above.
d="$(mk_repo_with doc.md "# doc

$a100
$b100
[K] not a link, just a bracketed aside that runs on for a very long stretch of unwrapped prose well past its neighbors here
")"
run "$pd" "$d" --quiet
check_contains "a non-link bracketed line IS flagged when genuinely anomalous" "$OUT" "doc.md:5"

# --- signal 1, sh comments: shebang excluded, comment block anomaly IS flagged ---------------------
# fake_sh built via key() rather than a bare literal "tools/" + "t.sh" — self/doctor.sh's own check 2
# scans tests/*.sh for exactly such a joined substring, and this file's source must never hold it
# intact (the same idiom test_self_doctor.sh already documents for its own fake fixture paths).
fake_sh="$(key tools/t .sh)"
d="$(mk_repo_with "$fake_sh" "#!/usr/bin/env bash
# $a100
# $b100
# $c140
echo done
")"
run "$pd" "$d" --quiet
check_contains "an anomalous sh comment line is flagged" "$OUT" "t.sh:4"
check_absent "the shebang line is never itself flagged" "$OUT" "t.sh:1"

# --- signal 1, sh_files: an extensionless shebang-only script IS scanned, not just *.sh ------------
# sh_files is derived from shellcheck-targets.sh (dir #169 fix), not a bare `*.sh` glob — a bare glob
# would silently skip this fixture entirely (real case: tools/secret-guard/pre-commit, pre-push).
fake_hook="$(key tools/pre .commit)"
d="$(mk_repo_with "$fake_hook" "#!/usr/bin/env bash
# $a100
# $b100
# $c140
echo done
")"
run "$pd" "$d" --quiet
check_contains "an extensionless shebang-only script is scanned like a .sh file" "$OUT" "commit:4"

# --- signal 2: a dead relative link -> GAP, exit 1 --------------------------------------------------
d="$(mk_repo_with doc.md "# doc

See [the guide](./missing-file.md) for detail.
")"
run "$pd" "$d" --quiet
check_status "a dead relative link fails the script -> exit 1" 1 "$STATUS"
check_contains "reports the dead link" "$OUT" "does not resolve"

# --- signal 2: a valid relative link -> OK, exit 0; the SAME link, broken, -> GAP (dir #110 pairing) -
d="$(mk_repo_with doc.md "# doc

See [the guide](./other.md) for detail.
" other.md "# other
")"
run "$pd" "$d" --quiet
check_status "a valid relative link doesn't fail the script -> exit 0" 0 "$STATUS"

d="$(mk_repo_with doc.md "# doc

See [the guide](./other.md) for detail.
")"
run "$pd" "$d" --quiet
check_status "the SAME link, now with its target missing, DOES fail -> exit 1" 1 "$STATUS"

# --- signal 2: a broken-link EXAMPLE inside a fenced code block is not flagged; the SAME content
# unfenced (a real broken link) DOES fail -> exit 1 (dir #110 pairing) -------------------------------
d="$(mk_repo_with doc.md '# doc

Example of a broken link:

```
[guide](./missing-illustrative.md)
```
')"
run "$pd" "$d" --quiet
check_status "an illustrative dead link inside a fence does not fail the script -> exit 0" 0 "$STATUS"

d="$(mk_repo_with doc.md '# doc

[guide](./missing-illustrative.md)
')"
run "$pd" "$d" --quiet
check_status "the SAME content, unfenced, DOES fail -> exit 1" 1 "$STATUS"

# --- --quiet suppresses OK but never a WARN/GAP -----------------------------------------------------
d="$(mk_repo_with doc.md "# doc

$a100
$b100
$c140
")"
run "$pd" "$d" --quiet
check_absent "--quiet suppresses OK lines" "$OUT" "OK   no dead"
check_contains "--quiet still shows a WARN" "$OUT" "WARN"

# --- signal 2: dir #217 — no repo-root fallback; a link resolving ONLY via the repo root (not
# sibling-relative to the linking file) is dead, not green -------------------------------------------
d="$(mk_repo_with sub/doc.md "# doc

See [the guide](other.md) for detail.
" other.md "# other
")"
run "$pd" "$d" --quiet
check_status "a repo-root-only-resolving link fails -> exit 1 (no fallback)" 1 "$STATUS"
check_contains "reports the fallback-only link as dead" "$OUT" "does not resolve"

d="$(mk_repo_with sub/doc.md "# doc

See [the guide](../other.md) for detail.
" other.md "# other
")"
run "$pd" "$d" --quiet
check_status "the SAME target, correctly sibling-relative, resolves -> exit 0" 0 "$STATUS"

# --- signal 2: dir #218 — a link to a heading anchor that doesn't exist is a GAP; the SAME anchor,
# once the heading exists, is OK ----------------------------------------------------------------------
d="$(mk_repo_with doc.md "# doc

See [the section](#does-not-exist) for detail.
")"
run "$pd" "$d" --quiet
check_status "a dead in-document anchor fails -> exit 1" 1 "$STATUS"
check_contains "reports the dead anchor" "$OUT" "anchor does not resolve"

d="$(mk_repo_with doc.md "# doc

See [the section](#a-real-section) for detail.

## A Real Section
")"
run "$pd" "$d" --quiet
check_status "an anchor matching a real heading's GitHub slug resolves -> exit 0" 0 "$STATUS"

# Cross-file anchor, and GitHub's own non-collapsing hyphenation for a run of dropped punctuation —
# an em dash between two spaces slugs to a DOUBLE hyphen, not one (dir #217/#218's shared spec cites
# this exact shape from docs/getting-started.md).
d="$(mk_repo_with doc.md "# doc

See [linked install](other.md#linked-install--recommended) for detail.
" other.md "# other

## Linked install — recommended
")"
run "$pd" "$d" --quiet
check_status "a cross-file anchor with an em-dash heading resolves -> exit 0" 0 "$STATUS"

# --- signal 2: dir #224 — balanced parens in a link target, and a percent-encoded target, both
# resolve rather than false-GAP; the SAME shapes pointing at a missing file still fail -----------------
d="$(mk_repo_with doc.md "# doc

See [x](design(notes).md) for detail.
" "design(notes).md" "# notes
")"
run "$pd" "$d" --quiet
check_status "a target with one level of balanced parens resolves -> exit 0" 0 "$STATUS"

d="$(mk_repo_with doc.md "# doc

See [x](design(notes).md) for detail.
")"
run "$pd" "$d" --quiet
check_status "the SAME balanced-paren target, missing, DOES fail -> exit 1" 1 "$STATUS"

d="$(mk_repo_with doc.md "# doc

See [y](design%20notes.md) for detail.
" "design notes.md" "# notes
")"
run "$pd" "$d" --quiet
check_status "a percent-encoded target resolves against its decoded path -> exit 0" 0 "$STATUS"

d="$(mk_repo_with doc.md "# doc

See [y](design%20notes.md) for detail.
")"
run "$pd" "$d" --quiet
check_status "the SAME percent-encoded target, missing, DOES fail -> exit 1" 1 "$STATUS"

# --- signal 2: an anchor whose GitHub slug legitimately starts with '-' doesn't trip `grep`'s own
# option parsing (found by an independent agent review of dir #218's own diff) ------------------------
d="$(mk_repo_with doc.md "# doc

See [a](#--todo-item) for detail.

## - Todo Item
")"
run "$pd" "$d" --quiet
check_status "a leading-hyphen anchor resolves, not misread as a grep flag -> exit 0" 0 "$STATUS"

# --- signal 2: a literal '%' in a target that isn't part of a %XX escape is left alone, not corrupted
# by the percent-decoder (found by the same review) ----------------------------------------------------
d="$(mk_repo_with doc.md '# doc

See [b](100%.md) for detail.
' "100%.md" "content
")"
run "$pd" "$d" --quiet
check_status "a bare percent sign in a target resolves, not corrupted by decoding -> exit 0" 0 "$STATUS"

# --- signal 2: a `#fragment` link into a NON-markdown target is out of scope for anchor validation —
# a GitHub line anchor (e.g. `file.sh#L10`) is a viewer feature, not a dead heading (found by the
# cross-model second-opinion review of dir #218's own diff) --------------------------------------------
d="$(mk_repo_with doc.md "# doc

See [x](script.sh#L10) for detail.
" script.sh "#!/usr/bin/env bash
# not a heading
")"
run "$pd" "$d" --quiet
check_status "a fragment into a non-md file is not anchor-checked -> exit 0" 0 "$STATUS"

# --- signal 2: a tab inside heading text hyphenates like a space would, instead of being silently
# dropped (found by the same review) --------------------------------------------------------------------
d="$(mk_repo_with doc.md "# doc

See [x](#foo-bar) for detail.

## Foo	Bar
")"
run "$pd" "$d" --quiet
check_status "a tab-separated heading slugs with a hyphen, not a dropped tab -> exit 0" 0 "$STATUS"

# --- signal 2: a heading with trailing whitespace slugs without a spurious trailing hyphen (found by
# /code-review medium, angle A) --------------------------------------------------------------------
trailing_space_heading="## Notes "
d="$(mk_repo_with doc.md "# doc

See [x](#notes) for detail.

$trailing_space_heading
")"
run "$pd" "$d" --quiet
check_status "a heading with trailing whitespace still resolves -> exit 0" 0 "$STATUS"

# --- signal 2: a literal backslash already in a target isn't corrupted by percent-decoding (found by
# /code-review medium, angle A) -----------------------------------------------------------------------
d="$(mk_repo_with doc.md '# doc

See [x](note\ntest.md) for detail.
' 'note\ntest.md' "content
")"
run "$pd" "$d" --quiet
check_status "a literal backslash in a target resolves, not reinterpreted -> exit 0" 0 "$STATUS"

# --- signal 2: a relative filename that merely starts with "http"/"mailto" is still existence-checked,
# not mistaken for an external link (found by /code-review medium, angle A) ----------------------------
d="$(mk_repo_with doc.md "# doc

See [x](http-notes.md) for detail.
")"
run "$pd" "$d" --quiet
check_status "a missing http-prefixed relative filename still fails -> exit 1" 1 "$STATUS"

d="$(mk_repo_with doc.md "# doc

See [x](http-notes.md) for detail.
" http-notes.md "content
")"
run "$pd" "$d" --quiet
check_status "the SAME http-prefixed filename, present, resolves -> exit 0" 0 "$STATUS"

# --- signal 2: a percent-encoded anchor decodes before matching against a heading slug (found by
# /code-review medium, angle A) — %2D is a hyphen, so the decoded anchor and the heading's own slug
# agree only once decoding actually happens ------------------------------------------------------------
d="$(mk_repo_with doc.md "# doc

See [x](#foo%2Dbar) for detail.

## Foo-Bar
")"
run "$pd" "$d" --quiet
check_status "a percent-encoded anchor resolves against the decoded slug -> exit 0" 0 "$STATUS"

# --- signal 2: a leading-slash target is GitHub's own repo-root-relative link convention, not the
# undocumented bare-relative fallback dir #217 removed (found by /code-review medium, angle B) ---------
d="$(mk_repo_with sub/doc.md "# doc

See [x](/other.md) for detail.
" other.md "# other
")"
run "$pd" "$d" --quiet
check_status "a leading-slash target resolves against the repo root -> exit 0" 0 "$STATUS"

d="$(mk_repo_with sub/doc.md "# doc

See [x](/other.md) for detail.
")"
run "$pd" "$d" --quiet
check_status "the SAME leading-slash target, missing, DOES fail -> exit 1" 1 "$STATUS"

summary
