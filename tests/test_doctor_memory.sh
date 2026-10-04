#!/usr/bin/env bash
# doctor's memory-dir checks (dir #521): W-MEMORY-ORPHAN / W-MEMORY-DANGLING / W-MEMORY-SUPERSEDED /
# H-MEMORY-STALE / H-MEMORY-DIR-UNRESOLVED — the "forgetting layer" over the harness memory dir. Own
# file, not an extension of test_doctor.sh: that file's tail is where every other doctor PR of the same
# release appends, so a separate file keeps each merge conflict-free.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

doctor="$REPO_ROOT/tools/doctor.sh"
GIT_ID=(-c user.email=t@keel.invalid -c user.name=t)

# A clean, committed-nothing project (CLAUDE.md ignored, so no GAP): prints its path.
cleanproj() {
  local d; d="$(mktemp -d "$SANDBOX/proj.XXXXXX")"; git -C "$d" init -q
  printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
  printf '%s' "$d"
}
newmem() { mktemp -d "$SANDBOX/mem.XXXXXX"; }
# commit FILE-in-project at a fixed committer date (deterministic %cs): commit_at DIR FILE YYYY-MM-DD
commit_at() {
  git -C "$1" add "$2"
  GIT_COMMITTER_DATE="$3T12:00:00" GIT_AUTHOR_DATE="$3T12:00:00" git -C "$1" "${GIT_ID[@]}" commit -qm "touch $2"
}
# mrun MEMDIR PROJECT [flags…] — doctor with the memory dir forced (the test-isolation hatch)
mrun() { local m="$1" p="$2"; shift 2; run env "KEEL_MEMORY_DIR=$m" "$doctor" "$@" "$p"; }
count_of() { printf '%s\n' "$OUT" | grep -c -- "$1" || true; }

# ---- A.2 orphan: fires on an unlinked file, not on a linked one, MEMORY.md, a subdir or a non-.md file ----
d="$(cleanproj)"; m="$(newmem)"
printf -- '- [Linked](linked.md) — hook\n- [Odd](odd.md) — other\n' > "$m/MEMORY.md"
printf '# l\n' > "$m/linked.md"; printf '# o\n' > "$m/odd.md"
printf '# orphan\n' > "$m/lonely-note.md"
mkdir "$m/sub"; printf '# s\n' > "$m/sub/deep.md"; printf 'x\n' > "$m/notes.txt"
mrun "$m" "$d"
check_status "orphan fixture → exit 0 (a WARN, not a GAP)" 0 "$STATUS"
check_contains "an unlinked top-level file fires W-MEMORY-ORPHAN" "$OUT" "WARN [W-MEMORY-ORPHAN] lonely-note.md"
check_absent   "a linked file is not an orphan" "$OUT" "[W-MEMORY-ORPHAN] linked.md"
check_absent   "MEMORY.md itself is never an orphan" "$OUT" "[W-MEMORY-ORPHAN] MEMORY.md"
check_absent   "a subdir file is ignored" "$OUT" "deep.md"
check_absent   "a non-.md file is ignored" "$OUT" "notes.txt"
check_eq       "exactly one orphan finding" 1 "$(count_of 'W-MEMORY-ORPHAN')"
check_contains "the remedy names both actions" "$OUT" "add the index line or delete the file"

# the `(<file>.md)` span ALONE decides: no leading `- `, no ` — hook` — still linked
printf 'see (odd.md) for the long story\n(linked.md)\n' > "$m/MEMORY.md"
mrun "$m" "$d"
check_absent "a linked-but-oddly-formatted index line still links (span alone decides)" "$OUT" "[W-MEMORY-ORPHAN] odd.md"
check_absent "a bare (file.md) line links too" "$OUT" "[W-MEMORY-ORPHAN] linked.md"
check_contains "...while the genuinely unlinked file still fires" "$OUT" "[W-MEMORY-ORPHAN] lonely-note.md"

# no MEMORY.md at all → every top-level file is unreachable by recall
rm -f "$m/MEMORY.md"
mrun "$m" "$d"
check_contains "no index at all → files are orphans" "$OUT" "[W-MEMORY-ORPHAN] linked.md"

# ---- A.3 dangling: a link to a file that is not there; one finding per link, naming the target ----
printf -- '- [Here](linked.md) — ok\n- [Gone](gone-away.md) — x\n- [Gone2](gone-too.md) — y\n- [Web](https://example.com/page.md) — url\n' > "$m/MEMORY.md"
mrun "$m" "$d"
check_contains "an index link to a missing file fires W-MEMORY-DANGLING" "$OUT" "WARN [W-MEMORY-DANGLING] gone-away.md"
check_contains "one finding per dangling link" "$OUT" "[W-MEMORY-DANGLING] gone-too.md"
check_eq       "exactly two dangling findings" 2 "$(count_of 'W-MEMORY-DANGLING')"
check_absent   "a link to an existing file does not dangle" "$OUT" "[W-MEMORY-DANGLING] linked.md"
check_absent   "a URL ending in .md is not a memory link" "$OUT" "page.md"
check_contains "the remedy names both actions" "$OUT" "remove the index line or restore the file"

