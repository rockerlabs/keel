#!/usr/bin/env bash
# doctor — the secrets-in-the-working-tree floor (dir #631 slice 1): W-SECRETS-EXPOSED (an env-shaped
# file git would commit or already tracks), W-SECRETS-PLAINTEXT (one resting gitignored), W-SECRETS-IGNORE
# (the recipe's ignore rules missing, adopted projects only), and H-DENY-ENV (the Claude Code Read-deny
# globs, --install mode). doctor reads names and git state only — never file content — and a WARN never
# changes the exit code. Each "fires" check has a paired bad sample (quiet / absent) so a build that
# flags every env file, or only `.env`, goes red.
# Fixtures are written by this file: the operator's personal secret-read hook text-matches env-file names
# in a COMMAND LINE, so none of these names ever appears in a Bash command, only in this script.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

doctor="$REPO_ROOT/tools/doctor.sh"
commit() { git -C "$1" -c user.name=t -c user.email=t@example.com commit -qm "$2"; }

# The recipe's ignore snippet (docs/secrets-in-the-working-tree.md) — the four B3 probes pass under it.
SNIP=('.env' '.env.*' '*.env' '!.env.example' '!.env.sample' '!.env.template' '!.env.dist' '!.env.tpl' '!*.example.env')
# fixture [extra .gitignore lines…] — a git repo whose CLAUDE.md is ignored (so no G-* context GAP) and
# whose .gitignore carries the extra lines. Prints its path.
fixture() {
  local d; d="$(new_repo)"
  printf '# ctx\n' > "$d/CLAUDE.md"
  { printf '%s\n' 'CLAUDE.md' '.claude/'; [ "$#" -eq 0 ] || printf '%s\n' "$@"; } > "$d/.gitignore"
  printf '%s' "$d"
}
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-placeholder}" > "$1"; }   # put FILE [CONTENT]
id_line() { printf '%s\n' "$OUT" | grep -F "[$1]" || true; }                      # the finding's line(s)

# --- A1: untracked + unignored env file → WARN, exit 0 ----------------------------------------------
d="$(fixture)"; put "$d/.env" "SENTINEL_A1=hunter2"
run "$doctor" "$d"
check_status "A1: a WARN never fails the audit (exit 0)" 0 "$STATUS"
case "$OUT" in *"  WARN [W-SECRETS-EXPOSED]"*) pass "A1: WARN [W-SECRETS-EXPOSED] for an untracked, unignored env file" ;;
  *) fail "A1: WARN [W-SECRETS-EXPOSED] for an untracked, unignored env file" "not in output: $OUT" ;; esac
check_absent "A1: it is not also PLAINTEXT" "$OUT" "W-SECRETS-PLAINTEXT"
check_absent "A1: no file content in the output" "$OUT" "SENTINEL_A1"

# --- A1b: tracked, although .gitignore lists it → EXPOSED (tracked wins) -----------------------------
d="$(fixture '.env')"; put "$d/.env"
git -C "$d" add -f .env
run "$doctor" "$d"
check_contains "A1b: a tracked env file that .gitignore also lists → EXPOSED" "$OUT" "[W-SECRETS-EXPOSED]"
check_absent "A1b: not also reported as resting-ignored" "$OUT" "W-SECRETS-PLAINTEXT"

