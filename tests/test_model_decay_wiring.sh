#!/usr/bin/env bash
# test_model_decay_wiring.sh — dir #842 (slice 3, B10): the `[model-decay]` heading marker is only worth
# having while something READS it. Four readers are wired by prose and one flag; each can be deleted
# without any other test noticing, so this file turns the suite red when one goes:
#   (a) docs/verification-economics.md defines the token, once, in a paragraph that links both consumers;
#   (b) docs/grooming.md's G5 section AND commands/groom.md's G5 block each name `--decay` (and
#       `backlog-census.sh --list`) — the groom's release row reports the decay-exposed share;
#   (c) docs/rollout-audit.md's "Running the audit" section names `backlog-census.sh --list all --decay`;
#   (d) tools/self/backlog-census.sh accepts `--decay` (exit 0 on a fixture).
# Assertion (c') — G0 names `accumulate.sh due --owner guards` — is slice 4's, added with its step.
# Each assertion reads ITS OWN section, bounded by the next heading or bold block title, so a paragraph
# moved to a different section turns it red (the MISPLACED mutations below prove it). A check that cannot
# fail proves nothing: every predicate runs against a good and a bad sample before it is trusted.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

ve="$REPO_ROOT/docs/verification-economics.md"
grooming="$REPO_ROOT/docs/grooming.md"
groom_cmd="$REPO_ROOT/commands/groom.md"
rollout="$REPO_ROOT/docs/rollout-audit.md"
census="$REPO_ROOT/tools/self/backlog-census.sh"
SCRATCH_COPY_PREFIX="decay-wiring-copy"

# --- predicates (status 0 = wired) ----------------------------------------------------------------
# h2_section HEADING_PREFIX FILE — the lines after the first line starting with HEADING_PREFIX, up to the
# next `## ` heading (a `### ` sub-heading stays inside the section).
h2_section() {
  awk -v h="$1" '!f && index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$2"
}
# bold_block TITLE_PREFIX FILE — the lines after the first line starting with TITLE_PREFIX, up to the next
# bold block title (`**G<n> — `) or `## ` heading: the shape commands/groom.md's blocks take.
bold_block() {
  awk -v h="$1" '!f && index($0, h) == 1 { f = 1; next } f && (/^\*\*G[0-9]+ — / || /^## /) { exit } f { print }' "$2"
}
# names_all TEXT NEEDLE... — every needle is a fixed substring of TEXT (here-string: no producer pipe).
names_all() {
  local text="$1" needle
  shift
  for needle in "$@"; do
    grep -qF -- "$needle" <<<"$text" || return 1
  done
}

# (a) the token is defined once: exactly one line carries it, in a paragraph that links both consumers
decay_defined() {
  [ "$(grep -cF -- '`[model-decay]`' "$1")" = 1 ] || return 1
  awk -v RS= 'index($0, "`[model-decay]`") && index($0, "(grooming.md)") && index($0, "(rollout-audit.md)") { n++ }
    END { exit !(n == 1) }' "$1"
}
# (b) the groom reads it: the doc's G5 section and the command's G5 block
groom_doc_wired() { names_all "$(h2_section '## G5 — ' "$1")" '--decay' 'backlog-census.sh --list'; }
groom_cmd_wired() { names_all "$(bold_block '**G5 — ' "$1")" '--decay' 'backlog-census.sh --list'; }
# (c) the rollout audit reads it, in its "Running the audit" section (Layer 0 stays free of model behaviour)
rollout_wired() { names_all "$(h2_section '## Running the audit' "$1")" 'backlog-census.sh --list all --decay'; }
# (d) the reader exists: the census takes --decay and exits 0 on a fixture
census_accepts_decay() {
  local fx="$SANDBOX/decay-wiring-fixture.md" rc=0
  printf '### dir #1 — a marked ticket [model-decay] — R2 — → pool\n\nbody\n' > "$fx"
  bash "$1" --decay "$fx" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 0 ]
}

assert_wired() {
  local label="$1"; shift
  if "$@"; then pass "$label"; else fail "$label" "not wired: $* — the reader, or a consumer that names it, is missing or misplaced"; fi
}
assert_unwired() {
  local label="$1"; shift
  if "$@"; then fail "$label" "predicate still passes on the broken sample: $*"; else pass "$label"; fi
}

check_file "docs/verification-economics.md exists" "$ve"
check_file "docs/grooming.md exists" "$grooming"
check_file "commands/groom.md exists" "$groom_cmd"
check_file "docs/rollout-audit.md exists" "$rollout"
check_file "tools/self/backlog-census.sh exists" "$census"