# ---- A.4 superseded: the marker AFTER the span; uppercase only; a NAME never fires ----
printf '# a\n' > "$m/old-fact.md"; printf '# b\n' > "$m/gone-fact.md"; printf '# c\n' > "$m/superseded-approach.md"
printf '# d\n' > "$m/low.md"; printf '# e\n' > "$m/title-marked.md"
cat > "$m/MEMORY.md" <<'EOF'
- [Old](old-fact.md) — SUPERSEDED by the new one
- [Gone](gone-fact.md) — RETRACTED: it was wrong
- [Named](superseded-approach.md) — a perfectly live note
- [Lower](low.md) — superseded in lowercase prose is not the marker
- [Title RETRACTED](title-marked.md) — the marker sits in the [title], as on the live keel line
- no span here but RETRACTED appears
EOF
mrun "$m" "$d"
check_contains "SUPERSEDED after the span fires" "$OUT" "WARN [W-MEMORY-SUPERSEDED] old-fact.md"
check_contains "RETRACTED after the span fires" "$OUT" "WARN [W-MEMORY-SUPERSEDED] gone-fact.md"
check_contains "a marker in the [title] before the span fires too" "$OUT" "WARN [W-MEMORY-SUPERSEDED] title-marked.md"
check_absent   "a file NAMED superseded-approach.md never false-positives" "$OUT" "[W-MEMORY-SUPERSEDED] superseded-approach.md"
check_absent   "the lowercase word is not the marker" "$OUT" "[W-MEMORY-SUPERSEDED] low.md"
check_eq       "a line with no span is skipped; exactly three superseded findings" 3 "$(count_of 'W-MEMORY-SUPERSEDED')"
check_contains "the remedy is the delete step" "$OUT" "fold the correction into the surviving memory"
check_status   "the markers are WARNs → exit 0" 0 "$STATUS"

# accept-file suppression works like every other WARN/HINT ID (none is a GAP)
mkdir -p "$d/.keel"; printf 'W-MEMORY-SUPERSEDED\n' > "$d/.keel/doctor-accept"
mrun "$m" "$d"
check_absent   "an accepted W-MEMORY-SUPERSEDED is not printed" "$OUT" "[W-MEMORY-SUPERSEDED]"
check_contains "...and is counted in the tail summary" "$OUT" "accepted hidden"
rm -rf "$d/.keel"

# ---- a clean dir → silent (no memory finding at all) ----
d="$(cleanproj)"; m="$(newmem)"
printf -- '- [Fine](fine.md) — ok\n' > "$m/MEMORY.md"; printf '# f\n' > "$m/fine.md"
mrun "$m" "$d"
check_absent "a clean memory dir draws no memory finding" "$OUT" "MEMORY-"
check_contains "...and says which dir it resolved (info line)" "$OUT" "memory dir: $m"
mrun "$m" "$d" --quiet
check_absent "--quiet omits the info line like every non-finding line" "$OUT" "memory dir:"

# ---- absent dir → silent skip (explicit override naming nothing) ----
mrun "$SANDBOX/no-such-memory-dir" "$d"
check_absent "an absent KEEL_MEMORY_DIR is a silent skip" "$OUT" "MEMORY"
check_absent "...with no info line" "$OUT" "memory dir:"
check_contains "...and the audit still completes" "$OUT" "baseline OK"

# ---- default resolution: <KEEL_HOME>/projects/<path with / and . → ->/memory ----
d="$(cleanproj)"; kh="$SANDBOX/kh.$$"; enc="$(printf '%s' "$d" | sed "s#[/.]#-#g")"
case "$enc" in -*) pass "the encoded name keeps the leading dash (the leading / maps too)" ;; *) fail "encoding" "no leading dash: $enc" ;; esac
mkdir -p "$kh/projects/$enc/memory"; printf '# z\n' > "$kh/projects/$enc/memory/stray.md"
run env -u KEEL_MEMORY_DIR "KEEL_HOME=$kh" "$doctor" "$d"
check_contains "default resolution finds the encoded dir (orphan fires there)" "$OUT" "[W-MEMORY-ORPHAN] stray.md"
check_contains "...and prints the resolved dir" "$OUT" "memory dir: $kh/projects/$enc/memory"
# no KEEL_HOME → $HOME/.claude (the sandbox HOME here)
mkdir -p "$HOME/.claude/projects/$enc/memory"; printf '# z\n' > "$HOME/.claude/projects/$enc/memory/stray2.md"
run env -u KEEL_MEMORY_DIR -u KEEL_HOME "$doctor" "$d"
check_contains "no KEEL_HOME → \$HOME/.claude/projects/…" "$OUT" "[W-MEMORY-ORPHAN] stray2.md"
rm -rf "$HOME/.claude/projects/$enc"

