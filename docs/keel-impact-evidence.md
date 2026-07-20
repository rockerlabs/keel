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
