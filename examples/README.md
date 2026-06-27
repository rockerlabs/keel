# A 5-minute tour

The fastest way to see Keel's mechanized tools actually work. One command, no setup, nothing
touched on your machine — [`tour.sh`](tour.sh) runs the whole thing inside a throwaway sandbox
(it redirects `HOME` and the global git config into a temp dir and cleans up on exit):

```bash
examples/tour.sh
```

It walks the three run-on-demand tools plus the one fires-by-itself mechanism, end to end:

1. **`init-project`** scaffolds a born-compliant project — git, a `.gitignore` that hides private
   AI context, and a `CLAUDE.md` from the template.
2. **`doctor`** audits the baseline. secret-guard isn't wired yet, so it reports a **WARN**
   (advisory — drift, not a failure).
3. **`install-secret-guard`** wires the hook; a re-audit comes back clean.
4. **`secret-guard`** then **blocks a key-shaped secret on commit** — the only piece that fires by
   itself, with no one remembering to run it.

That arc — *scaffold → audit → fix → the guard catches a real mistake* — is Keel's mechanized layer
in miniature. (The durable layer — `PRINCIPLES.md`, `FRAMEWORK.md`, the `CLAUDE.md` rails — biases a
model when loaded but doesn't enforce itself; see the README's "mechanized vs needs-you" section.)

## What it looks like

Real output from a run (paths abbreviated, and the planted key masked — a live run prints it in full):

```console
== 1. Scaffold a new project ==
   init-project sets up git, a .gitignore that hides private AI context, and a CLAUDE.md.

$ ./tools/init-project.sh /tmp/demo/my-project
  + git initialized
  + .gitignore += CLAUDE.md
  + .gitignore += .claude/
  + .gitignore += .DS_Store
  + .gitignore += .idea/
  + CLAUDE.md created from template

== 2. The generated CLAUDE.md (the thin, always-loaded core) ==
   Edit the placeholders for your project; everything else loads on demand.

$ sed -n 1,10p /tmp/demo/my-project/CLAUDE.md
# my-project
> Per-project always-loaded context. Keep it ≤ ~8–10K tokens; move detail to the on-demand tier ...

== 3. Audit the baseline with doctor ==
   doctor reports drift. secret-guard isn't wired yet, so it flags a WARN (advisory, not a fail).

$ ./tools/doctor.sh /tmp/demo/my-project
● my-project (/tmp/demo/my-project)
  WARN secret-guard not wired (install-secret-guard.sh --global, or vendor into this repo)
doctor: structural baseline OK

== 4. Wire secret-guard into the project ==
   A git hook that blocks key-shaped secrets before they ever reach a commit.

$ ./tools/install-secret-guard.sh /tmp/demo/my-project
secret-guard: vendored into /tmp/demo/my-project

== 5. Re-audit — the secret-guard WARN is gone ==

$ ./tools/doctor.sh /tmp/demo/my-project
● my-project (/tmp/demo/my-project)
doctor: structural baseline OK

== 6. secret-guard blocks a key-shaped secret on commit ==
   A developer accidentally stages an AWS-looking key...

$ git commit -m add config
secret-scan: BLOCKED — key-shaped secret(s) detected:
  config.txt:1:aws_key = "AKIA…REDACTED…"

If this is a legit fixture, add it to .secret-scan-allow or an inline 'secret-scan:allow' — don't weaken the scanner.
   ^ the commit was BLOCKED by the hook, exactly as intended.

== Done ==
```

## Then what?

- Bootstrap it for real on your machine: [`../install.sh`](../install.sh) (see the
  [Quickstart](../README.md#quickstart)).
- The foundation: [`../PRINCIPLES.md`](../PRINCIPLES.md) and [`../FRAMEWORK.md`](../FRAMEWORK.md).
- Run it under another model/harness: [`../ADAPTING.md`](../ADAPTING.md).
