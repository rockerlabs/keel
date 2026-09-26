# Vendor review: a scriptable cross-vendor reading leg

Every behavioural defect the audit record has caught in shipped code was found by a **cross-vendor**
reader — a different model family than the one that wrote or reviewed the change — after same-family
sessions had already read the files clean ([`docs/verification-economics.md`](verification-economics.md)
§5, [`docs/delta-audit.md`](delta-audit.md) §11). This doc ships the scriptable half of that leg: a
thin orchestrator, [`tools/vendor-review.sh`](../tools/vendor-review.sh), plus a swappable client
script per vendor CLI — [`tools/vendor-review/agy.sh`](../tools/vendor-review/agy.sh), for Google's
Antigravity CLI (`agy`, reaching Gemini and the other non-Claude models it hosts), ships as the
worked example. [`docs/drydock.md`](drydock.md)'s "The external leg" covers the other shape: a
vendor reachable only through a person's own account and UI, with no API and no CLI, via
`tools/audit-packet/`.

**Built for one use, and it generalizes.** This leg was built for a groom's G6 adjudication round
([`docs/grooming.md`](grooming.md)) — reading a release plan through a genuinely different model
vendor, not just a fresh context window. It generalizes as *a reviewer over TEXT, not over the
tree*: the model runs no commands and reads no files, so the bundle you hand it is the whole
universe. That's a real limitation, not a footnote — don't expect it to run anything.

## Two proven bundle shapes

- **Plan / ticket adjudication** — a groom's G6 round, or any backlog/spec review: the ticket
  bodies in scope, the plan section, and whatever live tool output the plan's own claims cite (a
  census, a report's relevant excerpt).
- **Per-PR / per-diff review** — `git diff` of the change, the ticket body, the touched files' test,
  and any convention the diff has to respect. On small, dense, security- or correctness-critical
  diffs this shape has repeatedly returned real bugs a same-session same-family review missed —
  never a guaranteed hit; the re-verify-live rail below is what makes the difference between a real
  finding and a plausible-sounding false one.

## The contract

`tools/vendor-review.sh` never calls a vendor's API itself — it leak-gates a bundle, then hands it
to a `--client` script that does. A new vendor is a new client, never a rewrite of the orchestrator.
A client script must:

- read the user message on stdin;
- accept an optional system prompt via `--system FILE`;
- print the model's reply to stdout;
- accept `--raw-out FILE` and, on success, write the full raw API response there as JSON;
- exit non-zero on any failure (an auth error, a vendor error, a denied tool call, an oversize
  prompt) rather than printing a plausible-looking empty answer.

Point `--client` at your own script to reach a different vendor CLI — the leak gate and the
round-dir bookkeeping stay the same either way.

## Usage

```bash
tools/vendor-review.sh --client tools/vendor-review/agy.sh \
  --system system-prompt.md --bundle bundle.md --label my-review --out private/audit-harness/out
```

Prints the round directory it wrote: `<out>/round-<UTC timestamp>-<label>/`, holding `raw.json`
(the raw API response — read it for anything vendor-specific, like a token-usage figure) and
`reply.md` (the model's reply, unwrapped). `tools/vendor-review/agy.sh` needs the `agy` CLI
installed and authenticated on your own machine; the script itself holds no credentials.

## The rails (non-negotiable)

1. **The leak gate is mandatory and has no bypass.** `vendor-review.sh` scans `--system` and
   `--bundle` with [`tools/secret-guard/secret-scan.sh`](../tools/secret-guard/secret-scan.sh)
   before anything is sent, and refuses — printing only the offending path, never the matched
   content — on any hit. There is no `--force` and no `--skip-scan`. Known limitation, shared with
   every other caller of the scanner's file-list mode (`tools/audit-packet/export.sh` included): an
   `.secret-scan-allow` entry in the caller's working directory applies unconditionally here, with
   none of the same-change-provenance baseline check `--range` mode applies — an allowlist entry
   added for an unrelated fixture would silently exempt a real match too. Anonymize and review the
   bundle yourself; don't rely on the gate as the only check.
2. **Anonymize before assembling the bundle.** Real machine paths, names, and other personal
   literals don't belong in a payload leaving the machine, gate or no gate — the gate is a
   backstop, not the first line of defense.
3. **Trim by whole section, never by line length or line count.** A record's own marker (a status
   note, a `CHUNK-END` line) can sit at a line's tail; a length- or line-count cap that lands
   mid-line or mid-record turns a real record into an artifact the model then "finds" as a defect
   that isn't there. Drop whole sections instead.
4. **Run your own doc tests / doctor pass before this leg, not after.** A round spent on a defect
   your own mechanical checks would have caught for free is a wasted round.
5. **Re-verify every finding live before accepting it.** The bar is the channel that produced a
   finding, never the vendor's own confidence — run the code, read the source, reproduce the claim.
   A vendor round has miscounted its own bundle's data and cited a version that doesn't exist; the
   same leg has also found real bugs same-family reviews missed. Treat every finding as a claim to
   check, not a verdict to accept.

## What this leg has actually found

[`docs/delta-audit.md`](delta-audit.md) §11 carries the transferable harness lessons this leg's real
runs have surfaced — a reasoner's reply embedding its JSON object mid-prose, a reasoning model
exhausting its token budget on thinking tokens before producing content, bundling a diff by
coupling rather than by file. [`docs/grooming.md`](grooming.md)'s G6 names it as an optional second
axis inside that same round: run twice on a release plan (2026-09-16, 2026-09-20), it returned
genuine findings a same-family adjudication round had not, on both occasions.
