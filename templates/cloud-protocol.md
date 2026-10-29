# Cloud session protocol — ticket <ticket> of <repo>

You are implementing one ticket, <ticket>, end to end in a Claude Code cloud session. This brief is everything
you get: the protocol (this part), then the ticket, then its spec when it has one, then the project's rails, each
under a `=== <part> ===` marker line. Do the steps below in letter order.

(a) Where you are.
- You run in a cloud VM on a clone of `<repo>`. Nothing outside this brief and that repository exists for you: no
  operator machine, no knowledge base, no hooks of the operator's (step (a3) installs a guard of its own), no
  pre-PR gate.
- Truncation check, first: the brief's very LAST line must be `=== end of brief ===` (its mention in this
  sentence does not count). If the brief does not end with that line, it was truncated in transit: do nothing
  else — no clone, no fetch, no branch, no edit — and stop and report a truncated brief in chat, naming the last
  part marker you can see. The session never works from a partial brief.
- Precedence: where the `rails` part conflicts with this protocol, this protocol wins. Rails steps that name the
  project's main checkout, a local gate or a local-only tool, `/polish`, `/wrap`, the backlog, a release plan or
  the specs directory do not apply here: those live on the operator's machine (the ticket and any spec are in
  this brief), and steps (e)–(g) plus the operator's local landing check replace them.
- Shell variables do not persist between your commands. Run `KT=$(mktemp -d) && echo "$KT"` once, now; wherever
  a command below uses `$KT`, start it with `KT=<the path it printed>;`.

(a1) The keel tools, before anything else. Run
`git clone <keel-origin> "$KT/keel" && git -C "$KT/keel" checkout -q <keel-sha> && git -C "$KT/keel" rev-parse HEAD`
and check that the printed sha equals `<keel-sha>`. A clone or network failure: wait 30 seconds and retry once. A
second failure, or a sha mismatch (never retried): push nothing, end per (j)'s no-PR form, stop. This stop
overrides (i)'s "an operator-only obstacle blocks only its own step": without these tools no push can be scanned.

(a2) Language. In chat, talk in the language the `rails` part names for talking to the operator, from your first
message; English when it names none. Everything in git and on GitHub — code, comments, commit messages, the PR
title and body — is in English.

(a3) The push guard, before the first push. Install it with exactly this block, run as one command (set `KT`
first, as above), from the work tree:

```sh
mkdir -p "$KT/keel-guard" && cat > "$KT/keel-guard/pre-push" <<'KEEL_CLOUD_GUARD'
#!/bin/sh
# keel cloud guard: this session may push one branch only, and never delete it.
allowed='refs/heads/<branch>'
refused=0
refuse() { echo "keel cloud guard: refused $1" >&2; refused=1; }
# git hands every ref of the push on stdin, one line each: <local-ref> <local-sha> <remote-ref> <remote-sha>.
while read -r local_ref local_sha remote_ref _ || [ -n "$local_ref" ]; do
  if [ "$remote_ref" != "$allowed" ]; then
    refuse "a push to '$remote_ref' (only $allowed may be pushed)"
  elif [ "$local_ref" = '(delete)' ]; then
    refuse "deleting '$remote_ref'"
  else
    case "$local_sha" in *[!0]*) ;; *) refuse "deleting '$remote_ref'" ;; esac
  fi
  local_ref=''
done
exit "$refused"
KEEL_CLOUD_GUARD
chmod +x "$KT/keel-guard/pre-push" && git config --local core.hooksPath "$KT/keel-guard"
```

The guard lives outside the work tree and replaces `.git/hooks`, which a configured `core.hooksPath` silently
skips. Prove it after (b)'s reset and before (b)'s first push, with `S=$(git rev-parse HEAD)` set in the same
command as `KT`:
- `git config --get core.hooksPath` prints `$KT/keel-guard`;
- `printf 'refs/heads/x %s refs/heads/<default> %s\n' "$S" "$S" | "$KT/keel-guard/pre-push"` exits non-zero;
- `printf 'refs/heads/<branch> %s refs/heads/<default> %s\n' "$S" "$S" | "$KT/keel-guard/pre-push"` exits non-zero;
- `printf '(delete) 0000000000000000000000000000000000000000 refs/heads/<branch> %s\n' "$S" | "$KT/keel-guard/pre-push"` exits non-zero;
- `printf 'refs/heads/x %s refs/heads/<branch> %s\n' "$S" "$S" | "$KT/keel-guard/pre-push"` exits 0.

A failed proof: push nothing, end per (j)'s no-PR form, stop. Before every later push, beside the scan, re-check
that `git config --get core.hooksPath` still prints `$KT/keel-guard` and that `$KT/keel-guard/pre-push` is still
an executable file; if either fails, push nothing, end per (j)'s no-PR form, stop. The guard catches an accident,
not an adversary: never pass `--no-verify` to any git command.

(b) Branch and pushes.
- Setup. Run `git fetch origin <default>`; if `git rev-parse --is-shallow-repository` prints `true`, run
  `git fetch --unshallow origin` as well. Check out a local branch reset to `origin/<default>`
  (`git checkout -B <branch> origin/<default>`), run (a3)'s proof, then push it at once, empty:
  `git push origin HEAD:refs/heads/<branch>`. Then say in chat, as your first line: `branch: <branch>`.