# ---- H-MEMORY-DIR-UNRESOLVED: absent dir + a path char the encoder cannot vouch for → say so ----
odd="$SANDBOX/my_project.$$"; mkdir -p "$odd"; git -C "$odd" init -q
printf '# ctx\n' > "$odd/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$odd/.gitignore"
run env -u KEEL_MEMORY_DIR "KEEL_HOME=$SANDBOX/empty-kh" "$doctor" "$odd"
check_contains "an unencodable path + absent dir → H-MEMORY-DIR-UNRESOLVED" "$OUT" "HINT [H-MEMORY-DIR-UNRESOLVED]"
check_contains "...naming the override" "$OUT" "KEEL_MEMORY_DIR"
mrun "$SANDBOX/no-such-memory-dir" "$odd"
check_absent "an explicit KEEL_MEMORY_DIR never draws the unresolved hint" "$OUT" "H-MEMORY-DIR-UNRESOLVED"
case "$d" in
  *[!A-Za-z0-9/.-]*) printf '  skip  safe-path absent-dir case (this sandbox path carries a char outside [A-Za-z0-9/.-])\n' ;;
  *) run env -u KEEL_MEMORY_DIR "KEEL_HOME=$SANDBOX/empty-kh" "$doctor" "$d"
     check_absent "a plain path + absent dir is a silent skip (no unresolved hint)" "$OUT" "H-MEMORY-DIR-UNRESOLVED" ;;
esac

# ---- A.5 staleness: both branches of the date comparison, all three date sources ----
d="$(cleanproj)"; m="$(newmem)"
mkdir "$d/src"; printf 'a\n' > "$d/src/a.sh"; printf 'b\n' > "$d/src/b.sh"; printf 'c\n' > "$d/src/c.sh"
commit_at "$d" src/a.sh 2024-03-01
commit_at "$d" src/b.sh 2024-09-01
commit_at "$d" src/c.sh 2024-06-01
printf -- '- [S](stale-fm.md) — x\n- [F](fresh-fm.md) — x\n- [M](stale-mt.md) — x\n- [N](fresh-mt.md) — x\n- [Z](multi.md) — x\n- [Y](nopath.md) — x\n- [U](untracked.md) — x\n' > "$m/MEMORY.md"
printf -- '---\nname: s\nmetadata:\n  type: project\n  modified: 2024-01-15T10:00:00Z\n---\nSee `src/c.sh` for it.\n' > "$m/stale-fm.md"
printf -- '---\nname: f\nmetadata:\n  modified: 2024-12-31T10:00:00Z\n---\nSee `src/c.sh` for it.\n' > "$m/fresh-fm.md"
printf 'No frontmatter, mentions `src/c.sh`.\n' > "$m/stale-mt.md";  touch -t 202301011200 "$m/stale-mt.md"
printf 'No frontmatter, mentions `src/c.sh`.\n' > "$m/fresh-mt.md";  touch -t 202407011200 "$m/fresh-mt.md"
# multi-path: note dated 2024-06-15 is newer than a.sh (03-01) and older than b.sh (09-01) → ONE finding, naming b.sh
printf -- '---\nmetadata:\n  modified: 2024-06-15\n---\nTouches `src/a.sh` and `src/b.sh` and `a-word`.\n' > "$m/multi.md"
# a note that names no existing path → no finding; a path that exists but is untracked → no code date → no finding
printf -- '---\nmetadata:\n  modified: 2001-01-01\n---\nOnly `no/such/path.sh` and `https://example.com/x.md` and `src/*`.\n' > "$m/nopath.md"
printf 'new\n' > "$d/src/new.sh"
printf -- '---\nmetadata:\n  modified: 2001-01-01\n---\nOnly `src/new.sh` (untracked).\n' > "$m/untracked.md"
snap_before="$(snapshot_tree_cksum "$m")"
mrun "$m" "$d"
check_absent "staleness is opt-in: without --memory-age no H-MEMORY-STALE fires" "$OUT" "H-MEMORY-STALE"
mrun "$m" "$d" --memory-age
check_contains "stale via frontmatter → HINT, source token [fm]" "$OUT" "HINT [H-MEMORY-STALE] stale-fm.md (2024-01-15[fm] < 2024-06-01 for src/c.sh)"
check_absent   "fresh via frontmatter → no finding" "$OUT" "[H-MEMORY-STALE] fresh-fm.md"
check_contains "stale via mtime → source token [mtime]" "$OUT" "[H-MEMORY-STALE] stale-mt.md (2023-01-01[mtime] < 2024-06-01 for src/c.sh)"
check_absent   "fresh via mtime → no finding" "$OUT" "[H-MEMORY-STALE] fresh-mt.md"
check_contains "multi-path: the NEWEST path wins" "$OUT" "[H-MEMORY-STALE] multi.md (2024-06-15[fm] < 2024-09-01 for src/b.sh)"
check_eq       "multi-path: one finding per file" 1 "$(count_of '\] multi.md')"
check_absent   "no matching path → no finding" "$OUT" "[H-MEMORY-STALE] nopath.md"
check_absent   "an untracked path has no code date → no finding" "$OUT" "[H-MEMORY-STALE] untracked.md"
check_status   "staleness is a HINT → exit 0" 0 "$STATUS"
check_eq       "report-only: the run changed no memory file (names and bytes)" "$snap_before" "$(snapshot_tree_cksum "$m")"