# --- the live tree -----------------------------------------------------------------------------------
assert_wired "(a) docs/verification-economics.md defines \`[model-decay]\` once, linking grooming.md and rollout-audit.md" decay_defined "$ve"
assert_wired "(b) docs/grooming.md G5 names --decay and backlog-census.sh --list" groom_doc_wired "$grooming"
assert_wired "(b) commands/groom.md's G5 block names --decay and backlog-census.sh --list" groom_cmd_wired "$groom_cmd"
assert_wired "(c) docs/rollout-audit.md \"Running the audit\" names backlog-census.sh --list all --decay" rollout_wired "$rollout"
assert_wired "(d) backlog-census.sh accepts --decay (exit 0 on a fixture)" census_accepts_decay "$census"

# --- bad samples: each predicate must turn red, or the assertion above proves nothing -----------------
# (a) a synthetic definition paragraph — the live doc is the good sample above; here the breakages.
d="$SANDBOX/decay-def"
mkdir -p "$d"
good_def='**A ticket that hardens a guard carries
`[model-decay]` in its heading** — a model reads it ([`docs/grooming.md`](grooming.md) G5,
[`docs/rollout-audit.md`](rollout-audit.md)).
'
printf 'Intro.\n\n%s\nOutro.\n' "$good_def" > "$d/good.md"
assert_wired "(a) sanity: the synthetic definition passes" decay_defined "$d/good.md"
printf 'Intro.\n\n**A ticket carries\n`[model-decay]` in its heading** (rollout-audit.md only).\n' > "$d/no-groom-link.md"
assert_unwired "(a) a definition that links only one consumer fails" decay_defined "$d/no-groom-link.md"
printf 'Intro.\n\nNothing about decay here.\n\n[`g`](grooming.md) [`r`](rollout-audit.md)\n' > "$d/absent.md"
assert_unwired "(a) a doc without the token fails" decay_defined "$d/absent.md"
printf 'Intro.\n\n`[model-decay]` named here.\n\n[`g`](grooming.md) and [`r`](rollout-audit.md) in another paragraph.\n' > "$d/split.md"
assert_unwired "(a) the token and the links in different paragraphs fails" decay_defined "$d/split.md"
printf '%s\n%s\n\nA second `[model-decay]` mention.\n' "Intro." "$good_def" > "$d/twice.md"
assert_unwired "(a) the token defined on two lines fails (A14: exactly one)" decay_defined "$d/twice.md"

# (b) the doc's G5 paragraph: deleted, then MISPLACED into G4
g="$(scratch_copy "$grooming" grooming.md)"
delete_line_containing "$g" '--decay'
assert_unwired "(b) docs/grooming.md without the G5 decay paragraph fails" groom_doc_wired "$g"
g="$(scratch_copy "$grooming" grooming.md)"
delete_line_containing "$g" '--decay'
insert_before_line_containing "$g" '## G5 — ' 'The decay share: backlog-census.sh --list TAG --decay.'
assert_unwired "(b) the G5 paragraph moved into G4 fails" groom_doc_wired "$g"

# (b) the command's G5 clause: deleted, then MISPLACED into G3
c="$(scratch_copy "$groom_cmd" groom.md)"
delete_line_containing "$c" '--decay'
assert_unwired "(b) commands/groom.md without the G5 clause fails" groom_cmd_wired "$c"
c="$(scratch_copy "$groom_cmd" groom.md)"
delete_line_containing "$c" '--decay'
insert_before_line_containing "$c" '**G4 — ' 'Decay share: backlog-census.sh --list TAG --decay.'
assert_unwired "(b) the G5 clause moved into G3 fails" groom_cmd_wired "$c"

# (c) the rollout paragraph: deleted, then MISPLACED into Layer 0
r="$(scratch_copy "$rollout" rollout-audit.md)"
delete_line_containing "$r" '--list all --decay'
assert_unwired "(c) docs/rollout-audit.md without the decay paragraph fails" rollout_wired "$r"
r="$(scratch_copy "$rollout" rollout-audit.md)"
delete_line_containing "$r" '--list all --decay'
insert_before_line_containing "$r" '### Layer 1' 'Re-triage: backlog-census.sh --list all --decay.'
assert_unwired "(c) the rollout paragraph moved into Layer 0 fails" rollout_wired "$r"

# (d) a census that does not know the flag fails the predicate
stub="$SANDBOX/census-stub.sh"
printf '#!/usr/bin/env bash\necho "unknown flag: $1" >&2\nexit 2\n' > "$stub"
assert_unwired "(d) a census without --decay fails" census_accepts_decay "$stub"

summary