# --- A1c: 4 files, first 3 in LC_ALL=C sort order, no content ------------------------------------------
# count_and_first3 OUT-LINE: count 4, the first three paths named, the fourth not.
for kind in exposed plaintext; do
  if [ "$kind" = exposed ]; then d="$(fixture)"; id="W-SECRETS-EXPOSED"; else d="$(fixture '.env' '.env.*')"; id="W-SECRETS-PLAINTEXT"; fi
  put "$d/.env" "SENTINEL_ONE=aaa"; put "$d/.env.one" "SENTINEL_TWO=bbb"; put "$d/.env.three" "SENTINEL_THREE=ccc"
  put "$d/sub/.env.two" "SENTINEL_FOUR=ddd"
  for mode in "" "--all"; do
    run "$doctor" ${mode:+"$mode"} "$d"
    line="$(id_line "$id" | sed 's#/[^ ]*secrets-in-the-working-tree\.md##')"   # a checkout path may carry digits
    case "$line" in *[!0-9]4[!0-9]*) pass "A1c ($kind$mode): the finding states count 4" ;;
      *) fail "A1c ($kind$mode): the finding states count 4" "line: $line" ;; esac
    ok=1; for p in ".env" ".env.one" ".env.three"; do case "$line" in *"$p"*) ;; *) ok=0 ;; esac; done
    [ "$ok" = 1 ] && pass "A1c ($kind$mode): names the first 3 paths in sort order" || fail "A1c ($kind$mode): names the first 3 paths in sort order" "line: $line"
    check_absent "A1c ($kind$mode): the 4th path is not named" "$line" "sub/.env.two"
    check_absent "A1c ($kind$mode): no sentinel reaches the output" "$OUT" "SENTINEL_"
  done
done

# --- A1d: the recipe pointer is an absolute path that resolves, from a cwd outside the checkout -------
for kind in exposed plaintext; do
  if [ "$kind" = exposed ]; then d="$(fixture)"; id="W-SECRETS-EXPOSED"; else d="$(fixture '.env')"; id="W-SECRETS-PLAINTEXT"; fi
  put "$d/.env"
  run bash -c 'cd "$1" && "$2" "$3"' _ "$SANDBOX" "$doctor" "$d"
  ptr="$(id_line "$id" | grep -oE '/[^ ]*docs/secrets-in-the-working-tree\.md' | head -n1 || true)"
  if [ -n "$ptr" ] && [ -f "$ptr" ]; then pass "A1d ($kind): an absolute recipe path that exists, from outside the checkout"
  else fail "A1d ($kind): an absolute recipe path that exists, from outside the checkout" "pointer='$ptr' line: $(id_line "$id")"; fi
done

# --- A2: ignored untracked env file → PLAINTEXT; adopted → "migration unfinished" ----------------------
d="$(fixture '.env')"; put "$d/.env"
run "$doctor" "$d"
check_contains "A2: an ignored plaintext env file → PLAINTEXT" "$OUT" "[W-SECRETS-PLAINTEXT]"
check_absent "A2: not EXPOSED" "$OUT" "W-SECRETS-EXPOSED"
check_absent "A2: not adopted → no 'migration unfinished'" "$(id_line W-SECRETS-PLAINTEXT)" "migration unfinished"
put "$d/.sops.yaml" "creation_rules: []"
run "$doctor" "$d"
check_contains "A2: adopted (.sops.yaml) → says 'migration unfinished'" "$(id_line W-SECRETS-PLAINTEXT)" "migration unfinished"

# --- A3: templates are never flagged -------------------------------------------------------------------
d="$(fixture)"
for f in .env.example .env.sample .env.template .env.dist .env.tpl config.example.env; do put "$d/$f"; done
git -C "$d" add -f .
run "$doctor" "$d"
check_absent "A3: tracked templates → no EXPOSED" "$OUT" "W-SECRETS-EXPOSED"
check_absent "A3: tracked templates → no PLAINTEXT" "$OUT" "W-SECRETS-PLAINTEXT"
d="$(fixture)"; put "$d/.env.example"; put "$d/config.example.env"      # untracked, unignored templates
run "$doctor" "$d"
check_absent "A3: untracked templates → no EXPOSED" "$OUT" "W-SECRETS-EXPOSED"

# --- A4 / A4b: ciphertext secrets.enc.yaml is quiet; a dotenv ciphertext is not --------------------------
d="$(fixture)"; put "$d/secrets.enc.yaml" "KEY: ENC[AES256_GCM,data:x]"
git -C "$d" add -f secrets.enc.yaml
run "$doctor" "$d"
check_absent "A4: tracked secrets.enc.yaml → no EXPOSED" "$OUT" "W-SECRETS-EXPOSED"
check_absent "A4: tracked secrets.enc.yaml → no PLAINTEXT" "$OUT" "W-SECRETS-PLAINTEXT"
d="$(fixture)"; put "$d/secrets.enc.env" "KEY=ENC[x]"
git -C "$d" add -f secrets.enc.env
run "$doctor" "$d"
check_contains "A4b: a tracked dotenv ciphertext named *.env → EXPOSED (D-7: unsupported)" "$OUT" "[W-SECRETS-EXPOSED]"

