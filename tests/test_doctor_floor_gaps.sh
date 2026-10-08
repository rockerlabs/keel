#!/usr/bin/env bash
# doctor — four holes in the secrets/guard floor (dir #718), each pinned red-then-green:
#   S6-1  the env-file floor prunes build/vendor dirs, so a TRACKED env-shaped file under dist/ or
#         node_modules/ read clean — tracked files are now judged wherever they sit (untracked ones in a
#         pruned dir stay unscanned, on purpose, and that choice is pinned too);
#   S7-9  the stale-guard check compared only secret-scan.sh — pre-push and range-lib.sh drift was silent
#         (the dir #504 re-vendor note is about exactly those); a user's own hook is never compared;
#   S6-3  G-GITIGNORE-CONTEXT fired for a .claude/ whose every file is ignored;
#   S6-9  tools/lib/agent-floor.sh was sourced unguarded at load, so a corrupt copy killed every plain run.
# Fixture file names that look like env files are written by this script, never typed in a command line.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

doctor="$REPO_ROOT/tools/doctor.sh"
gitt="$(type -P git)"
sg="$REPO_ROOT/tools/secret-guard"
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-placeholder}" > "$1"; }   # put FILE [CONTENT]
id_line() { printf '%s\n' "$OUT" | grep -F "[$1]" || true; }
# fixture — a repo whose CLAUDE.md and .claude/ are ignored; prints its path
fixture() {
  local d; d="$(new_repo)"
  printf '# ctx\n' > "$d/CLAUDE.md"
  printf '%s\n' 'CLAUDE.md' '.claude/' > "$d/.gitignore"
  printf '%s' "$d"
}

# --- S6-1: tracked env-shaped files inside the pruned dirs ---------------------------------------------
d="$(fixture)"
put "$d/dist/.env" "SENTINEL_S61=hunter2"; put "$d/node_modules/pkg/prod.env"
put "$d/vendor/.env.example"; put "$d/out/.env.local"; put "$d/target/.env"
"$gitt" -C "$d" add -f dist/.env node_modules/pkg/prod.env vendor/.env.example out/.env.local target/.env
run "$doctor" "$d"
line="$(id_line W-SECRETS-EXPOSED)"
check_contains "S6-1: a tracked env file under dist/ → EXPOSED" "$line" "dist/.env"
check_contains "S6-1: ...and one under node_modules/ → EXPOSED" "$line" "node_modules/pkg/prod.env"
check_contains "S6-1: ...the finding counts all four tracked files (not the template)" "$line" " 4 env-shaped"
check_absent  "S6-1: a tracked template inside a pruned dir stays quiet" "$line" "vendor/.env.example"
check_absent  "S6-1: no file content in the output" "$OUT" "SENTINEL_S61"

# git quotes a non-ASCII path in plain `ls-files` output; the floor must still find it
d="$(fixture)"; put "$d/dist/café/.env"; "$gitt" -C "$d" add -f dist
run "$doctor" "$d"
check_contains "S6-1: a tracked env file under a non-ASCII path in a pruned dir → EXPOSED" "$(id_line W-SECRETS-EXPOSED)" "dist/café/.env"
# a trailing slash on the audited dir must not double-count a tracked file find and git both report
d="$(fixture)"; put "$d/.env"; put "$d/dist/.env"; "$gitt" -C "$d" add -f .env dist/.env
run "$doctor" "$d/"
check_contains "S6-1: a trailing-slash dir argument counts each tracked file once" "$(id_line W-SECRETS-EXPOSED)" " 2 env-shaped"

# a tracked file deleted from the work tree is not a file on disk: quiet, no crash
d="$(fixture)"; put "$d/dist/.env"; "$gitt" -C "$d" add -f dist/.env; rm "$d/dist/.env"
run "$doctor" "$d"
check_status  "S6-1: a tracked-but-deleted env file does not crash the audit" 0 "$STATUS"
check_absent  "S6-1: ...and is not reported (no file there to expose)" "$OUT" "W-SECRETS-EXPOSED"

# the path-level accept list reaches a pruned-dir path too
d="$(fixture)"; put "$d/dist/.env"; "$gitt" -C "$d" add -f dist/.env
mkdir -p "$d/.keel"; printf 'dist/.env\n' > "$d/.keel/secrets-accept"
run "$doctor" "$d"
check_absent  "S6-1: an accepted pruned-dir path is hidden" "$OUT" "W-SECRETS-EXPOSED"

# the disclosed limit: an UNTRACKED env file inside a pruned dir is still not scanned (dependency and
# build trees would drown the floor) — pinned so widening or narrowing it is a deliberate change
d="$(fixture)"; put "$d/dist/.env"; put "$d/node_modules/pkg/prod.env"
run "$doctor" "$d"
check_absent  "S6-1: an untracked env file in a pruned dir stays unscanned (disclosed)" "$OUT" "W-SECRETS-EXPOSED"
check_absent  "S6-1: ...and is not reported as resting plaintext either" "$OUT" "W-SECRETS-PLAINTEXT"

