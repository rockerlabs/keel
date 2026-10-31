- The cloud route settles the five decisions left open by dir #907's reviews (dir #913). `tools/cloud-brief.sh` reads
  the `KEEL-CLOUD` opt-in from fence-blanked text, like every other field: a line inside a fenced example opts
  nothing in (G1, exit 3) and the refusal prints it as "inside a fenced block". A body line glued directly under a
  heading that has no recognized tail (`— R<d>`, `→ pool`, a status glyph) is refused as G2, naming the line and
  asking for a blank line after the heading, since the backlog lib folds it into the heading and G2 would read a
  `📐` or a `✅` from body text (a wrapped heading whose tail lands on a later line still passes; the shared lib is
  unchanged). The dispatch never writes the session id into the ticket's `Log:` line, a gitignored backlog's
  included: the ledger gains a 15th `session` cell that holds it (an older 14-cell ledger keeps working). G7's
  refusal quotes git's own stderr instead of the generic "git cannot tell". `tools/lib/cloud.sh`'s `cloud_gh_api`
  maps a 403 that is a rate limit (`X-RateLimit-Remaining: 0`, read from a second `--include` call, or "rate limit"
  in the message) to exit 2 (transient); any other 403 stays "not readable" (G1/G1b/G1c, exit 3).
  `tools/cloud-land.sh` reads a draft PR with a `skipped` check as not green (exit 3, with `gh pr ready <PR#> --repo
  <o>/<r>`, wait for CI, re-run), and its remedy grep reads bytes (`LC_ALL=C grep -a`) like the marker greps.
  `docs/cloud.md` names exit 2 for unpaired fences, B1's fence rule, the rate-limit exit and the draft rule, pinned
  in `tests/test_cloud_doc.sh`. Tests: the gh stub can answer a 403 (with response headers under `--include`);
  the landing remedy test asserts the hint's own phrase; T18's fd-3 claim is named as pinned for BSD and
  util-linux `script`.