# --- A5: the path-level accept file ------------------------------------------------------------------
d="$(fixture '.env.local')"
put "$d/.env.development"; put "$d/.env.production"; put "$d/sub/.env.development"; put "$d/.env.local"
git -C "$d" add .env.development .env.production sub/.env.development
mkdir -p "$d/.keel"
printf '%s\n' '# a note' '.env.development   # the dev defaults, committed on purpose' '.env.local' > "$d/.keel/secrets-accept"
run "$doctor" "$d"
line="$(id_line W-SECRETS-EXPOSED)"
check_contains "A5: a tracked, unlisted .env.production still fires" "$line" ".env.production"
check_contains "A5: sub/.env.development is not covered by the line .env.development (exact match)" "$line" "sub/.env.development"
rest="${line//sub\/.env.development/}"
check_absent "A5: the accepted .env.development is hidden (B1)" "$rest" ".env.development"
check_absent "A5: the accepted, ignored .env.local is hidden (B2)" "$OUT" "W-SECRETS-PLAINTEXT"
run "$doctor" --all "$d"
check_absent "A5: --all does not show a path-accepted file (the file is a path list, not an ID accept)" "$(id_line W-SECRETS-EXPOSED | sed 's#sub/\.env\.development##')" ".env.development"

# --- A6 family: the ignore rules, adopted projects only -------------------------------------------------
d="$(fixture)"; put "$d/.sops.yaml" "creation_rules: []"
run "$doctor" "$d"
check_contains "A6: .sops.yaml + no env ignore rules → W-SECRETS-IGNORE" "$OUT" "[W-SECRETS-IGNORE]"
check_contains "A6: it names .env" "$(id_line W-SECRETS-IGNORE)" ".env"
d="$(fixture)"       # not adopted: plain absence of the rules is not flagged
run "$doctor" "$d"
check_absent "A6: not adopted → no W-SECRETS-IGNORE" "$OUT" "W-SECRETS-IGNORE"

d="$(fixture '.env')"; put "$d/.sops.yaml" "creation_rules: []"      # the F13 probes
run "$doctor" "$d"
line="$(id_line W-SECRETS-IGNORE)"
check_contains "A6d: .gitignore = .env only → names .env.local" "$line" ".env.local"
check_contains "A6d: … and secrets.env" "$line" "secrets.env"

d="$(fixture "${SNIP[@]}" '*.yaml')"; put "$d/.sops.yaml" "creation_rules: []"; put "$d/secrets.enc.yaml" "K: ENC[x]"
git -C "$d" add -f secrets.enc.yaml
run "$doctor" "$d"
check_contains "A6b: *.yaml ignored, secrets.enc.yaml TRACKED → W-SECRETS-IGNORE names the ciphertext" "$(id_line W-SECRETS-IGNORE)" "secrets.enc.yaml"

d="$(fixture "${SNIP[@]}")"; put "$d/.sops.yaml" "creation_rules: []"; put "$d/.env"
git -C "$d" add -f .env
run "$doctor" "$d"
check_contains "A6e: adopted + tracked .env + full snippet → EXPOSED" "$OUT" "[W-SECRETS-EXPOSED]"
check_absent "A6e: … and NO W-SECRETS-IGNORE (--no-index reads the rules, not the index)" "$OUT" "W-SECRETS-IGNORE"
d="$(fixture '!.env.example' '.env.*')"; put "$d/.sops.yaml" "creation_rules: []"; put "$d/.env"   # the snippet minus .env and *.env
git -C "$d" add -f .env
run "$doctor" "$d"
check_contains "A6e bad sample: the rule line removed → W-SECRETS-IGNORE names .env" "$(id_line W-SECRETS-IGNORE)" ".env"

