- **`tools/self/backlog-census.sh` reads an adopter's own heading token (dir #605).** A backlog whose tickets
  are `### B.N`, `### KB.N` or `### RL.N` headings printed an empty census, and the adopters that hit it derived
  the three G3 rules by hand every groom. The new `--ticket-token ERE` flag (for example
  `--ticket-token 'B\.[0-9]+'`) names the token, replaces the default `dir #N` / `<n>.` for that run, and makes
  `--list` print the captured token (`B.12`). Without the flag nothing changes; an empty or malformed ERE exits 2.
  `backlog_ticket_blocks` in `tools/lib/backlog-blocks.sh` takes the same token as an optional second argument.
  Limits, stated in the tool's header and `docs/grooming.md` G3: a pool kept as a `## Pool` section
  rather than a `→ pool` heading tag is not read, `tools/self/pool-report.sh` does not take the flag, and the
  foreign-citation strip still recognises only `dir #N` citations (an adopter's own "Supersedes" citation of its token is not stripped).
