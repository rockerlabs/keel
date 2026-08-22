#!/usr/bin/env bash
# init-project — scaffolds a born-compliant project; a second run never clobbers existing files.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

init="$REPO_ROOT/tools/init-project.sh"

# scaffold a fresh project
d="$SANDBOX/fresh-proj"
run "$init" "$d"
check_status "init fresh → exit 0" 0 "$STATUS"
check_dir  "creates a git repo" "$d/.git"
check_file "creates CLAUDE.md" "$d/CLAUDE.md"
check_file "creates .gitignore" "$d/.gitignore"

claude="$(cat "$d/CLAUDE.md")"
check_contains "CLAUDE.md is named for the project" "$claude" "fresh-proj"
check_absent  "placeholder is substituted away" "$claude" "<Project name>"

check_link "creates AGENTS.md as a symlink to CLAUDE.md" "$d/AGENTS.md"
check_status "AGENTS.md symlink points at CLAUDE.md" "CLAUDE.md" "$(readlink "$d/AGENTS.md")"

gi="$(cat "$d/.gitignore")"
check_contains ".gitignore ignores CLAUDE.md" "$gi" "CLAUDE.md"
check_contains ".gitignore ignores AGENTS.md" "$gi" "AGENTS.md"
check_contains ".gitignore ignores .claude/" "$gi" ".claude/"
check_contains ".gitignore ignores the map-drift baseline" "$gi" "/.keel/map-drift-baseline"

# impact tracking is on by default (dir #251): an EXTERNAL store entry is created, nothing inside the
# project's own tree — no .keel/ marker, no impact-related .gitignore line beyond the map-drift one above
d_id="$(cd "$d" && pwd -P | tr '/' '-')"
check_dir "creates the external impact-store entry" "$KEEL_IMPACT_STORE/$d_id"
check_nofile "creates nothing inside the project tree" "$d/.keel/ledger.md"
check_absent ".gitignore gets no impact-log line (nothing left to ignore)" "$gi" "/.keel/impact-events.log"

# idempotency: a second run preserves an edited CLAUDE.md and adds no duplicate .gitignore lines
printf '\nMY-EDIT\n' >> "$d/CLAUDE.md"
before_lines="$(wc -l < "$d/.gitignore")"
run "$init" "$d"
check_status "init re-run → exit 0" 0 "$STATUS"
check_contains "re-run preserves the user edit" "$(cat "$d/CLAUDE.md")" "MY-EDIT"
check_contains "re-run reports CLAUDE.md untouched" "$OUT" "already exists"
check_contains "re-run reports AGENTS.md untouched" "$OUT" "AGENTS.md already exists"
after_lines="$(wc -l < "$d/.gitignore")"
check_status "re-run adds no duplicate .gitignore lines" "$before_lines" "$after_lines"

# a pre-existing AGENTS.md (e.g. a deliberately-authored contributor-facing file) is never clobbered
own="$SANDBOX/own-agents-proj"
mkdir -p "$own"
printf 'a project-authored AGENTS.md\n' > "$own/AGENTS.md"
run "$init" "$own"
check_status "init with a pre-existing AGENTS.md → exit 0" 0 "$STATUS"
check_nolink "pre-existing AGENTS.md stays a regular file" "$own/AGENTS.md"
check_contains "pre-existing AGENTS.md content is preserved" "$(cat "$own/AGENTS.md")" "project-authored"

# a pre-existing AGENTS.md that's a BROKEN symlink (dangling target) is also never clobbered — the
# never-clobber check must key off `-e || -L`, not a plain `-e` that a broken symlink fails
broken="$SANDBOX/broken-agents-proj"
mkdir -p "$broken"
ln -s does-not-exist.md "$broken/AGENTS.md"
run "$init" "$broken"
check_status "init with a broken AGENTS.md symlink → exit 0" 0 "$STATUS"
check_contains "reports the broken symlink untouched" "$OUT" "AGENTS.md already exists"
check_link "broken AGENTS.md symlink is left in place" "$broken/AGENTS.md"
check_status "broken symlink's dangling target is unchanged" "does-not-exist.md" "$(readlink "$broken/AGENTS.md")"

# a missing templates/project-CLAUDE.md means CLAUDE.md is never created — AGENTS.md must NOT be
# symlinked to it either, or the "success" message would describe a dangling symlink. Copy just the
# tool (no templates/ dir alongside it) so the template genuinely doesn't exist for this run.
notpl="$SANDBOX/no-template-run"
mkdir -p "$notpl/tools"
cp "$REPO_ROOT/tools/init-project.sh" "$notpl/tools/init-project.sh"
target="$SANDBOX/no-template-target"
run "$notpl/tools/init-project.sh" --no-register --no-impact "$target"
check_status "init with a missing template → exit 0" 0 "$STATUS"
check_contains "reports the template-not-found warning" "$OUT" "template not found"
check_contains "reports AGENTS.md skipped, not symlinked" "$OUT" "AGENTS.md skipped"
if [ -e "$target/AGENTS.md" ] || [ -L "$target/AGENTS.md" ]; then
  fail "no dangling AGENTS.md symlink when CLAUDE.md was never created" "AGENTS.md exists: $target/AGENTS.md"
else
  pass "no dangling AGENTS.md symlink when CLAUDE.md was never created"