d="$(fixture "${SNIP[@]}")"; put "$d/.sops.yaml" "creation_rules: []"; put "$d/secrets.enc.yaml" "K: ENC[x]"
git -C "$d" add -f secrets.enc.yaml
run "$doctor" "$d"
check_absent "A6c: .sops.yaml + the full snippet + tracked ciphertext → no W-SECRETS-IGNORE" "$OUT" "W-SECRETS-IGNORE"
check_absent "A6c: … no EXPOSED" "$OUT" "W-SECRETS-EXPOSED"
check_absent "A6c: … no PLAINTEXT" "$OUT" "W-SECRETS-PLAINTEXT"

# --- A7: each file yields exactly one of EXPOSED / PLAINTEXT ---------------------------------------------
d="$(fixture "${SNIP[@]}")"; put "$d/.sops.yaml" "creation_rules: []"; put "$d/.env"
git -C "$d" add -f .env
run "$doctor" "$d"
check_contains "A7: adopted + tracked .env → EXPOSED" "$OUT" "[W-SECRETS-EXPOSED]"
check_absent "A7: … and not PLAINTEXT" "$OUT" "W-SECRETS-PLAINTEXT"
d="$(fixture "${SNIP[@]}")"; put "$d/.sops.yaml" "creation_rules: []"; put "$d/.env"
run "$doctor" "$d"
check_contains "A7: adopted + ignored .env → PLAINTEXT" "$OUT" "[W-SECRETS-PLAINTEXT]"
check_absent "A7: … and not EXPOSED" "$OUT" "W-SECRETS-EXPOSED"

# --- A8: accept by ID, --all shows it, a rerun is byte-identical --------------------------------------------
d="$(fixture)"; put "$d/.env"
mkdir -p "$d/.keel"; printf '%s\n' 'W-SECRETS-EXPOSED  # accepted on purpose' > "$d/.keel/doctor-accept"
run "$doctor" "$d"; first="$OUT"
check_absent "A8: an accepted ID is hidden" "$OUT" "[W-SECRETS-EXPOSED]"
run "$doctor" "$d"
check_eq "A8: a second run is byte-identical (read-only)" "$first" "$OUT"
run "$doctor" --all "$d"
check_contains "A8: --all shows the accepted finding" "$OUT" "[W-SECRETS-EXPOSED]"
rm -f "$d/.keel/doctor-accept"
run "$doctor" "$d"
check_contains "A8 bad sample: without the accept file it shows" "$OUT" "[W-SECRETS-EXPOSED]"

# --- A9: not a git repo → G-GIT-MISSING only --------------------------------------------------------------------
d="$(mktemp -d "$SANDBOX/nogit.XXXXXX")"; put "$d/.env"; put "$d/.sops.yaml" "creation_rules: []"
run "$doctor" "$d"
check_contains "A9: not a git repo → G-GIT-MISSING speaks" "$OUT" "G-GIT-MISSING"
check_absent "A9: … and no W-SECRETS-* at all" "$OUT" "W-SECRETS-"

# --- A9b: an env file inside a submodule is that repo's to judge ------------------------------------------------------
src="$(new_repo)"; printf '%s\n' '.env' > "$src/.gitignore"; put "$src/readme" "x"
git -C "$src" add -A; commit "$src" init
d="$(fixture)"; put "$d/readme" "x"; git -C "$d" add readme; commit "$d" init
git -C "$d" -c protocol.file.allow=always submodule add -q "$src" sub >/dev/null 2>&1 || true
put "$d/sub/.env"
if [ -f "$d/.gitmodules" ]; then
  run "$doctor" "$d"
  check_absent "A9b: an ignored env file inside a submodule → no W-SECRETS-*" "$OUT" "W-SECRETS-"
else
  fail "A9b: fixture needs a submodule" "git submodule add did not produce .gitmodules"
fi
put "$d/.env"        # the same file in the project proper fires (untracked, unignored)
run "$doctor" "$d"
check_contains "A9b: the same file in the project proper fires" "$OUT" "[W-SECRETS-EXPOSED]"

