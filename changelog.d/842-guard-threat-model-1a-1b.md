- **A guard's filing rule now tells a realistic failure from a constructed bypass, and each guard states the
  threat model it is built against.** The always-file condition of
  [`docs/verification-economics.md`](/docs/verification-economics.md) §4 splits by the input that makes the
  surface fail. A **realistic failure** (it happened, or it needs no special input, or the input is attested in
  ordinary use) is filed with no discretion, as before. A **constructed bypass** that real sessions were
  searched for and not found goes into the guard's known-bypass register instead of a ticket, and is promoted
  only when a realistic sighting turns up. When the branches cannot be told apart, the guard's miss decides: a miss
  that would send data off the machine or destroy data is filed (the secret guard, `public-audit`, the
  pre-PR gate's push rule, the subagent git floor, a write outside the test sandbox, the installer), and a
  workflow miss goes to the register. Every procedure doc that restates "below the bar, a standing-list line"
  now sends a constructed-bypass finding to its register. [`SECURITY.md`](/SECURITY.md) gains "Threat model by
  guard" — a row per guard: what it guards against, what a miss costs, the doubt class, what still catches it,
  where its register lives — and its Scope now says a bypass that holds only for a constructed input is a
  known limit, not a vulnerability.
- **The registers gain the shapes this re-classification closes.** The pre-PR gate's header names a heredoc-
  or pipe-fed shell, an upper-case command word, a grouped `case` inside `$(…)` and a hook started with stdin
  closed; its subagent floor names the upper-case verb; `tests/lib.sh` names `run.sh`'s unpinned `termed`
  branch and `tools/lib/safe-write.sh` its unpinned link-planting check. Closed into those registers rather
  than filed: dir #763, dir #776, dir #777, dir #778, dir #779, dir #780, dir #781 and dir #792.
  `tests/test_known_bypass_registers.sh` pins every row, its register and its entries, and
  `tests/test_verification_economics_doc.sh` pins the rule's needles and its routing sites.
