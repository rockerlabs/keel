# Rollout audit — checking that a model or harness upgrade didn't break your pipeline

A prose-driven pipeline (a command a model reads and executes step by step) can't be unit-tested the way
its code can. That's fine while the environment underneath it holds still — but a model upgrade or a
harness update can silently change what that prose can actually do: a skill your pipeline depends on stops
being invocable, a hook that used to fire quietly stops firing, or a rule that used to resolve one way now
resolves the other. Nothing crashes. The next symptom is a human noticing something looks off, days later,
and reading a session transcript to find out why.

This is the checklist for closing that gap: instead of waiting for the next symptom, audit the pipeline
itself, on purpose, right after any rollout — a new model, a new harness version, even an upgrade you'd
otherwise treat as strictly better.

**The generalizing insight:** a stronger model does not uniformly help. It tends to **re-weight
rule-following** — resolving an ambiguous or conflicting instruction more literally than a weaker model
did. That turns pre-existing wording debt (a rule two files disagree on, a stale assumption that some
capability is always available) into a visible behaviour change, on a day nobody touched the prose. Treat
every rollout — including a plain upgrade — as a trigger for this audit, not only a downgrade or a
provider switch.

## The three layers

Split the check by how mechanizable it is. Each layer only matters once the one above it is clean — no
point scenario-probing a rail whose test suite is red.

### Layer 0 — mechanized floor (minutes, fully deterministic)

Everything here is a script or a test run; none of it depends on model behaviour.

- Run the full test suite. Green.
- Run your linters (`shellcheck`, or your stack's equivalent). Clean.
- Run the project's own structural self-audit, if it has one. Clean.
- **Live-probe your enforcement guards in a sandbox**, not just their unit tests: feed a fake secret
  through the commit path and confirm it's blocked; feed a gate-guarded action through without the
  evidence it requires and confirm it's denied. A guard that only "passes its own test file" hasn't been
  shown to fire against the real integration point. Isolate the probe's environment (a throwaway `HOME`,
  a throwaway repo) — a live-verification run that writes into the real one can break the machine's own
  tooling, which is exactly what this rule exists to prevent.
- **Carve-out: a read-only read of the machine's own configuration is exempt from that isolation** — run
  it against the real environment. Isolation is there so a live probe cannot *write* over real state; a
  check that only *reads* (`git config --global core.hooksPath`, to see whether a guard is wired at all)
  has nothing to damage. Worse, isolating it inverts the answer: under a redirected `HOME` the check
  reads the sandbox's empty config and reports "not wired" for a machine that is fully guarded. Treat a
  wired-or-not verdict produced under an isolated `HOME` as no verdict at all, and expect your own
  diagnostics to say when a finding is `HOME`-sensitive.

A clean Layer 0 narrows the search: anything actually broken lives above this floor, not in it.

### Layer 1 — harness integration (empirical, once per session)

This layer can't be scripted into a CI job, because it depends on the live harness — but it's still a
yes/no fact, not a judgment call, so establish it by trying the thing, never by reading a config file or a
capability listing.

- **For every hook your pipeline wires** (pre-commit, a pre-tool-use gate, a session-start check —
  whatever your harness offers): trigger it and read the result. A hook that's configured but silently
  stopped firing is indistinguishable from one that was never wired, until you make it fire.
- **For every skill or subcommand a pipeline step depends on:** verify it is both listed as available
  *and* actually callable — by attempting the call, not by reading the listing. A capability can appear in
  a menu and still refuse invocation; only the attempt surfaces that, and a pipeline step that silently
  falls back to "do it inline instead" on a refusal is exactly the failure this layer exists to catch.

### Layer 2 — model-behaviour rails (the only fuzzy layer)

This is genuinely empirical: for each rail in your pipeline that has a known failure mode (a stop-and-ask
point, a rule meant to prevent a specific shortcut), run one scenario probe with an artifact you can check
afterwards — a real end-to-end cycle of the pipeline against a trivial, disposable change, checked against
a written checklist of what should happen at each step (which points should stop and ask, which should run
automatically, what should get written where).

Every deviation from the checklist is a finding, and every finding gets written down as its own ticket —
never left as a chat-only observation. A rail that silently resolved differently than intended is worth
nothing to the next rollout's audit if this one didn't record it.

## Running the audit

The audit itself is read-only: don't repair anything in place mid-sweep, even when a fix looks obvious —
finish the sweep, then let the fixes queue normally like any other finding. Log, dated, what you checked
(the actual surfaces — which hooks, which skills, which rails) and the verdict per layer. That log is the
baseline the *next* rollout's audit diffs against; a sweep that doesn't name its surfaces reads as "checked
everything" even when it only checked a few.

See also: [`FRAMEWORK.md`](../FRAMEWORK.md)'s "Verify gates" section for the mechanism behind a pipeline's
own done-claim enforcement (the thing Layer 0's guard-probe is checking), and its "Enforcement mechanics"
section for why a guard's own error text should never teach the way around it.