run "$doctor" --help
check_contains "--help documents --memory-age" "$OUT" "--memory-age"

# ---- A.5 the operator's layout: the memory dir is a git repo of its own, reached through a symlink ----
d="$(cleanproj)"; kb="$SANDBOX/kbrepo.$$"; mkdir -p "$kb/kb-memory/p"; git -C "$kb" init -q
mkdir "$d/src"; printf 'a\n' > "$d/src/a.sh"; commit_at "$d" src/a.sh 2024-06-01
printf -- '- [G](gitnote.md) — x\n' > "$kb/kb-memory/p/MEMORY.md"
# frontmatter says 2999 (would be FRESH) — the git commit date must win the precedence and fire
printf -- '---\nmetadata:\n  modified: 2999-01-01\n---\nSee `src/a.sh`.\n' > "$kb/kb-memory/p/gitnote.md"
git -C "$kb" add -A
GIT_COMMITTER_DATE="2024-01-10T12:00:00" GIT_AUTHOR_DATE="2024-01-10T12:00:00" git -C "$kb" "${GIT_ID[@]}" commit -qm notes
ln -s "$kb/kb-memory/p" "$SANDBOX/linked-memory.$$"
mrun "$SANDBOX/linked-memory.$$" "$d" --memory-age
check_contains "git-repo dir via a symlink → note date from git, token [git] (beats the frontmatter)" "$OUT" "[H-MEMORY-STALE] gitnote.md (2024-01-10[git] < 2024-06-01 for src/a.sh)"
# a file with NO commit in that repo falls through to frontmatter
printf -- '- [G](gitnote.md) — x\n- [U](uncommitted.md) — x\n' > "$kb/kb-memory/p/MEMORY.md"
printf -- '---\nmetadata:\n  modified: 2024-02-02\n---\nSee `src/a.sh`.\n' > "$kb/kb-memory/p/uncommitted.md"
mrun "$SANDBOX/linked-memory.$$" "$d" --memory-age
check_contains "an uncommitted file in a git-repo dir falls back to [fm]" "$OUT" "[H-MEMORY-STALE] uncommitted.md (2024-02-02[fm] < 2024-06-01 for src/a.sh)"
# the orphan check works through the symlink too (physical dir resolved once)
printf '# o\n' > "$kb/kb-memory/p/orphan-via-link.md"
mrun "$SANDBOX/linked-memory.$$" "$d"
check_contains "orphan check works through the symlink" "$OUT" "[W-MEMORY-ORPHAN] orphan-via-link.md"

# ---- non-git project: the staleness sub-check is skipped (G-GIT-MISSING already reports the state) ----
nd="$(mktemp -d "$SANDBOX/nogit.XXXXXX")"; printf '# ctx\n' > "$nd/CLAUDE.md"
m="$(newmem)"; printf -- '- [S](s.md) — x\n' > "$m/MEMORY.md"
printf -- '---\nmetadata:\n  modified: 2001-01-01\n---\nSee `CLAUDE.md`.\n' > "$m/s.md"; printf '# o\n' > "$m/orph.md"
mrun "$m" "$nd" --memory-age
check_status   "non-git project still GAPs on its own" 1 "$STATUS"
check_absent   "non-git project → no staleness finding" "$OUT" "H-MEMORY-STALE"
check_contains "...but the deterministic memory checks still run" "$OUT" "[W-MEMORY-ORPHAN] orph.md"

summary