# --- A9c: a linked worktree is judged against its own top, not skipped ----------------------------------------------------
d="$(fixture)"; put "$d/.env"; put "$d/readme" "x"
git -C "$d" add -f .env readme; commit "$d" init
wt="$SANDBOX/wt-a9c"
git -C "$d" worktree add -q "$wt" -b wt-a9c
run "$doctor" "$wt"
check_contains "A9c: a tracked plaintext .env in a linked worktree → EXPOSED" "$OUT" "[W-SECRETS-EXPOSED]"

# --- A10: H-DENY-ENV in --install mode ------------------------------------------------------------------------------------
h="$SANDBOX/a10-home"
run "$REPO_ROOT/install.sh" --home "$h" --no-hooks
check_status "A10: install fixture ok" 0 "$STATUS"
rm -f "$h/settings.json"
run "$doctor" --install "$h"
line="$(id_line H-DENY-ENV)"
check_contains "A10: no settings.json → H-DENY-ENV fires" "$OUT" "[H-DENY-ENV]"
check_contains "A10: … naming all three rules" "$line" 'Read(**/.env)'
check_contains "A10: … including Read(**/*.env)" "$line" 'Read(**/*.env)'

printf '%s\n' '{"permissions":{"deny":["Read(**/.env)","Read(**/.env.*)"]}}' > "$h/settings.json"
run "$doctor" --install "$h"
line="$(id_line H-DENY-ENV)"
check_contains "A10: two of three → names exactly the missing Read(**/*.env)" "$line" 'Read(**/*.env)'
check_absent "A10: … and not the present Read(**/.env)" "$line" 'Read(**/.env)'
check_absent "A10: … and not the present Read(**/.env.*)" "$line" 'Read(**/.env.*)'

printf '%s\n' '{"permissions":{"deny":["Read(**/.env)","Read(**/.env.*)","Read(**/*.env)"]}}' > "$h/settings.json"
run "$doctor" --install "$h"
check_absent "A10: all three present → absent" "$OUT" "H-DENY-ENV"

# without jq: the grep -F path agrees on both the fires and the quiet half
farm="$(mktemp -d "$SANDBOX/farm.XXXXXX")"; path_farm "$farm" jq
run env PATH="$farm" "$doctor" --install "$h"
check_absent "A10 (no jq): all three present → absent" "$OUT" "H-DENY-ENV"
printf '%s\n' '{"permissions":{"deny":["Read(**/.env)","Read(**/.env.*)"]}}' > "$h/settings.json"
run env PATH="$farm" "$doctor" --install "$h"
check_contains "A10 (no jq): two of three → fires, names the missing one" "$(id_line H-DENY-ENV)" 'Read(**/*.env)'

# unparseable JSON → the grep -F path (the literal text decides)
printf '%s\n' '{ "permissions": { "deny": ["Read(**/.env)", "Read(**/.env.*)"  <<broken' > "$h/settings.json"
run "$doctor" --install "$h"
check_contains "A10 (unparseable JSON): fires through the grep path" "$(id_line H-DENY-ENV)" 'Read(**/*.env)'
check_absent "A10 (unparseable JSON): the present rules are not named" "$(id_line H-DENY-ENV)" 'Read(**/.env)'

# accepted via $ihome/.keel/doctor-accept
printf '%s\n' '{"permissions":{"deny":[]}}' > "$h/settings.json"
mkdir -p "$h/.keel"; printf '%s\n' 'H-DENY-ENV' > "$h/.keel/doctor-accept"
run "$doctor" --install "$h"
check_absent "A10: accepted via \$ihome/.keel/doctor-accept → hidden" "$OUT" "[H-DENY-ENV]"
run "$doctor" --install --all "$h"
check_contains "A10: --all shows it" "$OUT" "[H-DENY-ENV]"
rm -f "$h/.keel/doctor-accept"

# --codex: the deny globs are a Claude Code surface — skipped
ch="$SANDBOX/a10-codex/.codex"
run "$REPO_ROOT/install.sh" --codex --home "$ch" --no-hooks
run "$doctor" --install --codex "$ch"
check_absent "A10: --codex → H-DENY-ENV skipped" "$OUT" "H-DENY-ENV"

summary
