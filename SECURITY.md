# Security policy

Keel is an **experimental probe** (pre-1.0): a thin knowledge-base layer plus a few plain-Bash tools
(`secret-guard`, `doctor`, `public-audit`, `install`). The security-relevant surface is those tools and
the git hooks they wire — not a running service.

## Reporting a vulnerability

Please report privately — **don't** open a public issue for a security bug.

- Preferred: open a [private security advisory](https://github.com/rockerlabs/keel/security/advisories/new)
  (GitHub → the repo's **Security** tab → **Report a vulnerability**).
- Include what the flaw lets an attacker do, the affected file/command, and a minimal repro.

Expect a best-effort first response within about a week. As a solo, unfunded probe there is no SLA beyond
that; a fix lands as a normal PR and is noted in [`CHANGELOG.md`](CHANGELOG.md).

## Scope — what counts

In scope:

- `secret-guard` failing **open** — a key-shaped secret that should be blocked slips through commit/push.
- `public-audit` missing a real identity/secret leak it claims to catch before a private→public flip.
- `install.sh` or the hooks clobbering or mis-wiring a user's existing git config or files.

Known limits (by design — not vulnerabilities):

- `secret-guard` is a **prefix backstop, not full DLP**. It catches known key shapes (`ghp_`, `AKIA…`,
  `sk-…`, `glpat-`, …), not arbitrary secrets like an AWS *secret* key, a JWT, or a password. A clean pass
  means "no known key shape found," never "no secret here."
- The prose layer (`PRINCIPLES.md`, `FRAMEWORK.md`, the rails) biases an agent; it does not enforce
  anything — the human is the trigger (see the README's *mechanized vs needs-you*).

## Supported versions

Only the latest `main` and the most recent tag receive fixes; there is no
back-porting.
