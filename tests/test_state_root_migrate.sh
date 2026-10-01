#!/usr/bin/env bash
# tools/state-root-migrate.sh — the dir #637 PR2 move: keel's impact and read-trace stores go from
# the harness home (${KEEL_HOME:-$HOME/.claude}/.keel/NAME) to $HOME/.keel/NAME, one compat symlink
# left per moved entry. Spec: docs/specs/637-state-root-home-keel.md A8 (a)-(m).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

MIG="$REPO_ROOT/tools/state-root-migrate.sh"
TOOL="$REPO_ROOT/tools/keel-impact.sh"
check_file "tools/state-root-migrate.sh exists" "$MIG"
# shellcheck source=tools/lib/impact-store.sh
. "$REPO_ROOT/tools/lib/impact-store.sh"

# mig HOME [ARG…] — run the tool with HOME=$1, no store override and no KEEL_HOME ambient, so one
# case's expectations never depend on the harness's sandbox defaults (test (m) sets them on purpose).
mig() {
  local h="$1"; shift
  run env -u KEEL_IMPACT_STORE -u KEEL_READ_TRACE_STORE -u KEEL_HOME HOME="$h" bash "$MIG" "$@"
}
# sums DIR — a stable content fingerprint of every file under DIR (path + cksum), for byte-identity checks.
sums() { (cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }
# mk_entry DIR — a store entry with a couple of files and a subdirectory.
mk_entry() { mkdir -p "$1/sub"; printf 'ledger %s\n' "$1" > "$1/ledger.md"; printf 'x\n' > "$1/sub/f"; }

# --- (a) two legacy entries → moved, links left, bytes identical, exit 0 --------------------------------
ha="$SANDBOX/ma"; mkdir -p "$ha/.claude/.keel/impact" "$ha/.claude/.keel/read-trace"
mk_entry "$ha/.claude/.keel/impact/-p-one"
mk_entry "$ha/.claude/.keel/read-trace/-p-two"
mk_entry "$ha/.claude/.keel/impact/.dotted"   # dot-names are entries too
before_i="$(sums "$ha/.claude/.keel/impact/-p-one")"
before_r="$(sums "$ha/.claude/.keel/read-trace/-p-two")"
mig "$ha"
check_status "(a) exit 0" 0 "$STATUS"
check_contains "(a) the summary counts 3 moved" "$OUT" "moved 3, kept 0"
check_eq "(a) impact entry bytes identical at the new address" "$before_i" "$(sums "$ha/.keel/impact/-p-one")"
check_eq "(a) read-trace entry bytes identical at the new address" "$before_r" "$(sums "$ha/.keel/read-trace/-p-two")"
check_dir "(a) the dot-named entry moved" "$ha/.keel/impact/.dotted"
check_link "(a) a compat link is left at the old impact address" "$ha/.claude/.keel/impact/-p-one"
check_link "(a) ...and at the old read-trace address" "$ha/.claude/.keel/read-trace/-p-two"
check_link "(a) ...and for the dot-named entry" "$ha/.claude/.keel/impact/.dotted"
check_eq "(a) the link reaches the new address" "$ha/.keel/impact/-p-one" "$(cd "$ha/.claude/.keel/impact/-p-one" && pwd -P | sed "s|^$(cd "$ha" && pwd -P)|$ha|")"

# --- (b) re-run → nothing to migrate, exit 0 ----------------------------------------------------------
mig "$ha"
check_status "(b) re-run exit 0" 0 "$STATUS"
check_contains "(b) re-run says nothing to migrate, naming the harness home" "$OUT" "nothing to migrate from $ha/.claude"

# --- (c) a conflict is left byte-untouched, reported with a cwd-correct hint, exit 1 -----------------------
hc="$SANDBOX/mc"; mkdir -p "$hc/.claude/.keel/impact" "$hc/.claude/.keel/read-trace" "$hc/.keel/impact" "$hc/.keel/read-trace"
mk_entry "$hc/.claude/.keel/impact/-p-both"; printf '/some/origin/path\n' > "$hc/.claude/.keel/impact/-p-both/origin"
mk_entry "$hc/.keel/impact/-p-both"
mk_entry "$hc/.claude/.keel/impact/-p-solo"
mk_entry "$hc/.claude/.keel/read-trace/-p-rt"
mk_entry "$hc/.keel/read-trace/-p-rt"
legacy_before="$(sums "$hc/.claude/.keel/impact/-p-both")"
mig "$hc"
check_status "(c) a conflict → exit 1" 1 "$STATUS"
check_eq "(c) the conflicting legacy entry is byte-untouched" "$legacy_before" "$(sums "$hc/.claude/.keel/impact/-p-both")"
check_nolink "(c) ...and is still a real directory" "$hc/.claude/.keel/impact/-p-both"
check_contains "(c) reported as kept" "$OUT" "kept $hc/.claude/.keel/impact/-p-both"
check_contains "(c) the impact hint names a cd into the entry's origin" "$OUT" 'cd "/some/origin/path"'
check_contains "(c) ...and the restore verb" "$OUT" "keel-impact.sh restore"
check_link "(c) the non-conflicting entry moved anyway" "$hc/.claude/.keel/impact/-p-solo"
check_contains "(c) a read-trace conflict gets the merge-by-hand hint" "$OUT" "merge by hand"
check_contains "(c) the summary counts the kept entries" "$OUT" "kept 2"

# --- (d) --dry-run changes nothing, prints the plan -----------------------------------------------------
hd="$SANDBOX/md"; mkdir -p "$hd/.claude/.keel/impact"; mk_entry "$hd/.claude/.keel/impact/-p-d"
listing_before="$(cd "$hd" && find . | LC_ALL=C sort)"
mig "$hd" --dry-run
check_status "(d) --dry-run exit 0" 0 "$STATUS"
check_eq "(d) the find listing is unchanged" "$listing_before" "$(cd "$hd" && find . | LC_ALL=C sort)"
check_contains "(d) the plan names the entry" "$OUT" "-p-d"
check_contains "(d) the plan says it would move" "$OUT" "would move"

# --- (e) HOME unset → one line, exit 0 ----------------------------------------------------------------------
run env -u HOME -u KEEL_HOME bash "$MIG"
check_status "(e) HOME unset → exit 0" 0 "$STATUS"
check_eq "(e) HOME unset → the exact line" "state-root-migrate: HOME unset — nothing migrated" "$OUT"

# --- (f) a file child and a symlink child are skipped ------------------------------------------------------
hf="$SANDBOX/mf"; mkdir -p "$hf/.claude/.keel/impact" "$hf/elsewhere"
printf 'not an entry\n' > "$hf/.claude/.keel/impact/stray-file"
ln -s "$hf/elsewhere" "$hf/.claude/.keel/impact/stray-link"
mig "$hf"
check_status "(f) exit 0" 0 "$STATUS"
check_contains "(f) nothing to migrate" "$OUT" "nothing to migrate"
check_file "(f) the file child is untouched" "$hf/.claude/.keel/impact/stray-file"
check_nodir "(f) nothing was created at the new address" "$hf/.keel/impact/stray-file"
check_absent "(f) the file and link children are not mentioned" "$OUT" "stray"

# --- (g) --from a second home lands in the same root; the default FROM follows KEEL_HOME ---------------------
hg="$SANDBOX/mg"; mkdir -p "$hg/second/.keel/impact" "$hg/kh/.keel/impact"
mk_entry "$hg/second/.keel/impact/-p-g1"; mk_entry "$hg/kh/.keel/impact/-p-g2"
mig "$hg" --from "$hg/second"
check_dir "(g) --from: moved into \$HOME/.keel" "$hg/.keel/impact/-p-g1"
check_link "(g) --from: link left in the second home" "$hg/second/.keel/impact/-p-g1"
run env -u KEEL_IMPACT_STORE -u KEEL_READ_TRACE_STORE KEEL_HOME="$hg/kh" HOME="$hg" bash "$MIG"
check_dir "(g) default FROM = KEEL_HOME: moved into the same root" "$hg/.keel/impact/-p-g2"
check_link "(g) ...and its link left under KEEL_HOME" "$hg/kh/.keel/impact/-p-g2"

# --- (h) a read-trace entry with *.archive and wrap-fuse/ arrives intact ----------------------------------------
hh="$SANDBOX/mh"; rt="$hh/.claude/.keel/read-trace/-p-h"; mkdir -p "$rt/wrap-fuse"
printf 'r\n' > "$rt/reads.log"; printf 'a\n' > "$rt/reads.log.1.archive"; printf 'b\n' > "$rt/reads.log.2.archive"
printf 'f\n' > "$rt/wrap-fuse/main.flag"; printf 'e\n' > "$rt/wrap-fuse-events.log"
h_before="$(sums "$rt")"
mig "$hh"
check_eq "(h) every file, archives and wrap-fuse/ included, is byte-identical after the move" "$h_before" "$(sums "$hh/.keel/read-trace/-p-h")"

# --- (i) the drill: the entry survives losing the harness home ---------------------------------------------------
hi="$SANDBOX/mi"; mkdir -p "$hi"; repo_i="$(new_repo)"
# Pre-create the legacy root FIRST, so `enable` lands there (rung 3) — in a fresh sandbox it would
# otherwise land at the new address and this drill would prove nothing.
mkdir -p "$hi/.claude/.keel/impact"
(cd "$repo_i" && impact_isolated "$hi" bash "$TOOL" enable "$repo_i" >/dev/null 2>&1)
(cd "$repo_i" && impact_isolated "$hi" bash "$TOOL" add --guard "secret-guard | blocked a key" --gap "none" >/dev/null 2>&1)
id_i="$(impact_project_id "$repo_i")"
check_dir "(i) setup: the entry was created under the harness home" "$hi/.claude/.keel/impact/$id_i"
check_file "(i) setup: it holds a ledger row" "$hi/.claude/.keel/impact/$id_i/ledger.md"
mig "$hi"
check_status "(i) migrate exit 0" 0 "$STATUS"
rm -rf "$hi/.claude"
run impact_isolated "$hi" impact_entry_state "$repo_i"
check_eq "(i) after \$HOME/.claude is gone the entry state is still enabled" "enabled" "$OUT"
check_contains "(i) ...and the ledger row survived" "$(cat "$hi/.keel/impact/$id_i/ledger.md")" "blocked a key"

# --- (j) the next verb records the new path ---------------------------------------------------------------------------
hj="$SANDBOX/mj"; mkdir -p "$hj/.claude/.keel/impact"; repo_j="$(new_repo)"
(cd "$repo_j" && impact_isolated "$hj" bash "$TOOL" enable "$repo_j" >/dev/null 2>&1)
(cd "$repo_j" && impact_isolated "$hj" bash "$TOOL" add --guard "secret-guard | blocked a key" --gap "none" >/dev/null 2>&1)
mig "$hj"
(cd "$repo_j" && impact_isolated "$hj" bash "$TOOL" rollup >/dev/null 2>&1)
new_path_j="$(impact_isolated "$hj" impact_store_dir "$repo_j")"
check_contains "(j) the new path is where the store dir now resolves" "$new_path_j" "$hj/.keel/impact/"
run git -C "$repo_j" config --local --get-all keel.impactStore
check_contains "(j) one rollup records the new path in the repo's keel.impactStore" "$OUT" "$new_path_j"

# --- (k) a legacy source root that IS the target root → nothing to migrate -----------------------------------------------
hk="$SANDBOX/mk"; mkdir -p "$hk/.keel/impact" "$hk/.claude/.keel"
mk_entry "$hk/.keel/impact/-p-k"
ln -s "$hk/.keel/impact" "$hk/.claude/.keel/impact"
mig "$hk"
check_status "(k) exit 0" 0 "$STATUS"
check_contains "(k) nothing to migrate" "$OUT" "nothing to migrate"
check_nolink "(k) the entry is not turned into a link to itself" "$hk/.keel/impact/-p-k"

# --- (l) a pre-created target is kept (no T/<id> nesting); srm_link_back refuses an existing E ----------------------------
hl="$SANDBOX/ml"; mkdir -p "$hl/.claude/.keel/impact" "$hl/.keel/impact"
mk_entry "$hl/.claude/.keel/impact/-p-l"; mkdir -p "$hl/.keel/impact/-p-l"
mig "$hl"
check_nodir "(l) no nested T/<id>" "$hl/.keel/impact/-p-l/-p-l"
check_contains "(l) reported as kept" "$OUT" "kept"
run bash -c ". '$MIG'; srm_link_back '$hl/.keel/impact/-p-l' '$hl/.claude/.keel/impact/-p-l'"
check_ne "(l) srm_link_back over an existing directory returns non-zero" "0" "$STATUS"
check_contains "(l) ...and reports it as reappeared" "$OUT" "reappeared"
check_nolink "(l) ...and leaves E a real directory" "$hl/.claude/.keel/impact/-p-l"

# --- (m) an override → one notice line; a bad flag → exit 2 -----------------------------------------------------------------
hm="$SANDBOX/mm"; mkdir -p "$hm/.claude/.keel/impact"; mk_entry "$hm/.claude/.keel/impact/-p-m"
run env -u KEEL_HOME KEEL_IMPACT_STORE="$SANDBOX/m-override-impact" KEEL_READ_TRACE_STORE="$SANDBOX/m-override-rt" HOME="$hm" bash "$MIG"
check_status "(m) an override set → the notice does not count as a report: exit 0" 0 "$STATUS"
notice_count="$(printf '%s\n' "$OUT" | grep -c 'KEEL_IMPACT_STORE\|KEEL_READ_TRACE_STORE' || true)"
check_eq "(m) exactly one notice line" "1" "$notice_count"
check_dir "(m) the target is \$HOME/.keel/NAME, the override ignored" "$hm/.keel/impact/-p-m"
check_nodir "(m) ...nothing landed at the override" "$SANDBOX/m-override-impact"
mig "$hm" --bogus
check_status "(m) a bad flag → exit 2" 2 "$STATUS"
mig "$hm" --from
check_status "(m) --from without a value → exit 2" 2 "$STATUS"

summary