# --- S7-9: the stale check compares every engine file the installer copies ------------------------------
# A vendored dir the repo's core.hooksPath points at, holding Keel's four shipped files: both hooks carry
# Keel's marker line, so both are compared. A case that needs a user's own hook overwrites one with an
# unmarked script (line 2 not Keel's marker), which is then never compared.
vend() {  # vend DIR — a dir holding the four shipped files, byte-identical
  mkdir -p "$1"
  cp "$sg/secret-scan.sh" "$sg/pre-commit" "$sg/pre-push" "$sg/range-lib.sh" "$1/"
  chmod +x "$1/secret-scan.sh" "$1/pre-commit" "$1/pre-push"
}
repo718() {  # a repo with a local hooksPath at vhooks/, prints it
  local r; r="$(fixture)"
  vend "$r/vhooks"; "$gitt" -C "$r" config core.hooksPath vhooks
  printf '%s' "$r"
}
d="$(repo718)"
run "$doctor" "$d"
check_absent  "S7-9: four byte-identical vendored files → no drift finding" "$OUT" "[W-GUARD-STALE]"
printf '\n# drifted\n' >> "$d/vhooks/range-lib.sh"
run "$doctor" "$d"
check_contains "S7-9: range-lib.sh drifted (secret-scan.sh identical) → W-GUARD-STALE" "$OUT" "[W-GUARD-STALE]"
check_contains "S7-9: ...and the finding names the drifted file" "$(id_line W-GUARD-STALE)" "range-lib.sh"
d="$(repo718)"; printf '\n# drifted\n' >> "$d/vhooks/pre-push"
run "$doctor" "$d"
check_contains "S7-9: a Keel pre-push that drifted → W-GUARD-STALE" "$OUT" "[W-GUARD-STALE]"
check_contains "S7-9: ...and the finding names pre-push" "$(id_line W-GUARD-STALE)" "pre-push"
d="$(repo718)"; printf '\n# drifted\n' >> "$d/vhooks/pre-commit"
run "$doctor" "$d"
check_contains "S7-9: a Keel pre-commit that drifted → W-GUARD-STALE" "$OUT" "[W-GUARD-STALE]"
# an engine file ABSENT from a dir that holds a Keel hook: pre-push sources range-lib.sh, so it is broken
d="$(repo718)"; rm "$d/vhooks/range-lib.sh"
run "$doctor" "$d"
check_contains "S7-9: range-lib.sh deleted beside a Keel pre-push → W-GUARD-STALE" "$OUT" "[W-GUARD-STALE]"
check_contains "S7-9: ...and the finding says it is missing" "$(id_line W-GUARD-STALE)" "range-lib.sh (missing"
# ...but only Keel's OWN pre-push sources range-lib.sh: a user's pre-push beside a Keel pre-commit is not broken
d="$(repo718)"; rm "$d/vhooks/range-lib.sh"
printf '#!/bin/sh\n# my own hook\nexit 0\n' > "$d/vhooks/pre-push"; chmod +x "$d/vhooks/pre-push"
run "$doctor" "$d"
check_absent  "S7-9: range-lib.sh absent but the pre-push is the user's own → no finding" "$OUT" "[W-GUARD-STALE]"
# the user's OWN pre-push / pre-commit (no Keel marker line) is theirs, never compared
d="$(repo718)"
printf '#!/bin/sh\n# my own hook\nexit 0\n' > "$d/vhooks/pre-push"; chmod +x "$d/vhooks/pre-push"
printf '#!/bin/sh\n# my own hook\nexit 0\n' > "$d/vhooks/pre-commit"; chmod +x "$d/vhooks/pre-commit"
run "$doctor" "$d"
check_absent  "S7-9: a foreign pre-push / pre-commit is the user's data → no drift finding" "$OUT" "[W-GUARD-STALE]"
# a dir that holds no Keel guard files at all is not "stale"
d="$(fixture)"; mkdir -p "$d/vhooks"; printf '#!/bin/sh\nexit 0\n' > "$d/vhooks/pre-commit"; chmod +x "$d/vhooks/pre-commit"
"$gitt" -C "$d" config core.hooksPath vhooks
run "$doctor" "$d"
check_absent  "S7-9: a hooks dir with only the user's own pre-commit → no drift finding" "$OUT" "[W-GUARD-STALE]"

