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
tree*: the model is meant to run no commands and read no files — the worked client enforces what it
can (rail 6) — so the bundle you hand it is the whole universe. That's a real limitation, not a
footnote — don't expect it to run anything.

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
- accept `--raw-out FILE` and, on success, write the full raw API response there as JSON — it MAY
  also write it on a failed call, best-effort, for debugging: `--raw-out`'s mere existence is not
  proof of success, only the client's own exit code is;
- exit non-zero on any failure (an auth error, a vendor error, a denied tool call, an oversize
  prompt, an empty or whitespace-only reply) rather than printing a plausible-looking empty answer.

Point `--client` at your own script to reach a different vendor CLI — the leak gate and the
round-dir bookkeeping stay the same either way.

## Usage

```bash
round="$(tools/vendor-review.sh --client tools/vendor-review/agy.sh \
  --system system-prompt.md --bundle bundle.md --label my-review)"
```

Prints the round directory it wrote — exactly one line on stdout, the path, so a script can capture it
(the status sentence goes to stderr; on any failure stdout is empty): `<out>/round-<UTC timestamp>-<label>/`,
holding `raw.json` (the raw API response — read it for anything vendor-specific, like a token-usage figure)
and `reply.md` (the model's reply, unwrapped). `--out` defaults to `$HOME/.keel/vendor-review`
(`<keel state root>/vendor-review`), outside every repo, so a default run leaves nothing in your tree; pass
`--out DIR` (relative to your working directory) to put rounds elsewhere. Replies can quote material from
your bundle, so that directory keeps private text — it is never inside a repo, and nothing prunes it.

A round is refused, never run, when the bundle has no non-whitespace content (exit 2) or when the client
exits 0 with an empty reply (exit 1, round dir kept). `tools/vendor-review/agy.sh` caps the combined prompt
at 185 KiB, and at **131071 bytes on Linux** — the prompt travels as one argument, which Linux caps there
(131072 fails with `E2BIG`); an over-cap prompt is exit 2 before `agy` runs, so chunk the bundle. It needs
the `agy` CLI installed and authenticated on your own machine; the script itself holds no credentials.

## The rails (non-negotiable)

1. **The leak gate is mandatory and has no bypass.** `vendor-review.sh` scans `--system` and
   `--bundle` with [`tools/secret-guard/secret-scan.sh`](../tools/secret-guard/secret-scan.sh)
   before anything is sent, and refuses — printing only the offending path, never the matched
   content — on any hit. There is no `--force` and no `--skip-scan`, and no working-directory
   bypass: the scanner runs from a fresh empty directory, so a `.secret-scan-allow` in your cwd or
   your repo is never read, and the refusal text names no exemption mechanism. A path you hand the
   scanner through its environment (`SECRET_SCAN_PERSONAL_FILE` first among them) is resolved against
   *your* working directory first, so a relative one still finds your personal-literals file. (`tools/audit-packet/export.sh`
   still honours the audited repo's own root allow-list by design — it scans that repo's tracked
   files, where the file is that repo's own human decision.) Anonymize and review the bundle
   yourself; don't rely on the gate as the only check.
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
6. **No tool access is enforced, not assumed** (`agy.sh`). A `permissions.allow` rule in agy's own
   settings (`$HOME/.gemini/antigravity-cli/settings.json`) reaches the headless call and lets the
   model read files outside the bundle — measured, dir #662 — so `agy.sh` refuses (exit 1, agy never
   invoked) while that file carries any rule, or cannot be read or parsed (an unreadable policy is not
   a clean one). The message names the file and the number of rules, never the rules; they may belong to
   other sessions or tools, so changing them is a human's decision. A machine that already has such a
   rule (one added for another tool's file-read mode, say) gets `agy.sh` refusing until it is
   removed; add such a rule per run instead, and take it out after. `agy` also runs from a fresh empty
   directory, never your tree, so it loads no `AGENTS.md` / `GEMINI.md` from there. The guarantee is
   exactly this: those allow-rules are the one grant source checked. agy's MCP servers and plugins are
   not — "no tool access" is a prompt instruction plus these two checks, never an absolute.

## What this leg has actually found

[`docs/delta-audit.md`](delta-audit.md) §11 carries the transferable harness lessons this leg's real
runs have surfaced — a reasoner's reply embedding its JSON object mid-prose, a reasoning model
exhausting its token budget on thinking tokens before producing content, bundling a diff by
coupling rather than by file. [`docs/grooming.md`](grooming.md)'s G6 names it as an optional second
axis inside that same round: run twice on a release plan (2026-09-16, 2026-09-20), it returned
genuine findings a same-family adjudication round had not, on both occasions.
