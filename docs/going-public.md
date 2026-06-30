# Going public — flipping a private repo, safely

Keel is publication-first, but a repo that grew up private accumulates two kinds of leak a flip would
expose: **content** (personal data / instance-specific strings in the tree) and **history** (real emails in
commit/tag metadata, private tokens or personal data in old blobs and messages).
[`public-audit`](../tools/public-audit.sh) is the detector — but know exactly what it **fails** on vs what
it only **flags**: it **GAPs** (exit 1) on a non-public-safe commit/tag identity email and on an
user-declared `--token`; it **WARNs** (advisory) on heuristic hits — emails, absolute home paths, and
Cyrillic — in the tree *and* in history (message bodies + diffs), plus agent/session metadata. A bare
personal name in a message body isn't a hard GAP, so hunt declared tokens with `--token` before a flip.
This page is the **procedure** to fix what it finds and flip without churn.

> **This page is the *safety* half — "don't leak."** For the *presentation* half — "does the repo look
> finished?" (README, LICENSE, About metadata, social preview, release, branch protection) — see
> [`publishing-checklist.md`](publishing-checklist.md). Run this one first, that one second.

## Checklist

0. **Detect** — run `public-audit`.
1. **Stop the bleed** — fix your commit identity (two settings).
2. **Scrub history** — only if `public-audit` flags identities/tokens.
3. **Purge host PR refs** — if the repo has any closed PRs, their old commits survive a `main`
   force-push in `refs/pull/*`. The only fix is **delete-and-recreate** (see below).
4. **Flip** visibility to public — only after steps 2–3 are done AND `public-audit` is exit 0.
5. **Trigger** one CI run.
6. **Share** the probe.

## 0. Detect

```bash
tools/public-audit.sh --token <private-name> .
```
GAP on non-public-safe identities and private tokens; WARN on heuristics (home paths, content emails,
Cyrillic, agent/session metadata). **Clear every GAP before flipping.** Re-run after each fix.

## 1. Stop the bleed — identity (do this FIRST)

Two settings, or the leak recurs:

- **Local git identity → a noreply.** `git config user.email <id>+<user>@users.noreply.github.com`. The
  numeric-`<id>`+ form attributes commits to your account on hosts where the account is recent; the bare
  `user@…noreply` form may not. Set it `--global` if this is a personal machine.
- **The host's email-privacy setting.** A merge done through the **web UI** authors the merge commit with
  your account's *primary* email — so **every web-merge re-adds your real address**. Enable the host's
  "keep my email private" setting so web operations use the noreply too. **Without this, the scrub below is
  undone by your next web-merge.**

## 2. Scrub history (only if `public-audit` flags identities/tokens)

A one-time history rewrite. **Validate on a throwaway clone first — never rewrite your only copy.** Uses
[`git-filter-repo`](https://github.com/newren/git-filter-repo).

```bash
git clone <url> scrub && cd scrub

cat > /tmp/mailmap <<EOF
<Name> <<id>+<user>@users.noreply.github.com> <real@email>
EOF
cat > /tmp/msg <<'EOF'
<private-token>==><neutral-word>
EOF

before=$(git rev-parse HEAD^{tree})
git filter-repo --mailmap /tmp/mailmap --replace-message /tmp/msg --replace-text /tmp/msg

# --- gates: all three must hold before any push ---
git log --all --format='%ae' | sort -u                     # only noreply addresses
[ "$(git rev-parse HEAD^{tree})" = "$before" ] && echo OK   # tree UNCHANGED — rewrite touches history, not content
<keel>/tools/public-audit.sh --token <private-name> .        # exit 0  (<keel> = your Keel checkout; the auditor lives there, not in this scrub clone)

git remote add origin <url>                                 # filter-repo drops origin
git push origin --force <default>:<default>                 # a NAMED branch — never --all
```

> **Never `git push --force --all`.** It overwrites every remote ref, including from a stale local default,
> and can silently roll the default branch back over merged work. Push the *named* branch, and reconcile
> your local default with the remote first.

## 3. Purge host PR refs (if the repo has closed PRs)

This is the one a `main` scrub does **not** fix. The host keeps every PR's commits in `refs/pull/<n>/*`,
which are **world-fetchable on a public repo** and survive a force-push of `main`. They carry whatever those
old commits carried — a real email, an ex-employer name. **`git log --all` does not reach them**, so a
local-only scan can miss them; `public-audit` fetches them when a remote is reachable (and GAPs on a leak
there), but the **only remediation is delete-and-recreate** — there is no force-push that purges PR refs.

**Delete and recreate** the repo from the scrubbed clone (or ask the host to garbage-collect the refs).
Acceptable for a pre-launch solo repo — you lose PR threads; the tag/release are re-pushable. A private
pre-launch repo with no external clones is the cheapest moment to do this, before PRs accumulate.

```bash
# from your scrubbed working clone (main already clean):
gh repo delete <owner>/<repo> --yes          # needs the delete_repo scope
gh repo create <owner>/<repo> --private --source=. --remote=origin --push
git push origin <tag> ; gh release create <tag> --notes-from-tag   # re-push tag + release
```

## 4. Flip visibility

Flip to public **only after** steps 2–3 are done **and** a fresh `public-audit` (with network, so it covers
host PR refs) is exit 0 — history, tree, and PR refs all clean.

## 5. Trigger one CI run

Public CI is typically free and unlimited. The badge stays stale until a run lands — push a trivial commit
or dispatch the workflow once to turn it green.

## 6. Share

Hand the probe to a few people, or post it. The remaining product readiness is **real-user signal** — only
publishing unlocks it; don't keep polishing for hypothetical users instead.

## Recovery — if a force-push rolled the default back

The lost commits stay reachable for a while (your reflog, a clone, or the host's PR refs). Find a good copy
— a validation clone is ideal — then force-push the **named** branch from it:

```bash
git push origin --force <default>:<default>
# re-sync working copies (gitignored files are preserved):
git -C <working-copy> fetch origin && git -C <working-copy> reset --hard origin/<default>
# delete any stray branches a --force --all pushed:
git push origin --delete <stray-branch> ...
```

## Hard-won, in one place

- **The host email-privacy setting is the root fix** — without it, web-merges keep re-adding your real
  address, undoing any scrub.
- **Never `git push --force --all`** — push the named branch; reconcile local with upstream first.
- **`public-audit` detects, this page fixes** — run the audit before every flip; it is cheap, and it has
  caught real leaks (a corporate email in history, a session-trailer URL) that manual vigilance missed.
