# changelog.d/README.md — keel-self-maintenance (dir #68): one changelog file per PR, assembled at the cut

*This directory is how Keel's own repo writes its changelog. install.sh never ships it and an adopter's
project does not need it; it exists so two PRs stop colliding at one anchor.*

A PR's changelog entry is a new file here, **not** a bullet under `## [Unreleased]` in
[`CHANGELOG.md`](/CHANGELOG.md). Two PRs that each append at that one anchor conflict (and every PR that
falls behind turns DIRTY, with no CI run); two PRs that each add their own file do not (dir #744).

## Writing a fragment

- **Name** it `changelog.d/<ticket>-<slug>.md`: `<ticket>` is the PR's main `dir` number, digits only;
  `<slug>` is lowercase kebab-case. A PR with no ticket uses `<slug>.md`. Two PRs that pick the same name
  conflict visibly (add/add), never silently. Do not edit another PR's fragment unless correcting it is
  your PR's purpose.
- **Content** is only the bullets, exactly as they would sit under `## [Unreleased]`: the first non-blank
  line starts `- `, continuation lines are indented (fenced blocks too: indent the fence markers and what is
  inside), fence markers come in pairs, and no line starts with `#` (a heading would split the cut's
  section). Cite a ticket as `dir #N` in full, never wrapped in backticks.
- **Links** to a file in the repo are root-anchored, `[text](/docs/x.md)`, never relative; a bare `#anchor`
  or any scheme other than `http(s)` and `mailto` is rejected too. The cut moves
  the text into `CHANGELOG.md` verbatim, and `tools/self/prose-drift.sh` resolves a bare relative target
  beside the file that holds it, so `docs/x.md` would be dead from in here.
- Anything in this directory other than this README must be a non-empty top-level `*.md` file named as
  above: no subdirectory, no dotfile, no other extension. Only tracked files count (the lint reads what CI
  will see), so `git add` the fragment before you lint it.

Lint your fragment before you push; it prints nothing when everything passes:

```bash
tools/self/changelog-fragments.sh --check
```

## How the entries are read

`tools/self/changelog-fragments.sh` is the one reader. It prints every fragment in `LC_ALL=C` filename order
(never modification-time order), one blank line between fragments. The *effective unreleased text* is the
body of `CHANGELOG.md`'s `## [Unreleased]` followed by that output, so bullets already under `[Unreleased]`
stay valid next to fragments. Anything that checks a changelog cite reads both, never one fragment alone:
a cite you pin in a test lives in a file that disappears at the cut.

`tools/self/doctor.sh` matches the `dir #N` tickets in the commits since the last tag against that text,
and takes `changelog.d/` into account when it judges whether the changelog is stale.

## The cut

At the release cut, run this from the repo root, then curate the new section by hand and commit:

```bash
tools/self/changelog-cut.sh 0.17.0 2026-12-31
```

It appends the fragments after the last line of `[Unreleased]`, renames that heading to
`## [VERSION] — DATE`, opens a fresh empty `## [Unreleased]` above it and deletes the fragment files (this
README stays). It never runs git, and it refuses without changing anything on a bad version or date, a
second `[Unreleased]`, a `## [VERSION]` that already exists, or a fragment that fails the lint. Running it
twice therefore refuses the second time; a fragment that merges after the cut ran (before the tag) fails
`tools/self/doctor.sh` until it is moved into the cut section. See
[`docs/release-audit.md`](/docs/release-audit.md) Phase 7 for where it sits in the release order.
