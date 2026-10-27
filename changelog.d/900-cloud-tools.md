- Two new tools let any adopting project run a backlog ticket in a Claude Code cloud session (dir #900, slice 1;
  the procedure doc and the command text follow in slice 2). `tools/cloud-brief.sh <repo> <ticket-id>` checks the
  ticket against the mechanical eligibility rows — the project's own `KEEL-CLOUD` opt-in line, a readable
  github.com origin, a default branch protected for everyone (or `KEEL-CLOUD unprotected-ok`), a CI workflow, an
  open R3/R4/📐 ticket, its `**Cloud:**` verdict line, a present spec, no design-pass phrase, the brief's size —
  builds one self-contained brief from `templates/cloud-protocol.md`, the ticket, its spec and the project's
  rails, rewrites the home path and runs the secret scan over it (the personal list fail-closed), and records
  each dispatch in a ledger under `~/.keel/cloud/` behind a lock. `--check` writes nothing and ends with a
  `cloud-check:` receipt line; `--dispatch` runs `claude --cloud` from the main checkout under a pseudo-terminal
  (the CLI refuses to run without one) and prints the claim to write; `--sweep` lists open tickets with their
  verdicts and every dispatch still without a PR. The protocol has the cloud session clone keel's tools at a
  pinned published commit, install and prove a pre-push guard that allows exactly its `claude/cloud-<slug>`
  branch, and scan before every push. `tools/cloud-land.sh <repo> <PR#>` is the model-free landing check before
  the operator merges: a range scan, a PR-text scan, the added-allow-marker check and a green CI rollup at the
  exact head SHA, for the repository `<repo>`'s origin names and its own default branch.
