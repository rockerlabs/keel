# Keel impact — per-event evidence

The auditable trail behind each row in `keel-impact.md` (the ledger). Every scored session appends one dated
block listing each counted event and the citation that backs it — so a score is a checkable record, not a
number to trust. A count in the ledger equals the number of citations here: no citation, no count. Guard
citations are captured from the guardrail hooks (`source | detail`); the rest are supplied at score time.

`tools/keel-impact.sh add` writes the blocks; this header is created once. Shape of a block:

```
## 2026-07-09 — score 82/100 (conf high)

- guard: secret-guard | blocked
- fire: P0 real-time-propose | LEARNINGS.md:42 | cold would have waited to be told
- fire: git feature-branch flow | branched off main | cold commits to main
- hit: test command @ CLAUDE.md | ran the suite
- miss: hunted for the lint command
```

## 2026-07-20 — score 100/100 (conf low)

- guard: SEC4 server-side secret-scan (CI run 29722488680, PR #104) blocked agent session-metadata trailers (Claude-Session:) in commit messages 1dfb7d0 + 1d30f73; fixed by history rewrite (filter-branch), not by allowlisting

## 2026-07-20 — score 100/100 (conf med)

- guard: SEC4 ci-scan blocked PR #106 push (secret-scan job, 2026-07-20): the coding harness's session-URL commit trailer in both commit messages matched the key-shape patterns; resolved by stripping the trailer via filter-branch (no allowlist added, per the gate's own rule), scan clean on re-push
- hit: CORE.md Precedence rail ('safety rails yield only to an explicit human decision') @ always-on core — anchored the central design call of PR #106: --no-git is an install-time trim, never load-on-demand, so a git user's rails sit in context before the first git command
- hit: ADAPTING.md no-git trim note + keel-setup.md scope-question precedent @ KB — defined the exact KEEL-GIT module boundary (the same two sections the copy-mode trim already removed) without re-deriving it