fi

# --help prints usage and exits 0 (a newcomer's reflex must not look like a crash); an unknown flag
# is a usage error, not silently treated as a directory to scaffold.
run "$init" --help
check_status "--help → exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$init" --bogus
check_status "unknown flag → exit 2" 2 "$STATUS"

# auto-registers the scaffolded project in INSTANCE.md (when one exists) — no second command needed
inst="$SANDBOX/INSTANCE.md"; cp "$REPO_ROOT/templates/INSTANCE.md" "$inst"
ap="$SANDBOX/auto-reg-proj"
run env KEEL_INSTANCE="$inst" "$init" "$ap"
check_status "init with a registry → exit 0" 0 "$STATUS"
check_contains "row added to INSTANCE.md" "$(cat "$inst")" "| $ap |"
check_contains "reports the auto-registration" "$OUT" "INSTANCE.md Projects registry"

# --no-register opts out (and a non-existent registry is simply skipped, not fatal)
inst2="$SANDBOX/INSTANCE2.md"; cp "$REPO_ROOT/templates/INSTANCE.md" "$inst2"
np="$SANDBOX/no-reg-proj"
run env KEEL_INSTANCE="$inst2" "$init" --no-register "$np"
check_status "--no-register → exit 0" 0 "$STATUS"
check_absent "--no-register adds no row" "$(cat "$inst2")" "| $np |"

# --no-impact opts out of impact tracking (no external store entry created)
ni="$SANDBOX/no-impact-proj"
run "$init" --no-impact "$ni"
check_status "--no-impact → exit 0" 0 "$STATUS"
ni_id="$(cd "$ni" && pwd -P | tr '/' '-')"
check_nodir "--no-impact creates no store entry" "$KEEL_IMPACT_STORE/$ni_id"

# dir #10 residue (a) / dir #251: scaffolding FROM a linked worktree routes through keel-impact.sh's
# main-top resolution — the store entry it creates must be the SAME one the main checkout resolves to,
# never a worktree-forked one. Build the repo by hand (not via a first init-project run) so the
# worktree starts with no store entry of its own yet.
wbase="$SANDBOX/wt-base-proj"; mkdir -p "$wbase"; git -C "$wbase" init -q
git -C "$wbase" -c user.email=t@keel.invalid -c user.name=t commit -qm init --allow-empty >/dev/null
wt="$SANDBOX/wt-base-proj.wt"
git -C "$wbase" worktree add -q -b wt-branch "$wt" >/dev/null 2>&1
run "$init" --no-register "$wt"
check_status "init from a linked worktree → exit 0" 0 "$STATUS"
wbase_id="$(cd "$wbase" && pwd -P | tr '/' '-')"
check_dir "store entry lands at the main checkout's id" "$KEEL_IMPACT_STORE/$wbase_id"
check_nofile "nothing created inside the worktree's own tree" "$wt/.keel/ledger.md"

# dir #85 (code audit, finding 20): a project name carrying sed/awk replacement metacharacters must
# reach CLAUDE.md verbatim. Under the old `sed "s/<Project name>/$name/"`, `&` spliced the whole match
# back in, so "AT&T-tools" produced the literal "AT<Project name>T-tools" — placeholder and all.
for meta in 'AT&T-tools' 'back\slash-proj' 'a\tb-proj'; do
  d="$SANDBOX/meta-$(printf '%s' "$meta" | tr -c 'A-Za-z0-9' '-')"
  rm -rf "$d"
  run "$init" --no-register "$d/$meta"
  check_status "metachar name '$meta' → exit 0" 0 "$STATUS"
  head1="$(head -1 "$d/$meta/CLAUDE.md" 2>/dev/null || true)"
  check_status "metachar name '$meta' lands verbatim in the heading" "# $meta" "$head1"
  check_absent "metachar name '$meta' leaves no placeholder behind" "$head1" "<Project name>"
done

# dir #85 (code audit, finding 5): ensure_ignore() must not glue its rule onto an unterminated last
# line. This is the MORE exposed half of that fix — it runs six times per init and always against the
# adopter's PRE-EXISTING .gitignore, where keel-impact's appender (pinned in test_keel_impact.sh)
# usually meets a file Keel wrote itself. Found untested by an operator-run /code-review high pass.
bf="$SANDBOX/brownfield-proj"; mkdir -p "$bf"; git -C "$bf" init -q
printf 'node_modules' > "$bf/.gitignore"        # deliberately no trailing newline
run "$init" --no-register --no-impact "$bf"
check_status "init over an unterminated .gitignore → exit 0" 0 "$STATUS"
check_status "the adopter's unterminated rule survives as its own line" \
  "1" "$(grep -c '^node_modules$' "$bf/.gitignore")"
check_status "our first rule lands on its own line" \
  "1" "$(grep -c '^CLAUDE\.md$' "$bf/.gitignore")"
check_absent "the two rules are never concatenated" "$(cat "$bf/.gitignore")" "node_modulesCLAUDE.md"
# ...and only ONE separator is added: the remaining five ensure_ignore calls must not each insert a
# blank line, which is what a guard testing the wrong end of the file would do.
check_status "no blank line is introduced between rules" "0" "$(grep -c '^$' "$bf/.gitignore")"

summary
