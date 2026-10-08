# Secrets in the working tree — SOPS + age, and what `doctor` checks

A plaintext secrets file sitting in your project tree is one `cat` away from a permanent transcript: an
agent that reads it puts the value into a conversation log that is kept, unpruned, long after the session
ends. Keel's secret guard catches key-*shaped* strings at commit and push time; it does not see a
password, an opaque token or a base64 blob, and it never looks at a file that stays untracked. This page
is the recipe for keeping those values out of the tree as plaintext, and the short list of things
`tools/doctor.sh` checks so the recipe does not rot.

It is deliberately small: [SOPS](https://getsops.io) encrypts the file, [age](https://age-encryption.org)
holds the key, and a child process receives the plaintext through `sops exec-env` or `sops exec-file`.
**The agent never decrypts anything; it only ever sees ciphertext.** Both tools are the adopter's own to
install — Keel runs neither, and `doctor` reads no file content.

## How much protection you need

Protection should match what the project can lose. A weekend toy with a throwaway API key does not need
this; a repo holding production database credentials, a payment key or a customer's tokens does. This
recipe is encryption *at rest in the tree*. Read [Limits](#limits) before you decide it is enough.

## Install the tools

SOPS (MPL-2.0) and age (BSD-3-Clause) are separate programs; install both with your package manager or
from their release pages, then check that each runs.

```bash
sops --version
age-keygen --version
```

## Make a key — outside every project tree

The age private key must live outside every project directory. A key kept next to the ciphertext
recreates the original problem in a worse form, and `doctor` cannot see it.

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

`age-keygen` prints the matching public key (starts with `age1`); keep it for the next step. SOPS looks
for the key through `SOPS_AGE_KEY_FILE`, then `SOPS_AGE_KEY` and `SOPS_AGE_KEY_CMD`, and otherwise at a
default `keys.txt` under your user config directory (on macOS,
`$HOME/Library/Application Support/sops/age/keys.txt`). Pointing `SOPS_AGE_KEY_FILE` at the file you just
made works on every platform:

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

## Tell SOPS which key to use

A `.sops.yaml` at the project root names the key for the ciphertext file. Its presence is also the signal
`doctor` uses to know you have adopted this recipe.

```yaml
creation_rules:
  - age: age1yourpublickeygoeshere
    path_regex: secrets\.enc\.yaml$
```

Several recipients go in one comma-separated `age:` value.

## The ciphertext file

The ciphertext is **`secrets.enc.yaml`**, committed to the repository, with **flat top-level keys** — one
`NAME: value` pair per secret, no nesting (`exec-env` refuses a nested value). It is YAML on purpose: a
file named `*.env` would match the Read-deny globs below, and the agent could then not read even the
ciphertext.

Creating and editing it is a **human action, in your own terminal** — never the agent's. `sops edit`
opens your `$EDITOR` on the decrypted text and writes ciphertext back when you save:

```bash
sops edit secrets.enc.yaml
```

Add one line per secret, in the editor, as `NAME: value`.

## Ignore the plaintext names

The recipe's ignore rules keep every conventional plaintext name out of git while leaving committed
templates committable. Add them to the project's `.gitignore`:

```gitignore
.env
.env.*
*.env
!.env.example
!.env.sample
!.env.template
!.env.dist
!.env.tpl
!*.example.env
```

`secrets.enc.yaml` must **not** be ignored (a rule like `*.yaml` would silently keep the ciphertext out
of git). `doctor` checks, once `.sops.yaml` exists, that `.env`, `.env.local` and `secrets.env` are
ignored and `secrets.enc.yaml` is not; it checks only those four names.

## Run a program with the secrets

`sops exec-env` is the interface. It decrypts, puts each top-level key into the environment of one child
process, and runs it; the plaintext exists only in that process. The command you pass must be your
program, not something that prints its environment.

```bash
sops exec-env secrets.enc.yaml './run-my-app'
```

For a program that wants a file rather than variables, `sops exec-file` hands the decrypted contents over
as a file whose path replaces `{}`. Without `--output-type` the file is written in the input format —
YAML — so give a dotenv consumer `--output-type dotenv`:

```bash
sops exec-file --output-type dotenv secrets.enc.yaml './import-config --file {}'
```

By default the file is an in-memory FIFO: the plaintext never touches the disk, and the child can read it
**once** — a second read blocks. `--no-fifo` (an `exec-file` flag; `exec-env` has none) uses a temporary
file instead, which tolerates a program that reads twice at the cost of plaintext on disk for the run.

Upstream's own examples for these commands print the secrets (an `echo` of a variable, a `cat` of the
file). Do not copy them: a printed value lands in the transcript, which is the thing this recipe exists
to prevent.

## Keep the agent off the plaintext names

In Claude Code, deny the Read tool on env files in your user settings (`~/.claude/settings.json`):

```json
{
  "permissions": {
    "deny": ["Read(**/.env)", "Read(**/.env.*)", "Read(**/*.env)"]
  }
}
```

`tools/doctor.sh --install` reports `H-DENY-ENV` when any of the three is missing. A `Read` deny narrows
the Read tool only — see [Limits](#limits).

## Migrating an existing env file

Do this yourself, in your own terminal. Start with the key, `.sops.yaml` and ignore rules above, then
convert. `sops encrypt` chooses its creation rule from the *input* file name, so a source named `.env`
needs `--filename-override`, and a dotenv source needs `--input-type dotenv` with YAML out:

```bash
sops encrypt --filename-override secrets.enc.yaml --input-type dotenv --output-type yaml .env > secrets.enc.yaml
```

Check the result by running your program through `exec-env` — not by printing anything:

```bash
sops exec-env secrets.enc.yaml './run-my-app'
```

Then delete the plaintext file, and commit `secrets.enc.yaml`. If the plaintext file was ever tracked or
pushed, rotating every secret in it is not optional: deleting it does not remove it from history.
`doctor` reports `W-SECRETS-PLAINTEXT` ("migration unfinished") for as long as a plaintext copy rests
beside your `.sops.yaml`.

A plain YAML file with flat keys does not need the type flags; `sops encrypt --in-place` with a matching
creation rule encrypts it where it stands.

## Rotation

Rotate the age key whenever a machine that held it is lost, or on a schedule you choose.

**Step 1 — add the new key.** Make a new key (`age-keygen -o`), add its public key to the `age:` value in
`.sops.yaml` next to the old one, and re-wrap the file for both:

```bash
sops updatekeys --yes secrets.enc.yaml
```

**Step 2 — drop the old key.** Confirm the new key works (run the program through `exec-env` with
`SOPS_AGE_KEY_FILE` pointing at the new key), delete the old public key from `.sops.yaml`, and re-wrap
again:

```bash
sops updatekeys --yes secrets.enc.yaml
```

Optionally rotate the data key too:

```bash
sops rotate --in-place secrets.enc.yaml
```

**Step 3 — rotate the secrets themselves.** Any secret that ever sat in plaintext on a shared disk, in a
transcript, or in git history must be rotated at its source. A re-encrypted file protects the future, not
the copies that already exist: anyone holding the old key and an old commit can still read what that
commit contained.

## What `doctor` checks

`tools/doctor.sh` reads names and git state only — never file content — and these are advisories: they
never change its exit code. Each can be accepted by ID in `.keel/doctor-accept`.

| ID | Fires when |
|---|---|
| `W-SECRETS-EXPOSED` | an env-shaped file (`.env`, `.env.*`, `*.env`; templates excluded) is tracked, or untracked and not ignored |
| `W-SECRETS-PLAINTEXT` | an env-shaped file rests untracked and gitignored — plaintext still on disk |
| `W-SECRETS-IGNORE` | `.sops.yaml` exists but the ignore rules above are missing |
| `H-DENY-ENV` | (`--install`, Claude Code only) a Read-deny glob above is missing from your user settings |

A file you keep on purpose (a committed `.env.development` of harmless defaults) is accepted **by exact
path** — one path per line, `#` comments, relative to the project root — in `.keel/secrets-accept`. That
file is per-checkout and gitignored, because committing it would publish a list of plaintext-secret paths;
a fresh clone warns again until you recreate it.

## Limits

- **Honest threat model.** This is a speed bump against the honestly erring agent — one that would read a
  secrets file by accident or habit — and nothing against a hijacked one that is trying to get the value.
- **Key on disk.** The age private key sits on the same disk, readable by the same user, so a decrypt is
  one command for anything running as you; keep the key outside every project tree, where `doctor`
  cannot check it.
- **Other channels.** Environment dumps, `-- env`, a verbose failure or a stack trace that prints a
  variable all stay open: this is encryption at rest, not context hygiene.
- **Transcripts.** Retention of past transcripts is out of scope here; a value that was ever in plaintext
  and ever read by an agent may already be in one.
- **Build and dependency trees.** `doctor` does not walk `dist/`, `build/`, `out/`, `vendor/`, `target/`,
  `node_modules/`, `.build/`, `.gradle/` or `.claude/` looking for env-shaped files, so a plaintext one
  that is untracked there is not reported. A file **git tracks** is judged wherever it sits, those
  directories included.
- **Names, not content.** `doctor` checks file names and git state, never what a file holds — a secret in
  a file with an ordinary name is invisible to it.
- **Read deny covers Read only.** The deny globs stop the Read tool; shell verbs such as `cat` stay open,
  and a Bash hook that blocks them is yours to build for your own machine.
- **Scanner and ciphertext.** The secret guard passes SOPS ciphertext except by chance (the rate for its
  key-shaped patterns is far below one in ten thousand for a typical secrets file), and its personal-literal
  check can match random base64 when your literal is short; a `path:` line in `.secret-scan-allow` for the
  ciphertext file is the escape.

## Why not the alternatives

| Option | Why it is not the recipe |
|---|---|
| bare `age` | encrypts a file but has no run-a-command-with-the-secrets interface, so you would write and maintain the wrapper yourself |
| `gopass` | a separate GPG password store, not ciphertext kept inside the project tree — you lose one reviewed copy next to the code |
| `op run` (1Password) | proprietary and needs a 1Password account |