- What to push: only `HEAD:refs/heads/<branch>`, even when your environment names another branch for you (the
  operator's tools expect `<branch>`). No tag; never `<default>`, never another branch. Push after every green step, so a reclaimed VM loses nothing.
- Before every push, `"$KT/keel/tools/secret-guard/secret-scan.sh" --range "origin/<default>..HEAD"` must exit 0.
  On any other exit, fix the commit first: a pushed commit counts as published — on a private repository too, to
  everyone with access.
- After a VM reclaim (the conversation is restored but background jobs, unpushed work and `$KT` are gone): first
  re-run (a1) and (a3) with a fresh `$KT` — the old guard directory is gone while `core.hooksPath` still names it,
  and git then runs no hook at all — then fetch, check out the pushed branch, treat anything not pushed as lost,
  and redo only the step that was running.

(c) Commit hygiene.
- No `Claude-Session:` line and no `claude.ai/code/session` URL anywhere you write: commit messages, the PR title,
  the PR body. The harness may append a `Claude-Session:` trailer while it composes a commit.
- After each commit, read `git log -1 --format=%B`. If such a line is there, `git commit --amend` with the message
  minus that line before pushing; re-read to confirm it is gone.
- Never write the text `secret-scan:allow` anywhere: the operator's landing check refuses a range that adds it.
- Keep the harness's own `Co-Authored-By:` line if it adds one; write none yourself.

(d) Implement per the ticket and its spec.
- For implementation craft — red test first, reconcile, scope — read `$KT/keel/commands/go-guide.md`. Skip its
  lines on the backlog, worktrees and the pre-PR gate.
- Reconcile first. With a spec: diff its `Baseline:` sha against `HEAD` for the files its impact map names, and
  re-read whatever moved. With no spec: read the files the ticket names, at `origin/<default>`.
- Done-criteria. With a spec: its acceptance items. With none: the ticket's `**Acceptance:**` or "Done when"
  lines. With neither: write your own, short and checkable, put them in the PR body, and list them under Landing
  notes' open questions.
- Red test first where tests are named. If the repository keeps `CHANGELOG.md` or `changelog.d/`, add an entry
  the way its existing entries are written.

(e) Checks, in this order.
- Run shellcheck only when the rails name it in the project's test command (`pip install shellcheck-py` installs
  it; apt has no package without an update).
- Run the tests the rails name for a touched file; else the rails' whole test command. If the rails describe a
  split of the suite, run its parts ONE AT A TIME, each as a background job waited for by its completion notice.
- While a test run is going, change nothing: no edit, commit, branch switch or fetch.
- A run cut short is never green: name it in the PR body.

(f) Review. Run `/code-review high` on the diff against `origin/<default>`. If it is not available, use a
general-purpose subagent given the diff and the done-criteria from (d), asked for correctness bugs with
`file:line`. Fix every load-bearing finding in one fix round, then re-run (e)'s checks for what the fix touched.

(g) PR.
- Write the title and body to a file. `"$KT/keel/tools/secret-guard/secret-scan.sh" -- <file>` must exit 0, and
  `grep -E 'claude\.ai/code/session|-Session:' <file>` must find nothing.
- If a PR from this branch already exists (`gh api "repos/<repo>/pulls?head=<owner>:<branch>"`, `<owner>` being
  the part of `<repo>` before the slash), update its body with a REST `PATCH` instead of opening a second one.
- Otherwise open it as a draft with `gh api repos/<repo>/pulls` (REST; `gh pr` may be blocked here). Fields:
  `title`, `head=<branch>`, `base=<default>`, `draft=true`, `body`.
- On a 403, print the title and body in chat for the operator, who clicks Create PR in the diff view.
- You never merge, never mark a PR ready and never close one: those are the operator's.

(h) PR body: Summary · Done-criteria (each → its evidence) · Checks · Review (findings → fixes) ·
`## Landing notes`.
- Checks: one line per command, with its result and the commit SHA it ran on. Runs before a later commit are
  advisory for the head; CI on the final head is the gate. Checks not run are named.
- `## Landing notes` holds:
  - the line `PR #<number> from <branch>`;
  - one line per learning worth persisting;
  - every step marked unverified because it needs the operator's machine, with its exact command;
  - open questions.

(i) Ask in chat only at a real fork.
- A ticket's open pre-decision — a choice the ticket leaves to the operator, even one it calls "either is
  acceptable": settle it yourself only when the repository's code or docs decide it, and say how. When they do
  not, the choice is not yours: ask it once in chat — one message with the options and your recommendation — AND
  write it into Landing notes' open questions, since the chat may be unwatched; then go on at once with every part
  that does not depend on the answer. Still unanswered when everything else is done → leave that part out.
- An operator-only obstacle (a key, a device, a live account, the operator's machine) blocks only its own step:
  finish the rest, mark that step unverified, and give the exact command the operator runs locally.

(j) The final message: the PR URL and the Landing notes. A session that stops before any PR exists ends instead
with the line `no PR: <the step> — <the reason>`, then the line
`abandon: docs/cloud.md, Abandoning — ledger row <repo> <ticket>`, then its Landing-notes content in chat — the
chat is then the only channel.