# the installer's file list and doctor's compare list cannot drift apart silently
isg_list="$(sed -n 's/^isg_files="\([^"]*\)".*/\1/p' "$REPO_ROOT/tools/install-secret-guard.sh")"
doc_list="$(sed -n 's/^[[:space:]]*for f in \(secret-scan\.sh [^;]*\); do$/\1/p' "$doctor")"
check_ne "S7-9: the installer's file list was extracted (a reformat must not blank the pin)" "" "$isg_list"
check_ne "S7-9: doctor's compare list was extracted (a reformat must not blank the pin)" "" "$doc_list"
check_eq "S7-9: doctor compares exactly the files install-secret-guard.sh copies" \
  "$(printf '%s\n' $isg_list | LC_ALL=C sort | tr '\n' ' ')" "$(printf '%s\n' $doc_list | LC_ALL=C sort | tr '\n' ' ')"

# the machine-wide arm: same compare, same file set
gh="$SANDBOX/gfloor-home"; mkdir -p "$gh"; fresh_home_env "$gh"
gdir="$SANDBOX/gfloor-hooks"; vend "$gdir"
env "${FRESH_HOME_ENV[@]}" "$gitt" config --global core.hooksPath "$gdir"
d="$(fixture)"
run env "${FRESH_HOME_ENV[@]}" "$doctor" "$d"
check_absent  "S7-9: a machine-global dir with four identical files → no drift finding" "$OUT" "[W-GUARD-GLOBAL-STALE]"
printf '\n# drifted\n' >> "$gdir/range-lib.sh"
run env "${FRESH_HOME_ENV[@]}" "$doctor" "$d"
check_contains "S7-9: machine-global range-lib.sh drifted → W-GUARD-GLOBAL-STALE" "$OUT" "[W-GUARD-GLOBAL-STALE]"
check_contains "S7-9: ...and the finding names the drifted file" "$(id_line W-GUARD-GLOBAL-STALE)" "range-lib.sh"
vend "$gdir"; printf '\n# drifted\n' >> "$gdir/pre-push"
run env "${FRESH_HOME_ENV[@]}" "$doctor" "$d"
check_contains "S7-9: machine-global Keel pre-push drifted → W-GUARD-GLOBAL-STALE" "$OUT" "[W-GUARD-GLOBAL-STALE]"

# --- S6-3: .claude/ whose every file is ignored is not an open directory ----------------------------------
d="$(new_repo)"; printf '# ctx\n' > "$d/CLAUDE.md"
printf 'CLAUDE.md\n.claude/settings.local.json\n' > "$d/.gitignore"   # ignores the FILE, not the directory itself
put "$d/.claude/settings.local.json" "{}"
run "$doctor" "$d"
check_status  "S6-3: a .claude/ with only ignored files → no GAP (exit 0)" 0 "$STATUS"
check_absent  "S6-3: ...no G-GITIGNORE-CONTEXT" "$OUT" "G-GITIGNORE-CONTEXT"
put "$d/.claude/notes.md" "unignored"                      # one file git would add → the GAP is real
run "$doctor" "$d"
check_contains "S6-3: one unignored file under .claude/ → the GAP still fires" "$OUT" "[G-GITIGNORE-CONTEXT]"
check_contains "S6-3: ...and names .claude/" "$(id_line G-GITIGNORE-CONTEXT)" ".claude/"
d="$(new_repo)"; printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n' > "$d/.gitignore"
mkdir "$d/.claude"                                          # nothing in it at all: still exposed (dir #473's pin)
run "$doctor" "$d"
check_contains "S6-3: an EMPTY unignored .claude/ is still the GAP" "$OUT" "private AI context: .claude/ —"

# --- S6-9: a corrupt agent-floor.sh must not kill a plain run --------------------------------------------
cp_root="$SANDBOX/doctor-copy"; mkdir -p "$cp_root"
for part in tools agents commands docs; do [ -e "$REPO_ROOT/$part" ] && cp -R "$REPO_ROOT/$part" "$cp_root/$part"; done
cdoc="$cp_root/tools/doctor.sh"
d="$(fixture)"
run "$cdoc" "$d"; base_status="$STATUS"
printf 'agent_fm_lines() {\n' > "$cp_root/tools/lib/agent-floor.sh"      # an unterminated function: a syntax error
run "$cdoc" "$d"
check_eq      "S6-9: a plain run with a corrupt agent-floor.sh keeps the intact run's exit status" "$base_status" "$STATUS"
check_absent  "S6-9: ...and prints no raw shell syntax error" "$OUT" "syntax error"
check_contains "S6-9: ...and still reaches its tail summary" "$OUT" "doctor:"
# --install needs the lib: the failure must be a visible finding, not an abort and not silence
dah="$SANDBOX/doctor-copy-home/.claude"
run "$REPO_ROOT/install.sh" --home "$dah" --no-hooks
check_status  "S6-9 fixture: copy install → exit 0" 0 "$STATUS"
run "$cdoc" --install "$dah"
check_absent  "S6-9: --install with a corrupt lib prints no raw syntax error" "$OUT" "syntax error"
check_contains "S6-9: ...and says the reviewer-agent floor could not be judged" "$OUT" "[W-REVIEW-AGENT-FLOOR]"
check_contains "S6-9: ...naming the lib that failed to load" "$(id_line W-REVIEW-AGENT-FLOOR)" "agent-floor.sh"

summary
