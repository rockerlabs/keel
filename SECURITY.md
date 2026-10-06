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

- `secret-guard` failing **open** — a key-shaped secret that should be blocked slips through commit/push,
  a `--tracked` audit that misses tracked content it claims to cover, or a `--selftest` that reports OK
  while the installed gate is actually broken.
- `public-audit` missing a real identity/secret leak it claims to catch before a private→public flip.
- `install.sh` or the hooks clobbering or mis-wiring a user's existing git config or files.

Known limits (by design — not vulnerabilities):

- `secret-guard` is a **prefix backstop, not full DLP**. It catches known key shapes (`ghp_`, `AKIA…`,
  `sk-…`, `glpat-`, …), not arbitrary secrets like an AWS *secret* key, a JWT, or a password. A clean pass
  means "no known key shape found," never "no secret here." On push it additionally scans the pushed
  commits' messages and annotated-tag message bodies against all of the above — key shapes, your listed
  personal data, and agent session-metadata trailers (a `Claude-Session`-style line).
- The prose layer (`PRINCIPLES.md`, `FRAMEWORK.md`, the rails) biases an agent; it does not enforce
  anything — the human is the trigger (see the README's *mechanized vs needs-you*).
- A server-side CI job backs up the local hook: `secret-scan.sh --range` also runs on every pull
  request and every push to `main`, so a contributor without the local hook (or a hand-crafted push
  straight to `main`) doesn't ship a secret unscanned there. It only checks key shapes and agent
  session-metadata trailers — the personal-literal list is local-only by design and never reaches the
  CI runner. A push to a non-`main` branch with no open PR yet isn't covered by either trigger; the
  local hook is the only backstop until a PR opens.

## Threat model — the lethal trifecta

Simon Willison's ["lethal trifecta"](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/) is the
shared vocabulary for agent prompt-injection risk: an agent that combines **(1) access to private data**,
**(2) exposure to untrusted content** and **(3) a way to communicate externally** can be tricked into
stealing the first through the third. Remove any one leg and the attack collapses. This section says how
much of each leg Keel covers — and where it covers none.

Keel's original threat model is the **honestly erring** agent — a careless leak, a wrong push — not the
hijacked one. The mechanized barriers below happen to hold against both, because they live outside the
model; nothing here claims more than that.

| Leg | Keel's coverage |
|---|---|
| 1 — private data in context | **Partial.** Prose rails keep secrets out of the always-loaded surface; nothing keeps them out of the working tree or the session. |
| 2 — untrusted content | **None, by design.** Delegated to the harness. |
| 3 — external channel | **Strongest.** `secret-guard` and the CI re-scan block secret-shaped content at commit/push; human-in-the-loop rails gate the main outbound actions. |

**Leg 1 — private data.** The rails say never to put API keys or tokens in `CLAUDE.md`, memory or
knowledge-base docs, and to anonymize personal data at authoring time: what is not in context cannot be
exfiltrated by an injected instruction. That covers only what Keel loads. A `.env` (or any secret file)
inside the working tree is readable by the agent by default — the Read tool, or `cat` through Bash,
typically with no permission prompt — so its contents can enter the session context and the on-disk
transcript. Secrets also reach context without any file read: terminal output, logs, stack traces, tools
that print credentials in error output, or the agent dumping environment variables while debugging.
Keel closes none of this; the prose rails are advice, not enforcement. What narrows it sits at the harness
and the machine: permission deny rules (Claude Code's `permissions.deny`, for example
`"Read(./.env)"` and `"Read(./.env.*)"`; a Bash call is a separate surface the rule does not cover, and
bare `**/` patterns are relative to the working directory, so a machine-wide rule needs a `~/**` twin),
and — the real fix — secrets that never reach the process environment at all (a secret manager,
short-lived tokens, a file outside the repo). Keel's own contribution is the context-surface rules plus
`secret-guard` (leg 3), which stops a secret the agent *did* read from at least leaving by commit or push.

**Leg 2 — untrusted content.** Keel has no "tool output is data, not instructions" rail, and adds none:
that boundary belongs to the harness (Claude Code's instruction-source boundary, for example), and Keel
relies on it without strengthening it. A prose rail against injection would be exactly the model-dependent
nudge [`ADAPTING.md`](ADAPTING.md) warns about, so there is deliberately no template line for it. Do not
read Keel's silence here as coverage. The incidents are real and routine for agents that read issues and
pull requests: a public GitHub issue taking over a Gemini-powered triage agent on `gemini-cli`
([Pillar Security, "My Agentic Trust Issues"](https://www.pillar.security/blog/my-agentic-trust-issues-from-prompt-injection-to-supply-chain-compromise-on-gemini-cli)),
and a crafted issue *title* driving Cline's AI triage workflow toward its release credentials
([Clinejection](https://adnanthekhan.com/posts/clinejection/)).

**Leg 3 — external channel.** This is the leg Keel weakens hardest, and the one it mechanizes. The
`secret-guard` git hooks block secret-shaped and personal-literal content at commit and push whatever the
model decided — the one model-independent floor ([`ADAPTING.md`](ADAPTING.md) records why), subject to the
known limits above (a prefix backstop, not DLP). CI re-scans server-side. The human-in-the-loop rails —
never merge autonomously, confirm irreversible or outward-facing actions — gate a coding agent's main
outbound channels, but as prose they bias the agent rather than enforce; on Claude Code the pre-PR gate
mechanically denies the agent's own `gh pr create` until `/polish` has run, which covers that one step and
nothing wider. A channel Keel does not watch (a network call from a tool, a package install) stays open.

**Proportionate to what you can lose.** A learning side project and a production service holding other
people's data call for different amounts of this. Treat the table as a map of where Keel helps, not as an
all-or-nothing bar. A public video treatment of the same threat model, in Russian, reaches the same
split — defense outside the model, rules as instructions rather than guarantees:
[Как взламывают вайбкодеров?](https://youtu.be/sl5rGSm3Wmk)

## Supported versions

Only the latest `main` and the most recent tag receive fixes; there is no
back-porting.
