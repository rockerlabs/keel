# Publishing checklist — making a repo public-ready

This is the "is it finished and presentable?" list — what a repo should have before (and right after) you
make it public, so the work goes fast the next time instead of being re-derived from scratch.

Three siblings answer the other halves of "how do you know it's still true?":
[`release-audit.md`](release-audit.md) checks the *project* is ready to tag,
[`rollout-audit.md`](rollout-audit.md) checks a model or harness upgrade didn't quietly break your
pipeline, and [`drydock.md`](drydock.md) audits whether the repo's own prose — the README this list asks
you to write, the docs it asks you to ship — still matches the tree it describes. This list only checks
that they exist and look finished.

It's the companion to [`going-public.md`](going-public.md), which covers the **safety** side (no secrets or
personal data leak). Do that one first; this one second. Roughly: *going-public = don't leak*,
*this = look finished*.

Each item is marked **[auto]** (a tool or one command answers it) or **[you]** (your judgment or a manual
step). Skip nothing silently — if you decide an item doesn't apply, say so (see §6).

## 0. Safety gate — do this first

- [ ] **No secrets or personal data** in the tree *or* git history. Run [`public-audit`](../tools/public-audit.sh)
      → it must exit 0, **and read every WARN it printed**. Full fix procedure:
      [`going-public.md`](going-public.md). Don't flip until this is clean — a leak in history survives a
      later delete. **[auto]** for the exit code, **[you]** for the WARNs, and the split is the point:
      every personal-data heuristic (home paths, content emails, Cyrillic, agent/session metadata) is a
      WARN and leaves the exit code at 0. A clean exit is not a clean tree — only your read of the WARN
      list closes this item.

## 1. The files a stranger expects

- [ ] **README** — the first screen answers "what is this, and do I want it?" One plain-words line at the
      very top, then why it exists and how to start. **[you]**
- [ ] **LICENSE** — pick one. Without it, legally no one may use your code. **[you]**
- [ ] **CHANGELOG** — at least a first entry, so people see what shipped. **[you]**
- [ ] **.gitignore** — hides local/private files (IDE, OS, build output, and any private context). **[you]**
- [ ] **SECURITY.md** — how to report a vulnerability. Worth having early if the project touches security at
      all. Also turn on **private vulnerability reporting** so the "Report a vulnerability" link works. **[you]**

## 2. Make it findable (GitHub "About")

An empty About box makes a repo look abandoned at a glance. All three are one `gh` command:

- [ ] **Description** — one clear sentence under the repo name. `gh repo edit --description "…"` **[auto]**
- [ ] **Topics** — tags so search and topic pages surface it. `gh repo edit --add-topic a --add-topic b` **[auto]**
- [ ] **Homepage URL** — a docs site or a key doc; optional but cheap. `gh repo edit --homepage "…"` **[auto]**

## 3. Green and protected

- [ ] **CI passing on the default branch** — the badge is green, not stuck or red. **[auto]**
- [ ] **Branch protection on `main`** — PR required, CI required to merge, force-push and deletion blocked.
      (Solo project: 0 required approvals, self-merge is fine.) **[you]**
- [ ] **Auto-delete branches on merge** — keeps the branch list from filling with merged noise. **[auto]**

## 4. A real release

- [ ] **A version tag + GitHub release** — so people can pin a version and read what changed. **[you]**
      Create and push the tag YOURSELF, annotated, on the exact SHA the release audit named
      ([`release-audit.md`](release-audit.md) phase 7 stops at "tag ready to cut" and names that SHA;
      v0.6.1's tag is this shape, an annotated tag on the named merge commit):
      `git tag -a <tag> <sha> -m "<tag> — <headline>" && git push origin <tag>`
      A bare `gh release create <tag>` with no tag already on the remote silently creates one at **the
      default branch's head at execution time** — a different commit if anything landed since the cut.
      If you let `gh` create the tag, pass `--target <sha>`.
- [ ] **A no-clone install path works**, if you offer one (e.g. `curl … | sh`) — and you actually ran it
      once on a clean machine/sandbox, not just wrote it. **[you]**
- [ ] **Attach a stamped `bootstrap.sh` to the release**, so `releases/latest/download/bootstrap.sh`
      installs THIS tag by default instead of tracking main:
      `tools/stamp-release-bootstrap.sh <tag> /tmp/bootstrap.sh && gh release create <tag> --title "<tag> — <headline>" --notes-file <notes-file> /tmp/bootstrap.sh`
      (or `gh release upload <tag> /tmp/bootstrap.sh` on an existing release). **[you]** — not `[auto]`:
      `<notes-file>` still has to be composed from `CHANGELOG.md`, and reviewed before publishing,
      which is the step whose omission caused v0.6.1's blank release. `tools/changelog-section.sh <version> --digest`
      prints just the opener + `### ` headings first, to skim before composing; then
      `tools/changelog-section.sh --edit <version> <notes-file>` extracts the full section to a
      scratch file and opens it in `$EDITOR` — **the interactive `--edit` path a human runs by
      hand.** Outside that path, **composing the notes is agent-composed at this step,
      operator-reviewed before publishing** (`dir #367` — reversing this line's earlier "curation is
      still human by nature"
      framing): a session — the manager inside a managed release, or a standalone session
      otherwise — composes `<notes-file>` directly from the tagged commit's `CHANGELOG.md` section,
      per [`docs/release-management.md`](release-management.md) R9, without needing `--edit`'s
      `$EDITOR` step at all; `--edit` stays available for a human who wants to curate by hand instead.
      `<notes-file>` is never touched unless the editor exits 0 on that path. Either way this tool
      extracts the section, not the release note itself. Publishing stays irreversible and
      outward-facing, so the *review*, not the *write*, is what this line still gates.
      **`<notes-file>` is composed at this step, from the CHANGELOG section as it stands on the
      merged commit being tagged, and never earlier in the release pass.** A notes file that already
      exists when you reach this step was cut from a pre-fix source — discard it and recompose, don't
      review it. *Felt case: v0.7.0's notes file was handed over before a review correction landed to
      the CHANGELOG section it was cut from, and the documented `--notes-file` hand-off would have
      published into a GitHub Release a claim the same PR proved false — the one release artifact no
      repo-side check ever sees and that no commit amend can fix (dir #206).*

      `--edit` also prints two non-fatal warnings at this step (dir #326), best-effort and to stderr
      only — read them, don't just check the exit code: **HEAD not matching the `v<version>` tag**
      (this step reads the working tree, and a stale checkout composes notes from a different commit
      than the one just tagged, silently, unless you're at the tagged commit — *felt: the checkout sat
      5 commits behind `origin/main` at this exact step*), and **`<notes-file>` landing within 80% of
      the section's own byte size** (curation didn't happen — *felt: a 42,090-byte body against a
      42,274-byte section, 99.6%, the section pasted whole*). Neither is a hard fail; a printed
      warning is enough because the failure mode here is not noticing, not disagreeing.
- [ ] **Give the release a title and real notes**, then check them: `gh release view <tag> --json
      name,body,assets`. `--notes-from-tag` alone yields a blank title and a one-line body, and an empty
      title is invisible from the command that created it. **[you]**
      *Notes are CURATED from the `CHANGELOG.md` section you just cut, not a copy of it* — this repo's own
      releases run ~4KB (a prose opener, three or four highlight sections, a Known-issues paragraph) while
      the section itself ran ~31KB at v0.6.1, so pasting it whole gives a release note eight times the
      house length. The section is the source and the authority; the release note is the readable
      digest of it. *(v0.6.1 shipped with a blank title because this list omitted `--title`; see
      `CHANGELOG.md`'s dir #159 entry.)*

## 5. Presentation

- [ ] **Social preview image** — the card shown when the link is shared (Slack, X, Discord). Without it you
      get a generic auto-card. **Manual upload only** — Settings → General → Social preview; there is **no
      API** for it. 1280×640 PNG. **[you]**
- [ ] **README badges** — CI status and license at minimum. **[you]**

## 6. Decide, don't default (usually skip until needed)

Add these only when a real need shows up — not to tick a box. Adding process before there are people to use
it is just ceremony.

- [ ] **CONTRIBUTING.md** + issue/PR templates — when real contributors actually arrive. **[you]**
- [ ] **CODE_OF_CONDUCT.md** — same trigger. **[you]**
- [ ] **Discussions** — only if you'll read and use them. **[you]**
- [ ] **Org profile README** — when the org hosts more than one thing worth a landing page. **[you]**

> GitHub's "community standards" percentage counts only CONTRIBUTING.md + templates and
> CODE_OF_CONDUCT.md from this list — Discussions and an org profile README aren't part of that score at
> all. A deliberate skip of CONTRIBUTING.md/templates or CODE_OF_CONDUCT.md leaves the percentage
> **below 100% — that's expected, not a defect.** Write the decision down (a line in your project notes)
> so a future session doesn't re-open it.

## How fast this should go

Sections 2–4 are mostly one `gh` session. Sections 1 and 5 (a real README and a preview image) are the only
parts that take real thought. With `public-audit` doing the §0 legwork (its blockers automatically, its
WARNs for you to read) and `gh repo edit` covering the metadata, a clean repo goes from private to
presentable in well under an hour.
