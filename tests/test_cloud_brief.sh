#!/usr/bin/env bash
# test_cloud_brief.sh (dir #900) — tools/cloud-brief.sh and templates/cloud-protocol.md: the opt-in line, the
# eligibility rows G1–G9, the verdict line, the brief's shape and scan, the ledger and its lock, --check,
# --sweep, --dispatch, and the protocol's push guard run for real (spec docs/specs/900-cloud-ticket-routing.md,
# A1 T0–T21 and A3/T15b). Every case runs on fixtures under the sandbox: an engine copy of this tree committed
# to its own bare origin, a project with a bare origin, a stub `gh` and a stub `claude` on PATH, a fixture
# ledger and personal list — never the network, never the real ledger (T0).
REAL_LEDGER="${HOME:-/nonexistent}/.keel/cloud/ledger.tsv"
real_ledger_before="absent"; [ -f "$REAL_LEDGER" ] && real_ledger_before="$(cksum < "$REAL_LEDGER")"
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

echo "cloud-brief.sh (dir #900)"

TODAY="$(date +%F)"
TOKEN="$(key ghp_ "$(rep A 36)")"
LITERAL=zzfixturezz
HAVE_SCRIPT=""; command -v script >/dev/null 2>&1 && HAVE_SCRIPT=1

# --- the engine: this tree's tools and template, committed, pushed to a bare origin, plus one local commit ----
ENG="$SANDBOX/engine"
mkdir -p "$ENG/templates"
cp -R "$REPO_ROOT/tools" "$ENG/"
cp "$REPO_ROOT/templates/cloud-protocol.md" "$ENG/templates/"
git init -q "$ENG"
git -C "$ENG" add -A
git -C "$ENG" commit -qm "engine fixture"
git init -q --bare "$SANDBOX/keel-origin.git"
git -C "$ENG" remote add origin https://github.com/rockerlabs/keel.git
git -C "$ENG" config url."$SANDBOX/keel-origin.git".insteadOf https://github.com/rockerlabs/keel.git
git -C "$ENG" push -q origin HEAD:refs/heads/main
ENG_PUBLISHED="$(git -C "$ENG" rev-parse HEAD)"
git -C "$ENG" commit -q --allow-empty -m "local only"
ENG_HEAD="$(git -C "$ENG" rev-parse HEAD)"
BRIEF_TOOL="$ENG/tools/cloud-brief.sh"
check_ne "fixture: the engine has a local commit ahead of origin/main" "$ENG_PUBLISHED" "$ENG_HEAD"

# --- stubs --------------------------------------------------------------------------------------------------
gh_fixture_stub "$SANDBOX/bin"
cat > "$SANDBOX/bin/claude" <<'CLAUDE'
#!/usr/bin/env bash
d="${CLAUDE_FX:?}"
echo called >> "$d/calls"
pwd -P > "$d/cwd"
printf '%s' "$#" > "$d/argc"
printf '%s' "${1:-}" > "$d/arg1"
printf '%s' "${2:-}" > "$d/brief"
printf '%s %s %s %s' "${3:-}" "${4:-}" "${5:-}" "${6:-}" > "$d/rest"
cp "$CLOUD_LEDGER" "$d/ledger-at-call"
if [ -d "$(dirname "$CLOUD_LEDGER")/ledger.lock" ]; then echo held; else echo free; fi > "$d/lock-at-call"
if { : >&3; } 2>/dev/null; then echo open; else echo closed; fi > "$d/fd3-at-call"
case "$(cat "$d/mode" 2>/dev/null || true)" in
  trust)
    printf 'Quick safety check: Is this a project you created or one you trust?\n'
    printf ' \342\235\257 No, exit\n   Yes, I trust this folder\n Enter to confirm\n'
    exec sleep 600 ;;
  hang) printf 'Some other prompt [y/N] '; exec sleep 600 ;;
esac
rc="$(cat "$d/exit" 2>/dev/null || echo 0)"
if [ "$rc" = 0 ]; then
  echo "Created cloud session: Fixture"
  echo "View: https://claude.ai/code/session_01FIXTURE?from=cli&m=0"
else
  echo "stub stdout line"
  echo "stub stderr line" >&2
fi
exit "$rc"
CLAUDE
chmod +x "$SANDBOX/bin/claude"
export PATH="$SANDBOX/bin:$PATH"

# --- the standard backlog ---------------------------------------------------------------------------------------
std_backlog() {
  cat <<BACKLOG
# Backlog

## Open

### dir #801 — eligible, verdict yes, with a spec — R4 — → pool — 📐 SPEC-READY

Spec: docs/specs/s801.md (gitignored — main checkout only)

**Model rec:** mid tier + high — fixture.

**Cloud:** yes (2026-10-27, fixture)

### dir #802 — no verdict yet — R4 — → pool

**Model rec:** top tier + xhigh

### dir #803 — verdict no — R3 — → pool

**Cloud:** no — G4: needs a live device (2026-10-27, fixture)

### dir #804 — closed — R4 — ✅ DONE (PR #1)

**Cloud:** yes (2026-10-27, fixture)

### dir #805 — retracted — R4 — RETRACTED

**Cloud:** yes (2026-10-27, fixture)

### dir #806 — superseded — R4 — ❌ SUPERSEDED by dir #1

**Cloud:** yes (2026-10-27, fixture)

### dir #807 — in flight — R4 — ⏳ IN FLIGHT (2026-10-27, branch x)

**Cloud:** yes (2026-10-27, fixture)

### dir #808 — blocked — R4 — ⛔ BLOCKED by dir #1

**Cloud:** yes (2026-10-27, fixture)

### dir #809 — not ready — R2 — → pool

**Cloud:** yes (2026-10-27, fixture)

### dir #810 — no grade — → pool

**Cloud:** yes (2026-10-27, fixture)

### dir #811 — a contradiction — R2 — 📐 SPEC-READY

**Cloud:** yes (2026-10-27, fixture)

### dir #812 — spec-ready alone — 📐 SPEC-READY

**Cloud:** yes (2026-10-27, fixture)

### dir #813 — last token low — R4 rewrite — R2

**Cloud:** yes (2026-10-27, fixture)

### dir #814 — last token high — R2 idea — R4

**Cloud:** yes (2026-10-27, fixture)

### dir #815 — a body Log line with a check mark — R4 — → pool

Log: 2026-10-01 — ✅ DONE the first half

**Cloud:** yes (2026-10-27, fixture)

### dir #816 — two verdict lines — R4 — → pool

**Cloud:** yes (2026-10-27, fixture)

**Cloud:** yes (2026-10-27, fixture)

### dir #817 — a fenced example above a real no — R4 — → pool

\`\`\`
**Cloud:** yes (2026-10-27, example)
\`\`\`

**Cloud:** no — G4: needs a simulator (2026-10-27, fixture)

### dir #818 — maybe — R4 — → pool

**Cloud:** maybe

### dir #819 — yes with no date — R4 — → pool

**Cloud:** yes

### dir #820 — a missing spec — R4 — → pool

Spec: docs/specs/missing.md

**Cloud:** yes (2026-10-27, fixture)

### dir #821 — a design question — R4 — → pool

**Question for a /design pass:** which way?

**Cloud:** yes (2026-10-27, fixture)

### dir #822 — a design model rec — R4 — → pool

**Model rec:** top tier + high, For the Design pass

**Cloud:** yes (2026-10-27, fixture)

### dir #823 — a token in the ticket — R4 — → pool

The key $TOKEN leaked here.

**Cloud:** yes (2026-10-27, fixture)

### dir #824 — light tier — R4 — → pool

**Model rec:** light tier + low

**Cloud:** yes (2026-10-27, fixture)

### dir #825 — no model rec — R4 — → pool

**Cloud:** yes (2026-10-27, fixture)

### dir #826 — an unmapped tier — R4 — → pool

**Model rec:** huge tier + high

**Cloud:** yes (2026-10-27, fixture)

### dir #827 — a personal literal in the spec — R4 — → pool

Spec: docs/specs/s827.md

**Cloud:** yes (2026-10-27, fixture)

### dir #828 — a token in the spec — R4 — → pool

Spec: docs/specs/s828.md

**Cloud:** yes (2026-10-27, fixture)

### dir #829 — a big spec — R4 — → pool

Spec: docs/specs/big.md

**Cloud:** yes (2026-10-27, fixture)

### dir #830 — rejected alone — R4 — ❌ WONTFIX

**Cloud:** yes (2026-10-27, fixture)

### dir #831 — superseded alone — R4 — SUPERSEDED by dir #1

**Cloud:** yes (2026-10-27, fixture)

### dir #832 — maximum care — R4 — → pool

**Model rec:** top tier + maximum care

**Cloud:** yes (2026-10-27, fixture)

### dir #833 — no effort word — R4 — → pool

**Model rec:** mid tier, careful

**Cloud:** yes (2026-10-27, fixture)

### dir #834 — two tiers — R4 — → pool

**Model rec:** mid tier + high (top tier + xhigh if the gate route is taken)

**Cloud:** yes (2026-10-27, fixture)

### dir #840 — no verdict, then a sibling with one — R4 — → pool

Body of 840.

### dir #841 — the sibling — R4 — → pool

Body of 841.

**Cloud:** yes (2026-10-27, fixture)

### KB.34 — a KB-shaped id — R4 — → pool

**Cloud:** yes (2026-10-27, fixture)

### H.130 — an H-shaped id — R4 — → pool

**Cloud:** yes (2026-10-27, fixture)

### 34. — a numbered id — R4 — → pool

**Cloud:** yes (2026-10-27, fixture)

### 35. a legacy heading with no dash after the id — R4

**Cloud:** yes (2026-10-27, fixture)
BACKLOG
}

# gh_ok DIR OWNER/NAME — the stub answers for a readable, protected repository with CI.
gh_ok() {
  local d="$1" key
  key="$(printf '%s' "repos/$2" | tr '/' '_')"
  mkdir -p "$d/api"
  printf '{"default_branch":"main"}\n' > "$d/api/$key.json"
  printf '{"protected":true,"protection":{"required_status_checks":{"enforcement_level":"everyone"}}}\n' > "$d/api/${key}_branches_main.json"
  printf '{"total_count":1,"workflows":[{"name":"CI","state":"active"}]}\n' > "$d/api/${key}_actions_workflows.json"
}

# home_slug DIR — Claude Code's project-directory encoding of DIR (every byte outside [A-Za-z0-9] → `-`).
home_slug() { printf '%s' "$1" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g'; }

# fx [OPTIN-LINE] — a fresh fixture: $F, $P (the project's main checkout), $GH_FX, $CLAUDE_FX, the ledger.
fx() {
  F="$(mktemp -d "$SANDBOX/fx.XXXXXX")"; require_sandbox_path "$F" fx
  P="$F/proj"
  mkdir -p "$P/docs/specs" "$F/gh" "$F/claude" "$F/store"
  export GH_FX="$F/gh" CLAUDE_FX="$F/claude"
  export CLOUD_LEDGER="$F/store/ledger.tsv" CLOUD_BRIEF_DIR="$F/store/briefs" SECRET_SCAN_PERSONAL_FILE="$F/personal"
  printf '%s\n' "$LITERAL" > "$F/personal"
  gh_ok "$GH_FX" example/proj
  {
    printf '# proj — project context (fixture)\n\n'
    printf '%s\n' "${1-KEEL-CLOUD}"
    printf '\nTest command: bash tests/run.sh. Notes live at %s/notes/rails.md.\n' "$HOME"
    printf 'Claude project dir: %s-proj; scratch /private/tmp/claude-%s/x; tmp /tmp/claude-%s/y\n' \
      "$(home_slug "$HOME")" "$(id -u)" "$(id -u)"
    printf 'Physical home: %s/notes/phys.md\n' "$(cd "$HOME" && pwd -P)"
  } > "$P/CLAUDE.md"
  std_backlog > "$P/BACKLOG.md"
  printf '# spec 801\nBaseline: abc1234\nRead %s/notes/s801.md first.\nA1 the thing works.\n' "$HOME" > "$P/docs/specs/s801.md"
  printf '# spec 827\nowner %s here\n' "$LITERAL" > "$P/docs/specs/s827.md"
  printf '# spec 828\ntoken %s\n' "$TOKEN" > "$P/docs/specs/s828.md"
  { printf '# big spec\n'; rep x 135000; printf '\n'; } > "$P/docs/specs/big.md"
  printf 'BACKLOG.md\nCLAUDE.md\ndocs/specs/\n' > "$P/.gitignore"
  git init -q "$P"
  git -C "$P" add .gitignore
  git -C "$P" commit -qm init
  git init -q --bare "$F/proj-origin.git"
  git -C "$P" remote add origin https://github.com/example/proj.git
  git -C "$P" config url."$F/proj-origin.git".insteadOf https://github.com/example/proj.git
  git -C "$P" push -q origin HEAD:refs/heads/main
}

cb()  { run "$BRIEF_TOOL" "$@"; }                                         # merged stdout+stderr
cbo() { OUT="$("$BRIEF_TOOL" "$@" 2>"$F/stderr" </dev/null)"; STATUS=$?; ERR="$(cat "$F/stderr")"; }
# Ticket ids compare as strings: awk compares two numeric-looking values as numbers (`34.` = `34`).
row_of()    { awk -F'\t' -v t="$1" 'NR > 1 && ($3 "") == (t "")' "$CLOUD_LEDGER" 2>/dev/null; }
status_of() { row_of "$1" | cut -f8; }
set_cell() { # TICKET N VALUE — edit the fixture ledger by hand, as an operator would
  awk -F'\t' -v OFS='\t' -v t="$1" -v n="$2" -v v="$3" 'NR > 1 && ($3 "") == (t "") { $n = v } { print }' "$CLOUD_LEDGER" > "$F/l.tmp"
  cat "$F/l.tmp" > "$CLOUD_LEDGER"
}
set_status() { set_cell "$1" 8 "$2"; } # TICKET STATUS
part_of() { awk -v p="=== $2 ===" '$0 == p { f = 1; next } /^=== [a-z ]+ ===$/ { f = 0 } f' "$1"; }
nothing_written() { # LABEL
  if [ -d "$CLOUD_BRIEF_DIR" ] && [ -n "$(ls -A "$CLOUD_BRIEF_DIR")" ]; then fail "$1: no brief" "found $(ls "$CLOUD_BRIEF_DIR")"; else pass "$1: no brief"; fi
  if [ -s "$CLOUD_LEDGER" ] && [ -n "$(tail -n +2 "$CLOUD_LEDGER")" ]; then fail "$1: no ledger row" "$(cat "$CLOUD_LEDGER")"; else pass "$1: no ledger row"; fi
}

# --- T1 / T1c: the opt-in line ------------------------------------------------------------------------------------
fx ""
cb "$P" "dir #801"
check_status "T1 no KEEL-CLOUD line → exit 3" 3 "$STATUS"
check_contains "T1 names G1" "$OUT" "refused: G1"
nothing_written "T1"

fx "This project uses KEEL-CLOUD for its tickets."
cbo "$P" "dir #801"
check_status "T1 the token only mid-paragraph → exit 3" 3 "$STATUS"
check_contains "T1 mid-paragraph: G1" "$ERR" "refused: G1"
check_contains "T1 mid-paragraph: stderr names the line" "$ERR" "line 3: This project uses KEEL-CLOUD"

fx "KEEL-CLOUD unprotected-ok extra"
cbo "$P" "dir #801"
check_status "T1c 'KEEL-CLOUD unprotected-ok extra' → exit 3" 3 "$STATUS"
check_contains "T1c near-miss: G1" "$ERR" "refused: G1"
check_contains "T1c near-miss: stderr names the line" "$ERR" "KEEL-CLOUD unprotected-ok extra"
fx "keel-cloud"
cbo "$P" "dir #801"
check_status "T1c lowercase 'keel-cloud' → exit 3" 3 "$STATUS"
check_contains "T1c lowercase: G1 and the line" "$ERR" "line 3: keel-cloud"

set_protection() { printf '%s\n' "$1" > "$GH_FX/api/repos_example_proj_branches_main.json"; } # SHAPE
unprotect() { set_protection '{"protected":true,"protection":{"enabled":true}}'; }
fx "KEEL-CLOUD
KEEL-CLOUD unprotected-ok extra"
unprotect
cbo "$P" "dir #801"
check_status "T1c a plain line + a near-miss unprotected-ok line, unprotected branch → exit 3" 3 "$STATUS"
check_contains "T1c the near-miss line does not opt in: G1b" "$ERR" "refused: G1b"
fx "KEEL-CLOUD
We are fine with unprotected-ok here."
unprotect
cbo "$P" "dir #801"
check_contains "T1c prose naming unprotected-ok does not opt in: G1b" "$ERR" "refused: G1b"
fx "$(printf 'KEEL-CLOUD\r')"
cb "$P" "dir #801"
check_status "T1c a CRLF KEEL-CLOUD line passes" 0 "$STATUS"

# dir #913 (1): the opt-in is read from fence-blanked text, like every other field — a line inside a fenced example
# opts nothing in (docs/cloud.md B1), and the refusal says the line was fenced.
for fence in '```' '~~~'; do
  fx "$fence"$'text\nKEEL-CLOUD\n'"$fence"
  cbo "$P" "dir #801"
  check_status "T1e KEEL-CLOUD only inside a $fence fence → exit 3" 3 "$STATUS"
  check_contains "T1e … G1" "$ERR" "refused: G1"
  check_contains "T1e … stderr names the fenced line" "$ERR" "CLAUDE.md line 4 (inside a fenced block): KEEL-CLOUD"
  nothing_written "T1e $fence"
done
fx $'```\nKEEL-CLOUD unprotected-ok\n```\n\nKEEL-CLOUD'
unprotect
cbo "$P" "dir #801"
check_status "T1e a fenced 'unprotected-ok' line does not carry its flag to a real plain line → exit 3" 3 "$STATUS"
check_contains "T1e … the real line opts in, so the refusal is G1b" "$ERR" "refused: G1b"
fx $'```\nan example\n```\n\nKEEL-CLOUD'
cb "$P" "dir #801"
check_status "T1e a real KEEL-CLOUD line after a closed fence still opts in" 0 "$STATUS"
fx $'```\nan unclosed example\n\nKEEL-CLOUD'
cbo "$P" "dir #801"
check_status "T1e a stray fence above the real line blanks it → exit 3" 3 "$STATUS"
check_contains "T1e … and the refusal says the fence markers are odd" "$ERR" "odd number of fence markers"

# dir #913 (2): an HTTP 403 that is a rate limit (X-RateLimit-Remaining: 0, or "rate limit" in the message) is
# transient — exit 2, nothing written; any other 403 stays "not readable" (G1/G1b/G1c, exit 3).
rl() { # PATH-KEY MESSAGE REMAINING-HEADER-LINE — the stub answers 403 for it
  printf '%s\n' "$2" > "$GH_FX/api/$1.403"
  if [ -n "${3:-}" ]; then printf '%s\n' "$3" > "$GH_FX/api/$1.403hdr"; else rm -f "$GH_FX/api/$1.403hdr"; fi
}
for key in repos_example_proj repos_example_proj_branches_main repos_example_proj_actions_workflows; do
  case "$key" in repos_example_proj) row=G1 ;; *_branches_main) row=G1b ;; *) row=G1c ;; esac
  fx; rl "$key" "Forbidden" "X-RateLimit-Remaining: 4999"
  cb "$P" "dir #801"
  check_status "T22 a plain 403 reading $key → exit 3" 3 "$STATUS"
  check_contains "T22 … refused as $row" "$OUT" "refused: $row"
  nothing_written "T22 plain 403 $key"
  fx; rl "$key" "Forbidden" "X-RateLimit-Remaining: 10"
  cb "$P" "dir #801"
  check_status "T22 a 403 with X-RateLimit-Remaining: 10 (not 0) reading $key → exit 3" 3 "$STATUS"
  fx; rl "$key" "Forbidden" ""
  cb "$P" "dir #801"
  check_status "T22 a 403 with no rate-limit header reading $key → exit 3" 3 "$STATUS"
  fx; rl "$key" "Forbidden" "X-RateLimit-Remaining: 0"
  cb "$P" "dir #801"
  check_status "T22 a 403 with X-RateLimit-Remaining: 0 reading $key → exit 2" 2 "$STATUS"
  check_contains "T22 … named as a rate limit" "$OUT" "rate limit"
  nothing_written "T22 rate limit $key"
  fx; rl "$key" "Forbidden" "x-ratelimit-remaining: 0"
  cb "$P" "dir #801"
  check_status "T22 … the header name in lower case (HTTP/2) → exit 2" 2 "$STATUS"
  fx; rl "$key" "API rate limit exceeded for user ID 1." "X-RateLimit-Remaining: 4999"
  cb "$P" "dir #801"
  check_status "T22 a 403 whose message says rate limit → exit 2" 2 "$STATUS"
  fx; rl "$key" "You have exceeded a secondary rate limit. Please wait." ""
  cb "$P" "dir #801"
  check_status "T22 a secondary rate limit (no header) → exit 2" 2 "$STATUS"
done

# --- T1b / T1d: finding the ticket --------------------------------------------------------------------------------
fx
cb "$P" "dir #999"
check_status "T1b an unknown id → exit 2" 2 "$STATUS"
cb "$P" "dir #80"
check_status "T1d 'dir #80' when only dir #801 exists → exit 2" 2 "$STATUS"
cb "$P" "35."
check_status "T1b a legacy heading with no ' — ' after the id → exit 2" 2 "$STATUS"
fx
mv "$P/BACKLOG.md" "$F/away.md"
cb "$P" "dir #801"
check_status "T1b a project with no backlog → exit 2" 2 "$STATUS"
check_contains "T1b no backlog: spec mode named" "$OUT" "spec-mode tickets are not dispatched"

fx
cb "$P" "dir #840"
check_status "T1d dir #840 with no verdict, its sibling dir #841 carrying one → exit 4" 4 "$STATUS"
cb "$P" "dir #840" --eligible --out "$F/b840.md"
check_status "T1d dir #840 --eligible → exit 0" 0 "$STATUS"
t840="$(part_of "$F/b840.md" ticket)"
check_contains "T1d the ticket part holds dir #840" "$t840" "Body of 840."
check_absent "T1d the ticket part holds no dir #841 text" "$t840" "dir #841"
check_absent "T1d the ticket part holds no sibling body" "$t840" "Body of 841."

# --- T2: origin and gh ------------------------------------------------------------------------------------------
fx
git -C "$P" remote set-url origin https://gitlab.com/example/proj.git
cb "$P" "dir #801"
check_status "T2 origin not on github.com → exit 3" 3 "$STATUS"
check_contains "T2 not github: G1" "$OUT" "refused: G1"
fx
touch "$GH_FX/fail"
cb "$P" "dir #801"
check_status "T2 gh fails for transport → exit 2" 2 "$STATUS"
fx
rm "$GH_FX/api/repos_example_proj.json"
cb "$P" "dir #801"
check_status "T2 gh answers 404 for the repository → exit 3" 3 "$STATUS"
check_contains "T2 404: G1" "$OUT" "refused: G1"

# --- T3 / T3c: protection and CI ---------------------------------------------------------------------------------
fx
cb "$P" "dir #801"
check_status "T3 enforcement_level everyone → passes" 0 "$STATUS"
for shape in '{"protected":true,"protection":{"enabled":true}}' \
             '{"protected":true,"protection":{"required_status_checks":{"enforcement_level":"non_admins"}}}' \
             '{"protected":false}'; do
  fx
  set_protection "$shape"
  cb "$P" "dir #801"
  check_status "T3 $shape without unprotected-ok → exit 3" 3 "$STATUS"
  check_contains "T3 $shape: G1b" "$OUT" "refused: G1b"
  fx "KEEL-CLOUD unprotected-ok"
  set_protection "$shape"
  cb "$P" "dir #801"
  check_status "T3 $shape with unprotected-ok → 0" 0 "$STATUS"
done
fx
printf '{"total_count":0}\n' > "$GH_FX/api/repos_example_proj_actions_workflows.json"
cb "$P" "dir #801"
check_status "T3c no workflow → exit 3" 3 "$STATUS"
check_contains "T3c names G1c" "$OUT" "refused: G1c"
nothing_written "T3c"
fx
printf '{"total_count":1,"workflows":[{"name":"iOS CI","state":"disabled_manually"}]}\n' > "$GH_FX/api/repos_example_proj_actions_workflows.json"
cb "$P" "dir #801"
check_status "T3c only a disabled workflow → exit 3" 3 "$STATUS"
check_contains "T3c disabled: G1c" "$OUT" "refused: G1c"
nothing_written "T3c disabled"
fx
printf '{"total_count":2,"workflows":[{"name":"old","state":"disabled_manually"},{"name":"CI","state":"active"}]}\n' > "$GH_FX/api/repos_example_proj_actions_workflows.json"
cb "$P" "dir #801"
check_status "T3c one active workflow → passes" 0 "$STATUS"

# --- T4: G2 ---------------------------------------------------------------------------------------------------
fx
for t in 804 805 806 807 808 809 810 811 813 830 831; do
  cb "$P" "dir #$t"
  check_status "T4 dir #$t → exit 3" 3 "$STATUS"
  check_contains "T4 dir #$t: G2" "$OUT" "refused: G2 "
done
for t in 812 814 815; do
  cb "$P" "dir #$t"
  check_status "T4 dir #$t passes G2" 0 "$STATUS"
done

# --- T5–T10b: the verdict line, G7, G8 -------------------------------------------------------------------------
fx
cb "$P" "dir #803"
check_status "T5 a no — G4 verdict → exit 3" 3 "$STATUS"
check_contains "T5 stderr names G4 and the reason" "$OUT" "G4: needs a live device"
nothing_written "T5"
cb "$P" "dir #801"
check_status "T6 a yes verdict builds without --eligible" 0 "$STATUS"
fx
cb "$P" "dir #802"
check_status "T7 no verdict → exit 4" 4 "$STATUS"
for r in G3 G3b G4 G5 G8; do check_contains "T7 prints $r" "$OUT" "  $r "; done
check_contains "T7 prints the yes template" "$OUT" "**Cloud:** yes ($TODAY, <who>)"
check_contains "T7 prints the no template" "$OUT" "**Cloud:** no — <G3|G3b|G4|G5|G8>: <reason> ($TODAY, <who>)"
nothing_written "T7"
cb "$P" "dir #816"
check_status "T8 two verdict lines → exit 3" 3 "$STATUS"
cb "$P" "dir #817"
check_status "T8 a fenced yes above a real no — G4 → exit 3" 3 "$STATUS"
check_contains "T8 the value is read from the blanked block: G4" "$OUT" "G4: needs a simulator"
cb "$P" "dir #818"
check_status "T9 **Cloud:** maybe → exit 3" 3 "$STATUS"
cb "$P" "dir #819"
check_status "T9 **Cloud:** yes with no (date, who) → exit 3" 3 "$STATUS"
cb "$P" "dir #820"
check_status "T10 Spec: a missing file → exit 3" 3 "$STATUS"
check_contains "T10 names G7" "$OUT" "refused: G7"
cb "$P" "dir #821"
check_status "T10b 'Question for a /design pass' → exit 3" 3 "$STATUS"
check_contains "T10b question: G8" "$OUT" "refused: G8"
cb "$P" "dir #822"
check_status "T10b a Model rec 'For the Design' → exit 3" 3 "$STATUS"
check_contains "T10b model rec: G8" "$OUT" "refused: G8"
nothing_written "T5–T10b"

# --- T10c: a Spec: path outside the main checkout, a CRLF Spec: line ------------------------------------------
add_ticket() { printf '%b' "$1" >> "$P/BACKLOG.md"; } # TEXT (printf %b escapes) — appended to the fixture backlog
fx
printf '# outside\n' > "$F/outside.md"
mkdir -p "$F/outside-dir" && printf '# linked\n' > "$F/outside-dir/s.md"
ln -s "$F/outside-dir" "$P/docs/link"
ln -s "$F/outside.md" "$P/docs/specs/linked.md"
add_ticket '\n### dir #850 — a spec beside the checkout — R4 — → pool\n\nSpec: ../outside.md\n\n**Cloud:** yes (2026-10-27, fixture)\n'
add_ticket '\n### dir #854 — a spec through a symlinked dir — R4 — → pool\n\nSpec: docs/link/s.md\n\n**Cloud:** yes (2026-10-27, fixture)\n'
add_ticket '\n### dir #857 — a spec that is a symlink out — R4 — → pool\n\nSpec: docs/specs/linked.md\n\n**Cloud:** yes (2026-10-27, fixture)\n'
add_ticket "\\n### dir #855 — an absolute spec — R4 — → pool\\n\\nSpec: $F/outside.md\\n\\n**Cloud:** yes (2026-10-27, fixture)\\n"
add_ticket '\n### dir #853 — a CRLF block — R4 — → pool\r\n\r\nSpec: docs/specs/s801.md\r\n\r\n**Cloud:** yes (2026-10-27, fixture)\r\n'
add_ticket '\n### dir #858 — a spec under a symlinked dir, then .. — R4 — → pool\n\nSpec: docs/alink/../outside.md\n\n**Cloud:** yes (2026-10-27, fixture)\n'
ln -s "$F/outside-dir" "$P/docs/alink"
for t in 850 854 855 858; do
  cb "$P" "dir #$t"
  check_status "T10c dir #$t: a Spec: outside the main checkout → exit 3" 3 "$STATUS"
  check_contains "T10c dir #$t: G7, outside \$MAIN" "$OUT" "refused: G7"
  check_contains "T10c dir #$t: … says outside" "$OUT" "outside $(cd "$P" && pwd -P)"
done
cb "$P" "dir #857"
check_status "T10c dir #857: a Spec: that is itself a symlink → exit 3" 3 "$STATUS"
check_contains "T10c dir #857: G7, a symlink" "$OUT" "refused: G7 — Spec: docs/specs/linked.md is a symlink"
check_absent "T10c dir #857: … with no claim about where it leads" "$OUT" "outside"
# A `.git` component — named, or reached through a symlinked directory — never travels (the repo's own config).
ln -s ../.git "$P/docs/g"
add_ticket '\n### dir #859 — a spec in .git — R4 — → pool\n\nSpec: .git/config\n\n**Cloud:** yes (2026-10-27, fixture)\n'
add_ticket '\n### dir #864 — a spec in .git through a link — R4 — → pool\n\nSpec: docs/g/config\n\n**Cloud:** yes (2026-10-27, fixture)\n'
for t in 859 864; do
  cb "$P" "dir #$t"
  check_status "T10c dir #$t: a Spec: inside .git → exit 3" 3 "$STATUS"
  check_contains "T10c dir #$t: G7, .git" "$OUT" "refused: G7"
  check_contains "T10c dir #$t: … names .git" "$OUT" ".git"
done
# In any case — a case-insensitive file system (macOS) reads `.GIT` as the repository's own `.git`. As written, a
# `.git` component refuses (a gitfile too, which no directory check sees); physically, a `.git` or `*.git` directory
# (a bare repository inside the checkout), named or reached through a symlinked directory.
mkdir -p "$P/mirror.git" "$P/docs/sub" && printf '[core]\n\tbare = true\n' > "$P/mirror.git/config"
printf 'gitdir: /nonexistent-fixture\n' > "$P/docs/sub/.git"
ln -s ../mirror.git "$P/docs/m"
add_ticket '\n### dir #873 — a spec in .GIT — R4 — → pool\n\nSpec: .GIT/config\n\n**Cloud:** yes (2026-10-27, fixture)\n'
add_ticket '\n### dir #881 — a gitfile spec — R4 — → pool\n\nSpec: docs/sub/.git\n\n**Cloud:** yes (2026-10-27, fixture)\n'
add_ticket '\n### dir #874 — a spec in a bare repository inside the checkout — R4 — → pool\n\nSpec: mirror.git/config\n\n**Cloud:** yes (2026-10-27, fixture)\n'
add_ticket '\n### dir #875 — a spec in a bare repository through a link — R4 — → pool\n\nSpec: docs/m/config\n\n**Cloud:** yes (2026-10-27, fixture)\n'
written="873 881" physical="874 875"
if [ -f "$P/.GIT/config" ]; then # a case-insensitive file system: `.GIT` reached through a link (not `docs/G`:
  ln -s ../.GIT "$P/docs/upper"  # that name IS docs/g there, and ln would put the link inside it), a gitfile as .GIT
  add_ticket '\n### dir #876 — a spec in .GIT through a link — R4 — → pool\n\nSpec: docs/upper/config\n\n**Cloud:** yes (2026-10-27, fixture)\n'
  add_ticket '\n### dir #882 — a gitfile spec as .GIT — R4 — → pool\n\nSpec: docs/sub/.GIT\n\n**Cloud:** yes (2026-10-27, fixture)\n'
  written="$written 882" physical="$physical 876"
else
  echo "  SKIP  T10c dir #876, dir #882 (.GIT through a link, a gitfile as .GIT): this file system is case-sensitive"
fi
for t in $written $physical; do
  case " $physical " in *" $t "*) want="inside a git directory (its directory is" ;; *) want="has a .git component" ;; esac
  cb "$P" "dir #$t"
  check_status "T10c dir #$t: a Spec: in the repository's git data → exit 3" 3 "$STATUS"
  check_contains "T10c dir #$t: G7, '$want'" "$OUT" "refused: G7 — Spec: "
  check_contains "T10c dir #$t: … '$want'" "$OUT" "$want"
done
# Whatever its name, a directory git itself reads as git data refuses (a bare clone named `vendor/upstream`), and
# so does one git cannot answer for (a bare repository under safe.bareRepository=explicit).
git init -q --bare "$P/vendor/upstream"
add_ticket '\n### dir #883 — a spec in a bare clone named without .git — R4 — → pool\n\nSpec: vendor/upstream/config\n\n**Cloud:** yes (2026-10-27, fixture)\n'
cb "$P" "dir #883"
check_status "T10c dir #883: a Spec: in a bare clone named vendor/upstream → exit 3" 3 "$STATUS"
check_contains "T10c dir #883: G7, git reads it as a git directory" "$OUT" \
  "refused: G7 — Spec: vendor/upstream/config is inside a git directory (git reads "
n="${GIT_CONFIG_COUNT:-0}"
run env "GIT_CONFIG_COUNT=$((n + 1))" "GIT_CONFIG_KEY_$n=safe.bareRepository" "GIT_CONFIG_VALUE_$n=explicit" \
  "$BRIEF_TOOL" "$P" "dir #883"
check_status "T10c dir #883 under safe.bareRepository=explicit → exit 3" 3 "$STATUS"
check_contains "T10c … git cannot tell, so it refuses" "$OUT" \
  "refused: G7 — Spec: vendor/upstream/config — git cannot tell whether its directory"
check_contains "T10c … and quotes git's own message" "$OUT" "cannot use bare repository"
nothing_written "T10c"
# A `..` that stays inside the main checkout is no refusal: the physical directory decides.
add_ticket '\n### dir #865 — a spec spelled with .. inside — R4 — → pool\n\nSpec: docs/../docs/specs/s801.md\n\n**Cloud:** yes (2026-10-27, fixture)\n'
cb "$P" "dir #865" --out "$F/b865.md"
check_status "T10c Spec: docs/../docs/specs/s801.md (inside) passes G7" 0 "$STATUS"
check_contains "T10c … and its spec travels" "$(part_of "$F/b865.md" spec)" "A1 the thing works."
cb "$P" "dir #853" --out "$F/b853.md"
check_status "T10c a CRLF Spec: line passes G7" 0 "$STATUS"
check_contains "T10c … and its spec travels" "$(part_of "$F/b853.md" spec)" "A1 the thing works."

# --- T15c: a part with no final newline, a last ticket ending in a fence ------------------------------------
fx
printf '%s' "$(cat "$P/CLAUDE.md")" > "$F/c" && cat "$F/c" > "$P/CLAUDE.md"
printf '# spec 801\nA1 the thing works.' > "$P/docs/specs/s801.md"
add_ticket '\n### dir #851 — the last ticket ends in a fence — R4 — → pool\n\n**Cloud:** yes (2026-10-27, fixture)\n\n```\nfenced tail content\n```\n'
cb "$P" "dir #801" --out "$F/nl.md"
check_status "T15c parts with no final newline build" 0 "$STATUS"
check_eq "T15c a rails file with no final newline: the last line is the end marker" "=== end of brief ===" "$(tail -n 1 "$F/nl.md")"
check_eq "T15c a spec with no final newline: the rails marker is a line of its own" "1" "$(grep -cx '=== rails ===' "$F/nl.md")"
cb "$P" "dir #851" --out "$F/b851.md"
check_status "T15c the last ticket builds" 0 "$STATUS"
check_contains "T15c the last ticket's trailing fence travels" "$(part_of "$F/b851.md" ticket)" "fenced tail content"
# An unclosed fence blanks the rest of the file: the block must not run on over the tickets and sections after it.
fx
add_ticket '\n### dir #862 — an unclosed fence — R4 — → pool\n\n**Cloud:** yes (2026-10-27, fixture)\n\n```\nunclosed fence body\n\n### dir #863 — after the fence — R4 — → pool\n\nBody of 863.\n\n## Archive\n\n### dir #700 — archived — R4 — ✅ DONE\n'
cb "$P" "dir #862" --out "$F/b862.md"
check_status "T15c a ticket with an unclosed fence builds" 0 "$STATUS"
t862="$(part_of "$F/b862.md" ticket)"
check_contains "T15c … its own heading travels" "$t862" "### dir #862 — an unclosed fence"
check_contains "T15c … and its own text after the unclosed opener" "$t862" "unclosed fence body"
for gone in "dir #863" "Body of 863." "## Archive" "dir #700"; do
  check_absent "T15c … the ticket part carries no '$gone' from after the unclosed fence" "$t862" "$gone"
done
# A heading-shaped line inside the last ticket's CLOSED fence is fenced text: the fence travels whole.
fx
add_ticket '\n### dir #870 — a closing fence holding a heading — R4 — → pool\n\n**Cloud:** yes (2026-10-27, fixture)\n\n```\n### an example heading\n## an example section\nafter the example heading\n```\n'
cb "$P" "dir #870" --out "$F/b870.md"
check_status "T15c a last ticket whose closing fence holds a heading-shaped line builds" 0 "$STATUS"
t870="$(part_of "$F/b870.md" ticket)"
check_contains "T15c … the fenced heading-shaped line travels" "$t870" "### an example heading"
check_contains "T15c … a fenced section-shaped line too" "$t870" "## an example section"
check_contains "T15c … and the fence's last line" "$t870" "after the example heading"
# A closed fence, then an unclosed one: the closed fence travels, the unclosed fence's text up to the first heading.
fx
add_ticket '\n### dir #871 — a closed fence, then an unclosed one — R4 — → pool\n\n**Cloud:** yes (2026-10-27, fixture)\n\n```\n### a fenced example\n```\n\n```\nunclosed body 871\n\n### dir #872 — hidden by the unclosed fence — R4 — → pool\n\nBody of 872.\n'
cb "$P" "dir #871" --out "$F/b871.md"
check_status "T15c a closed fence, then an unclosed one, builds" 0 "$STATUS"
t871="$(part_of "$F/b871.md" ticket)"
check_contains "T15c … the closed fence's heading-shaped line travels" "$t871" "### a fenced example"
check_contains "T15c … the unclosed fence's own text travels" "$t871" "unclosed body 871"
check_absent "T15c … the heading it hid does not" "$t871" "dir #872"
check_absent "T15c … nor that heading's body" "$t871" "Body of 872."
# An unclosed fence with no heading after it: the block runs to the file's last line.
fx
add_ticket '\n### dir #880 — an unclosed fence at the end — R4 — → pool\n\n**Cloud:** yes (2026-10-27, fixture)\n\n```\nunclosed tail 880\nits last line\n'
cb "$P" "dir #880" --out "$F/b880.md"
check_status "T15c an unclosed fence at the end of the file builds" 0 "$STATUS"
check_contains "T15c … its text to the file's last line travels" "$(part_of "$F/b880.md" ticket)" "its last line"
# An unclosed fence, then a section holding its own closed fence: the toggle pairs the ticket's opener with that
# fence's first marker, so no marker tells which fence is open, and the archive's code reads as the ticket's own
# text. Cutting at the first section heading would drop text the blanking shows as the ticket's, so the build
# refuses (exit 2) and names the fix, rather than carrying the archive or silently shortening the ticket.
fx
add_ticket '\n### dir #884 — an unclosed fence before a fenced archive — R4 — → pool\n\n**Cloud:** yes (2026-10-27, fixture)\n\n```\nunclosed body 884\n\n## Archive\n\n### dir #885 — archived — R4 — ✅ DONE\n\n```sh\narchived code 885\n```\n\n### dir #886 — archived too — R4 — ✅ DONE\n\nBody of 886.\n'
cb "$P" "dir #884" --out "$F/b884.md"
check_status "T15c an unclosed fence before a fenced archive → exit 2" 2 "$STATUS"
check_contains "T15c … it names the unpaired fences" "$OUT" "the fence markers after its heading do not pair up"
check_nofile "T15c … no brief written" "$F/b884.md"
# The same ambiguity inside the ticket: a closed fence holding a section-shaped line, the ticket's own text after
# it (a G8 phrase), then an unclosed fence. A cut would drop that text, and G8 with it: the build refuses instead.
fx
add_ticket '\n### dir #887 — a fenced section line, then an unclosed fence — R4 — → pool\n\n**Cloud:** yes (2026-10-27, fixture)\n\n```\n## an example section\n```\n\nQuestion for a /design pass: which shape?\n\n```\nunclosed tail 887\n'
cb "$P" "dir #887" --out "$F/b887.md"
check_status "T15c a fenced section line before the ticket's own text, then an unclosed fence → exit 2" 2 "$STATUS"
check_contains "T15c … it names the unpaired fences" "$OUT" "the fence markers after its heading do not pair up"
check_nofile "T15c … no brief written" "$F/b887.md"
# dir #915: the end of a last ticket is the scanner's (tools/lib/backlog-blocks.sh), not a count kept here. A closed fence
# holding a section-shaped line, then an unclosed fence, with nothing visible after the ticket's own text: the cut used
# to fall inside the closed fence and the brief silently lost the rest of it. Now the closed fence travels whole, and the
# cut falls only inside the unclosed one.
fx
add_ticket '\n### dir #890 — a closed fence holding a section line, then an unclosed one — R4 — → pool\n\n**Cloud:** yes (2026-10-31, fixture)\n\n```\n## an example section\nfenced line after the section line\n```\n\n```\nunclosed tail 890\n'
cb "$P" "dir #890" --out "$F/b890.md"
check_status "T15c a closed fence holding a section line, then an unclosed fence, builds" 0 "$STATUS"
t890="$(part_of "$F/b890.md" ticket)"
check_contains "T15c … the closed fence's section-shaped line travels" "$t890" "## an example section"
check_contains "T15c … so does the rest of that fence" "$t890" "fenced line after the section line"
check_eq "T15c … and its closing marker (the fence is whole)" "3" "$(grep -c '^```' <<< "$t890")"
check_contains "T15c … then the unclosed fence's text" "$t890" "unclosed tail 890"
# The refusal names where to close the fence: inside the ticket, before the heading the unclosed fence hides. Closing it at
# the end of the file would make the count even and carry the sections after it.
fx
add_ticket '\n### dir #891 — an unclosed fence before a section — R4 — → pool\n\n**Cloud:** yes (2026-10-31, fixture)\n\n```\nunclosed body 891\n\n## Archive\n\n```sh\narchived code 891\n```\n\ntail text\n'
cb "$P" "dir #891" --out "$F/b891.md"
check_status "T15c an unclosed fence before a section with fenced code → exit 2" 2 "$STATUS"
n891="$(grep -n '^## Archive' "$P/BACKLOG.md" | tail -n 1 | cut -d: -f1)"
check_contains "T15c … it says to close the fence inside the ticket, before the hidden heading's line" "$OUT" \
  "close the unclosed fence inside the ticket, before line $n891"
check_contains "T15c … and names that heading's line as inside the ticket's text" "$OUT" "the heading at line $n891 of"
# Accepted limit, recorded: an unclosed opener plus ONE stray marker in a later section is an even count, which the toggle
# reads as "every fence closed" — the block then runs to the scanner's END, the file's last line, and carries that section.
# Telling this apart from a ticket whose fences all close needs a fence grammar (char, length, info string).
fx
add_ticket '\n### dir #892 — an unclosed fence and a stray marker later — R4 — → pool\n\n**Cloud:** yes (2026-10-31, fixture)\n\n```\nunclosed body 892\n\n## Later section\n\ntext of the later section\n\n```\nafter the stray marker\n'
cb "$P" "dir #892" --out "$F/b892.md"
check_status "T15c an unclosed fence and one stray marker later (even count) builds" 0 "$STATUS"
t892="$(part_of "$F/b892.md" ticket)"
check_contains "T15c … the block runs to the scanner's END, the file's last line" "$t892" "after the stray marker"
check_contains "T15c … carrying the later section (accepted limit: needs a fence grammar)" "$t892" "text of the later section"

# --- T15d: a part that cannot be read stops the build -------------------------------------------------------------
fx
chmod 000 "$P/docs/specs/s801.md"
cb "$P" "dir #801" --out "$F/unreadable.md"
if [ "$(id -u 2>/dev/null)" != 0 ]; then # root reads a mode-000 file (CLAUDE.md Linux-leg trap 2)
  check_status "T15d an unreadable spec → exit 2" 2 "$STATUS"
  check_contains "T15d … named" "$OUT" "cannot read"
  check_nofile "T15d … no brief written" "$F/unreadable.md"
fi
chmod 644 "$P/docs/specs/s801.md"

# --- T11 G6 --------------------------------------------------------------------------------------------------------
fx
cb "$P" "dir #829"
check_status "T11 a brief over the default cap → exit 3" 3 "$STATUS"
check_contains "T11 names G6 and the default 130000" "$OUT" "CLOUD_BRIEF_MAX_BYTES=130000"
cb "$P" "dir #801" --out "$F/size.md"
size="$(wc -c < "$F/size.md" | tr -d ' ')"
CLOUD_BRIEF_MAX_BYTES="$size" cb "$P" "dir #801" --out "$F/size2.md"
check_status "T11 a cap equal to the rewritten size → 0" 0 "$STATUS"
CLOUD_BRIEF_MAX_BYTES="$((size - 1))" cb "$P" "dir #801" --out "$F/size3.md"
check_status "T11 one byte less → exit 3" 3 "$STATUS"
rm -f "$F/size.md" "$F/size2.md"
fx
CLOUD_BRIEF_MAX_BYTES=1000 cb "$P" "dir #801"
check_status "T11 a brief over CLOUD_BRIEF_MAX_BYTES → exit 3" 3 "$STATUS"
check_contains "T11 override: G6" "$OUT" "refused: G6"
nothing_written "T11"

# --- T12: the scan, the home path, the personal list -----------------------------------------------------------
fx
cb "$P" "dir #823"
check_status "T12 a ghp_ token in the ticket → exit 1" 1 "$STATUS"
cb "$P" "dir #828"
check_status "T12 a ghp_ token in the spec → exit 1" 1 "$STATUS"
cb "$P" "dir #827"
check_status "T12 a personal literal in the spec → exit 1" 1 "$STATUS"
nothing_written "T12"
printf 'key %s\n' "$TOKEN" >> "$P/CLAUDE.md"
cb "$P" "dir #801"
check_status "T12 a ghp_ token in the rails → exit 1" 1 "$STATUS"
nothing_written "T12 rails"
fx
printf 'key %s # %s\n' "$TOKEN" "secret-scan:""allow" >> "$P/CLAUDE.md"
cb "$P" "dir #801"
check_status "T12 a token beside an allow marker still refuses (the brief's scan reads markers as text) → exit 1" 1 "$STATUS"
# A marker split by an invalid byte reads whole in the scanner's caller-locale personal pass (after `iconv -c`),
# the one pass that finds a non-ASCII literal's case variant: it hides nothing either.
utf8_locale="$(pick_utf8_locale)" || utf8_locale=""
if [ -n "$utf8_locale" ]; then
  fx
  printf 'ёлкаfixture\n' >> "$F/personal"
  printf '# spec 878\nowner ЁЛКАFIXTURE here\n' > "$P/docs/specs/s878.md"
  printf '# spec 879\nowner ЁЛКАFIXTURE here # secret-scan:al\377low\n' > "$P/docs/specs/s879.md"
  add_ticket '\n### dir #878 — a literal case variant in the spec — R4 — → pool\n\nSpec: docs/specs/s878.md\n\n**Cloud:** yes (2026-10-27, fixture)\n'
  add_ticket '\n### dir #879 — the same beside a split allow marker — R4 — → pool\n\nSpec: docs/specs/s879.md\n\n**Cloud:** yes (2026-10-27, fixture)\n'
  LC_ALL="$utf8_locale" cb "$P" "dir #878"
  check_status "T12 a non-ASCII literal's case variant in the spec, under $utf8_locale → exit 1" 1 "$STATUS"
  LC_ALL="$utf8_locale" cb "$P" "dir #879"
  check_status "T12 … beside an allow marker split by an invalid byte → still exit 1" 1 "$STATUS"
  nothing_written "T12 split marker"
else
  echo "  SKIP  T12 split allow marker: this host has no UTF-8 locale"
fi
fx
cb "$P" "dir #801" --out "$F/b801.md"
check_status "T12 the clean ticket builds" 0 "$STATUS"
b801="$(cat "$F/b801.md")"
check_absent "T12 \$HOME rewritten" "$b801" "$HOME"
# shellcheck disable=SC2088  # the LITERAL ~ is the point: the rewrite writes it verbatim
check_contains "T12 \$HOME became ~" "$b801" "~/notes/rails.md"
check_contains "T12 the -Users-<user>- form rewritten" "$b801" "-Users-x-proj"
check_contains "T12 the /private/tmp/claude-<uid>/ form rewritten" "$b801" "scratch <tmp>/x"
check_contains "T12 the /tmp/claude-<uid>/ form rewritten" "$b801" "tmp <tmp>/y"
check_absent "T12 the physical home path rewritten" "$b801" "$(cd "$HOME" && pwd -P)"
check_absent "T12 no home slug left" "$b801" "$(home_slug "$HOME")"
# The longer path first: on macOS the physical home (/private/var/…) holds the logical one (/var/…).
# shellcheck disable=SC2088
check_contains "T12 the physical home, rewritten whole (the longer form first)" "$b801" "Physical home: ~/notes/phys.md"
HOME_SAVED="$HOME"
export HOME="$SANDBOX/home.dotted"
mkdir -p "$HOME"
fx
cb "$P" "dir #801" --out "$F/dotted.md"
check_status "T12 a HOME with a dot in its name builds" 0 "$STATUS"
dotted="$(cat "$F/dotted.md")"
check_absent "T12 the dotted HOME's slug rewritten" "$dotted" "$(home_slug "$HOME")"
check_contains "T12 … to -Users-x-" "$dotted" "-Users-x-proj"
check_absent "T12 the dotted HOME's path rewritten" "$dotted" "home.dotted"
# Every byte outside [A-Za-z0-9] is a `-` in Claude Code's project-dir name, an `_` too; the bare slug before a `/`.
export HOME="$SANDBOX/x/first_last"
mkdir -p "$HOME"
fx
# A slug nested in another project-dir name (a session started under a scratch root) follows a `-`; the
# `/` and `.` → `-` form (tools/lib/transcript-usage.sh's tu_project_slug) keeps the `_`.
nested="$(home_slug "/private/tmp/claude-$(id -u)/$(home_slug "$HOME")-proj")"
tu_form="$(printf '%s' "$HOME" | tr '/.' '--')"
add_ticket "\\n### dir #866 — the home's own project dir — R4 — → pool\\n\\nMemory: $(home_slug "$HOME")/memory/MEMORY.md\\nNested: $nested/memory\\nTranscripts: $tu_form/s.jsonl\\n\\n**Cloud:** yes (2026-10-27, fixture)\\n"
cb "$P" "dir #866" --out "$F/fl.md"
check_status "T12 a HOME named first_last builds" 0 "$STATUS"
fl="$(cat "$F/fl.md")"
check_contains "T12 … its CLI-style slug (first-last) rewritten" "$fl" "Claude project dir: -Users-x-proj"
check_absent "T12 … no slug left" "$fl" "first-last"
check_contains "T12 the bare home slug before a / → -Users-x/" "$fl" "Memory: -Users-x/memory/MEMORY.md"
check_contains "T12 a slug nested after a - rewritten" "$fl" "Nested: -private-tmp-claude-$(id -u)--Users-x-proj/memory"
check_contains "T12 the tu_project_slug form (first_last kept) rewritten" "$fl" "Transcripts: -Users-x/s.jsonl"
check_absent "T12 … no tu form left" "$fl" "first_last"
# A home's slug is rewritten only where it starts a token: never glued after a letter or digit (privacy first: one
# glued before a letter is still rewritten, so a sibling's `-…-root2-…` hides the login too).
export HOME="$SANDBOX/x/root"
mkdir -p "$HOME"
fx
rs="$(home_slug "$HOME")"
add_ticket "\\n### dir #867 — slug-shaped words — R4 — → pool\\n\\nGlued: tools/state${rs}-migrate.sh as a non${rs}-user; ${rs}2-proj hides.\\nReal: ${rs}-proj and ${rs}/memory.\\n\\n**Cloud:** yes (2026-10-27, fixture)\\n"
cb "$P" "dir #867" --out "$F/root.md"
check_status "T12 a HOME named root builds" 0 "$STATUS"
rt="$(part_of "$F/root.md" ticket)"
check_contains "T12 the slug glued after a letter unchanged; a sibling's slug rewritten" "$rt" "Glued: tools/state${rs}-migrate.sh as a non${rs}-user; -Users-x2-proj hides."
check_contains "T12 the slug standing alone rewritten" "$rt" "Real: -Users-x-proj and -Users-x/memory."
# HOME=/root itself: its slug `-root` sits inside ordinary words, which a sandbox home's long slug never could. Only
# HOME changes for this one run: every path the tool or the scanner writes under HOME is pinned into the sandbox
# (the ledger and briefs by fx, the impact store and log by tests/lib.sh), and git's global config stays the
# sandbox file tests/lib.sh exported.
fx
add_ticket "\\n### dir #877 — HOME=/root's slug in words — R4 — → pool\\n\\nRun tools/state-root-migrate.sh as a non-root-user on claude/cloud-root-12.\\nSibling: -root2-proj hides; real: -root-proj and -root/memory.\\nNested: -private-tmp-claude-0--root-proj.\\n\\n**Cloud:** yes (2026-10-27, fixture)\\n"
HOME=/root cb "$P" "dir #877" --out "$F/slash-root.md"
check_status "T12 HOME=/root builds" 0 "$STATUS"
rt="$(part_of "$F/slash-root.md" ticket)"
check_contains "T12 HOME=/root: state-root-migrate, non-root-user, cloud-root-12 unchanged" "$rt" "Run tools/state-root-migrate.sh as a non-root-user on claude/cloud-root-12."
check_contains "T12 HOME=/root: a sibling's -root2- and the -root slug rewritten" "$rt" "Sibling: -Users-x2-proj hides; real: -Users-x-proj and -Users-x/memory."
check_contains "T12 HOME=/root: the slug nested after a - rewritten" "$rt" "Nested: -private-tmp-claude-0--Users-x-proj."
# A HOME with a trailing slash is the same home: `~/notes`, never `~notes`.
export HOME="$SANDBOX/home.slash/"
mkdir -p "$HOME"
fx
add_ticket "\\n### dir #868 — a trailing-slash home — R4 — → pool\\n\\nNotes: ${HOME%/}/notes/slash.md and $(home_slug "${HOME%/}")-proj\\n\\n**Cloud:** yes (2026-10-27, fixture)\\n"
cb "$P" "dir #868" --out "$F/slash.md"
check_status "T12 a HOME with a trailing slash builds" 0 "$STATUS"
sl="$(cat "$F/slash.md")"
# shellcheck disable=SC2088
check_contains "T12 … its path → ~/notes" "$sl" "Notes: ~/notes/slash.md and -Users-x-proj"
check_absent "T12 … never ~notes" "$sl" "~notes"
export HOME="$HOME_SAVED"
# HOME unset: the passwd entry's home is still a home to rewrite.
fx
pw_home="$(unset HOME; CDPATH='' cd ~ 2>/dev/null && pwd)" || pw_home=""
if [ -n "$pw_home" ] && [ "$pw_home" != / ]; then
  add_ticket "\\n### dir #869 — the passwd home — R4 — → pool\\n\\nPasswd: ${pw_home}/notes/pw.md and $(home_slug "$pw_home")-proj\\n\\n**Cloud:** yes (2026-10-27, fixture)\\n"
  OUT="$(env -u HOME "$BRIEF_TOOL" "$P" "dir #869" --out "$F/pw.md" 2>&1 </dev/null)"; STATUS=$?
  check_status "T12 HOME unset builds" 0 "$STATUS"
  # shellcheck disable=SC2088
  check_contains "T12 HOME unset: the passwd home's path and slug rewritten" "$(part_of "$F/pw.md" ticket)" "Passwd: ~/notes/pw.md and -Users-x-proj"
else
  echo "  SKIP  T12 HOME unset: this user's passwd entry has no usable home"
fi
fx
unset SECRET_SCAN_PERSONAL_FILE
cb "$P" "dir #801"
check_status "T12 SECRET_SCAN_PERSONAL_FILE unset, no default file → exit 2" 2 "$STATUS"
check_contains "T12 fail-closed names the list" "$OUT" "personal-literals list"
nothing_written "T12 fail-closed"
export SECRET_SCAN_PERSONAL_FILE=/dev/null
cb "$P" "dir #801"
check_status "T12 /dev/null opts out → 0" 0 "$STATUS"

# --- T13: the model mapping (read back from the ledger row) -----------------------------------------------------
fx
cb "$P" "dir #801"; check_eq "T13 mid tier + high → sonnet/high" "sonnet/high" "$(row_of 'dir #801' | cut -f5)"
cb "$P" "dir #802" --eligible; check_eq "T13 top tier + xhigh → opus/xhigh" "opus/xhigh" "$(row_of 'dir #802' | cut -f5)"
cb "$P" "dir #824"; check_eq "T13 light tier + low → haiku/low" "haiku/low" "$(row_of 'dir #824' | cut -f5)"
cb "$P" "dir #825"; check_eq "T13 no Model rec → sonnet/medium" "sonnet/medium" "$(row_of 'dir #825' | cut -f5)"
check_contains "T13 no Model rec warns" "$OUT" "sonnet + medium, the default"
cb "$P" "dir #826"
check_status "T13 an unmapped tier → exit 3" 3 "$STATUS"
cb "$P" "dir #832"; check_eq "T13 'maximum care' is not the effort max → opus/medium" "opus/medium" "$(row_of 'dir #832' | cut -f5)"
cb "$P" "dir #833"; check_eq "T13 mid tier, no effort word → sonnet/medium" "sonnet/medium" "$(row_of 'dir #833' | cut -f5)"
check_contains "T13 no effort word warns" "$OUT" "no effort word"
cb "$P" "dir #834"; check_eq "T13 two tiers: the first decides → sonnet/high" "sonnet/high" "$(row_of 'dir #834' | cut -f5)"

# --- dir #913 (3): a body line glued to a heading with no recognized tail --------------------------------------------
# backlog_ticket_blocks folds such a line into the heading (its lib documents the residual and stays unchanged), so G2
# would read a 📐 from body text: the cloud route refuses and asks for the blank line.
fx
add_ticket '\n### dir #890 — glued prose under an ungraded heading\nThis body line is glued to it and says 📐 SPEC-READY.\n\n**Cloud:** yes (2026-10-27, fixture)\n'
add_ticket '\n### dir #891 — a glued line under a graded heading — R4 — → pool\nThis body line is glued but the heading is finished.\n\n**Cloud:** yes (2026-10-27, fixture)\n'
add_ticket '\n### dir #892 — a wrapped heading whose tail\nlands on its second line — R4 — → pool\n\n**Cloud:** yes (2026-10-27, fixture)\n'
add_ticket '\n### dir #893 — glued prose carrying a grade\nThe plan is R4 ready — R4 — here.\n\n**Cloud:** yes (2026-10-27, fixture)\n'
add_ticket '\n### dir #894 — an ungraded heading with its blank line\n\nA body line saying 📐 SPEC-READY, after the blank line.\n\n**Cloud:** yes (2026-10-27, fixture)\n'
cb "$P" "dir #890"
check_status "T23 a glued body line carrying 📐 under an ungraded heading → exit 3" 3 "$STATUS"
check_contains "T23 … refused as G2" "$OUT" "refused: G2"
check_contains "T23 … naming the glued line" "$OUT" "This body line is glued to it and says 📐 SPEC-READY."
glued_n="$(grep -n 'This body line is glued to it' "$P/BACKLOG.md" | cut -d: -f1)"
check_contains "T23 … and its line number" "$OUT" "line $glued_n of"
check_contains "T23 … asking for a blank line after the heading" "$OUT" "blank line"
nothing_written "T23"
cb "$P" "dir #891"
check_status "T23 a glued line under a FINISHED heading is the lib's own case → passes" 0 "$STATUS"
cb "$P" "dir #892"
check_status "T23 a wrapped heading whose tail lands on a later line still passes" 0 "$STATUS"
cb "$P" "dir #893"
check_status "T23 a glued line whose text reads as a tail finishes the heading (the lib's grammar) → passes G2" 0 "$STATUS"
cb "$P" "dir #894"
check_status "T23 the same words after a blank line: the heading has no grade → exit 3" 3 "$STATUS"
check_contains "T23 … that is the plain no-grade refusal, not the glued one" "$OUT" "no readiness grade on the heading"
check_absent "T23 … which does not ask for a blank line" "$OUT" "directly under"

# --- T14: the ledger ----------------------------------------------------------------------------------------------
fx
cb "$P" "dir #801" --credit-before 200
check_eq "T14 a build writes one built row" "built" "$(status_of 'dir #801')"
check_eq "T14 the row is keyed by repo" "example/proj" "$(row_of 'dir #801' | cut -f2)"
check_eq "T14 the credit cell" "200" "$(row_of 'dir #801' | cut -f7)"
check_eq "T14 a row has 15 cells" "15" "$(row_of 'dir #801' | awk -F'\t' '{print NF}')"
check_eq "T14 the header" "$(printf 'built\trepo\tticket\tbranch\tmodel/effort\tbrief bytes\tcredit before\tstatus\tcredit after\toverlap\tlanded\tlanding exit\thead SHA\tPR\tsession')" "$(head -1 "$CLOUD_LEDGER")"
cb "$P" "dir #801"
check_eq "T14 a rebuild replaces the built row: one row" "1" "$(row_of 'dir #801' | grep -c '')"
check_eq "T14 the rebuild's credit cell is fresh" "?" "$(row_of 'dir #801' | cut -f7)"
for s in dispatched abandoned; do
  set_status "dir #801" "$s"
  cb "$P" "dir #801"
  check_status "T14 a $s row refuses a build without --redispatch" 3 "$STATUS"
  cb "$P" "dir #801" --redispatch
  check_status "T14 a $s row builds with --redispatch" 0 "$STATUS"
  check_eq "T14 $s + --redispatch: one row" "1" "$(row_of 'dir #801' | grep -c '')"
done
set_status "dir #801" landed
cb "$P" "dir #801" --redispatch
check_status "T14 a landed row always refuses" 3 "$STATUS"

# --- T14b: the lock -----------------------------------------------------------------------------------------------
fx
cb "$P" "dir #801"
LOCK="$F/store/ledger.lock"
mkdir "$LOCK"
before="$(cksum_of "$CLOUD_LEDGER")"
cb "$P" "dir #801"
check_status "T14b a held lock → the second writer exits 2" 2 "$STATUS"
check_contains "T14b it names the lock" "$OUT" "ledger.lock"
check_eq "T14b the row untouched" "$before" "$(cksum_of "$CLOUD_LEDGER")"
( sleep 3; rmdir "$LOCK" ) &
cb "$P" "dir #801"
wait
check_status "T14b a lock released after 3 s lets it proceed" 0 "$STATUS"
mkdir "$LOCK"
touch -t 202001010000 "$LOCK"
cb "$P" "dir #801"
check_status "T14b a lock older than 10 minutes → exit 2" 2 "$STATUS"
check_contains "T14b stderr says stale" "$OUT" "stale"
check_dir "T14b the stale lock is left in place" "$LOCK"
rmdir "$LOCK"
# The row check sits inside the lock: a row set to dispatched while --dispatch waits refuses it. The old brief
# goes first, so the wait below sees this run's own write (it comes after the first row check, before the lock).
mkdir "$LOCK"
rm -f "$CLOUD_BRIEF_DIR/example-proj--dir-801.md"
( "$BRIEF_TOOL" "$P" "dir #801" --dispatch > "$F/bg.out" 2>&1 </dev/null; echo $? > "$F/bg.rc" ) &
n=0; while [ ! -f "$CLOUD_BRIEF_DIR/example-proj--dir-801.md" ] && [ "$n" -lt 300 ]; do sleep 0.1; n=$((n + 1)); done
set_status "dir #801" dispatched
rmdir "$LOCK"
wait
check_eq "T14b a row set to dispatched while --dispatch waited → exit 3" "3" "$(cat "$F/bg.rc")"
check_nofile "T14b the stub claude was never called" "$CLAUDE_FX/calls"

# --- T15 / T15b (A3): the brief's shape and the protocol's pins ----------------------------------------------------
fx
cb "$P" "dir #801" --out "$F/b801.md"
markers="$(grep -E '^=== [a-z ]+ ===$' "$F/b801.md" | tr '\n' '|')"
check_eq "T15 part markers in order" "=== protocol ===|=== ticket ===|=== spec ===|=== rails ===|=== end of brief ===|" "$markers"
check_eq "T15 the last line" "=== end of brief ===" "$(tail -n 1 "$F/b801.md")"
proto="$(part_of "$F/b801.md" protocol)"
for ph in '<repo>' '<ticket>' '<branch>' '<default>' '<keel-sha>' '<keel-origin>'; do
  check_absent "T15 no $ph left in the protocol part" "$proto" "$ph"
done
flat="$(flatten_ws <<< "$proto")"
B=claude/cloud-dir-801
for needle in \
  "the brief's very LAST line must be \`=== end of brief ===\`" \
  "git clone https://github.com/rockerlabs/keel \"\$KT/keel\" && git -C \"\$KT/keel\" checkout -q $ENG_PUBLISHED" \
  "check that the printed sha equals \`$ENG_PUBLISHED\`" \
  "a sha mismatch (never retried): push nothing, end per (j)'s no-PR form, stop" \
  "git config --local core.hooksPath \"\$KT/keel-guard\"" \
  "printf 'refs/heads/x %s refs/heads/main %s\\n' \"\$S\" \"\$S\" | \"\$KT/keel-guard/pre-push\"\` exits non-zero" \
  "printf 'refs/heads/$B %s refs/heads/main %s\\n' \"\$S\" \"\$S\" | \"\$KT/keel-guard/pre-push\"\` exits non-zero" \
  "printf '(delete) 0000000000000000000000000000000000000000 refs/heads/$B %s\\n' \"\$S\" | \"\$KT/keel-guard/pre-push\"\` exits non-zero" \
  "printf 'refs/heads/x %s refs/heads/$B %s\\n' \"\$S\" \"\$S\" | \"\$KT/keel-guard/pre-push\"\` exits 0" \
  "Before every later push, beside the scan, re-check that \`git config --get core.hooksPath\` still prints \`\$KT/keel-guard\` and that \`\$KT/keel-guard/pre-push\` is still an executable file" \
  "re-run (a1) and (a3) with a fresh \`\$KT\`" \
  "What to push: only \`HEAD:refs/heads/$B\`" \
  "Before every push, \`\"\$KT/keel/tools/secret-guard/secret-scan.sh\" --range \"origin/main..HEAD\"\` must exit 0" \
  "\`git commit --amend\` with the message minus that line" \
  "Never write the text \`secret-scan:allow\` anywhere" \
  "Run \`/code-review high\`" \
  "\`draft=true\`" \
  "You never merge, never mark a PR ready and never close one" \
  "\`## Landing notes\`" \
  "ask it once in chat — one message with the options and your recommendation — AND write it into Landing notes' open questions" \
  "never pass \`--no-verify\` to any git command" \
  "\`no PR: <the step> — <the reason>\`" \
  "\`abandon: docs/cloud.md, Abandoning — ledger row example/proj dir #801\`" \
  "\"\$KT/keel/tools/secret-guard/secret-scan.sh\" -- <file>\` must exit 0" \
  "\`gh api repos/example/proj/pulls\`" \
  "\`gh api \"repos/example/proj/commits/<sha>/check-runs\"\`" \
  "one read every 2 minutes, at most 60 minutes per push" \
  "An empty list is pending, not green" \
  "\`gh pr checks\` is GraphQL and blocked in the VM"; do
  check_contains "T15b pin: ${needle:0:70}" "$flat" "$needle"
done
check_absent "T15b no 'Russian' in the protocol part" "$proto" "Russian"
g_ids="$(grep -nE '(^|[^A-Za-z0-9])G[0-9]b?([^A-Za-z0-9]|$)' <<< "$proto" || true)"
check_eq "T15b no G-row id in the protocol part" "" "$g_ids"
check_eq "T15b no ticket id in the template" "0" "$(grep -cE 'dir #[0-9]|KB\.[0-9]' "$REPO_ROOT/templates/cloud-protocol.md")"
check_eq "T15b rockerlabs/keel occurs once in the protocol part" "1" "$(grep -c 'rockerlabs/keel' <<< "$proto")"
check_contains "T15b … and only as <keel-origin> in the (a1) clone line" "$(grep 'rockerlabs/keel' <<< "$proto")" "git clone https://github.com/rockerlabs/keel \"\$KT/keel\""
check_contains "T15b the work repository is the fixture's" "$flat" "on a clone of \`example/proj\`"

# --- T3b: the guard, installed by the protocol's own block, against real pushes -----------------------------------
block="$(awk '/^\(a3\)/ { a = 1 } a && /^```sh$/ { f = 1; next } f && /^```$/ { exit } f' <<< "$proto")"
check_contains "T3b the install block was extracted" "$block" "KEEL_CLOUD_GUARD"
C="$F/vm"
KT="$F/kt"
git clone -q "$F/proj-origin.git" "$C"
git -C "$C" checkout -q -B "$B" origin/main
( cd "$C" && KT="$KT" bash -c "$block" )
check_status "T3b the install block runs" 0 "$?"
check_eq "T3b core.hooksPath names the guard" "$KT/keel-guard" "$(git -C "$C" config --get core.hooksPath)"
S="$(git -C "$C" rev-parse HEAD)"
proof_rcs=""
while IFS= read -r cmd; do
  ( cd "$C" && KT="$KT" S="$S" bash -c "$cmd" ) >/dev/null 2>&1
  proof_rcs="$proof_rcs$?,"
done < <(grep -oE "^- \`printf '[^\`]*\`" <<< "$proto" | sed -e 's/^- `//' -e 's/`$//')
check_eq "T3b the proof, in git's field order: non-zero, non-zero, non-zero, 0" "1,1,1,0," "$proof_rcs"
main_before="$(git -C "$F/proj-origin.git" rev-parse refs/heads/main)"
git -C "$C" commit -q --allow-empty -m "vm work"
run git -C "$C" push origin HEAD:refs/heads/main
check_ne "T3b a push to the default branch is refused" 0 "$STATUS"
check_contains "T3b … by the guard" "$OUT" "keel cloud guard: refused"
run git -C "$C" push origin HEAD:refs/heads/other
check_ne "T3b a push to another ref is refused" 0 "$STATUS"
run git -C "$C" push origin "HEAD:refs/heads/$B-x"
check_ne "T3b a push to <branch>-x is refused (no prefix match)" 0 "$STATUS"
run git -C "$C" push origin "HEAD:refs/heads/$B" HEAD:refs/heads/main
check_ne "T3b two refspecs, the branch first, are refused" 0 "$STATUS"
run git -C "$C" push origin HEAD:refs/heads/main "HEAD:refs/heads/$B"
check_ne "T3b two refspecs, the default first, are refused" 0 "$STATUS"
check_eq "T3b the default branch never moved" "$main_before" "$(git -C "$F/proj-origin.git" rev-parse refs/heads/main)"
run git -C "$C" push origin "HEAD:refs/heads/$B"
check_status "T3b a push to <branch> is accepted" 0 "$STATUS"
run git -C "$C" push origin ":refs/heads/$B"
check_ne "T3b deleting <branch> is refused" 0 "$STATUS"
check_eq "T3b <branch> still exists" "$(git -C "$C" rev-parse HEAD)" "$(git -C "$F/proj-origin.git" rev-parse "refs/heads/$B" 2>/dev/null)"
hook="$KT/keel-guard/pre-push"
printf 'refs/heads/x %s refs/heads/%s %s\nrefs/heads/x %s refs/heads/main %s\n' "$S" "$B" "$S" "$S" "$S" | "$hook" 2>/dev/null
check_ne "T3b the hook on two lines, the allowed one first → non-zero" 0 "$?"
printf 'refs/heads/x %s refs/heads/main %s\nrefs/heads/x %s refs/heads/%s %s\n' "$S" "$S" "$S" "$B" "$S" | "$hook" 2>/dev/null
check_ne "T3b the hook on two lines, the default one first → non-zero" 0 "$?"
printf 'refs/heads/%s %s refs/heads/x %s\n' "$B" "$S" "$S" | "$hook" 2>/dev/null
check_ne "T3b the hook keys on field 3 (the branch in field 1 pushed elsewhere → non-zero)" 0 "$?"
printf 'refs/heads/x 0000000000000000000000000000000000000000 refs/heads/%s %s\n' "$B" "$S" | "$hook" 2>/dev/null
check_ne "T3b an all-zero local sha to <branch> is a deletion (no \`(delete)\` spelling needed) → non-zero" 0 "$?"

# --- T16: the keel commit, the engine, <repo> forms ----------------------------------------------------------------
check_contains "T16 <keel-sha> is the merge-base with origin/main" "$proto" "checkout -q $ENG_PUBLISHED"
check_absent "T16 … not the engine's local HEAD" "$proto" "$ENG_HEAD"
pass "T16 an engine origin with a .git suffix matches the default CLOUD_KEEL_ORIGIN (the build above)"
fx
CLOUD_KEEL_ORIGIN=https://github.com/someone/fork cb "$P" "dir #801"
check_status "T16 an engine whose origin is not CLOUD_KEEL_ORIGIN → exit 2" 2 "$STATUS"
check_contains "T16 … no published keel commit" "$OUT" "no published keel commit"
TARBALL="$F/tarball"
mkdir -p "$TARBALL/templates"
cp -R "$ENG/tools" "$TARBALL/"
cp "$ENG/templates/cloud-protocol.md" "$TARBALL/templates/"
run "$TARBALL/tools/cloud-brief.sh" "$P" "dir #801"
check_status "T16 an engine with no .git → exit 2" 2 "$STATUS"
check_contains "T16 … no git checkout" "$OUT" "is no git checkout"
nothing_written "T16"
git -C "$P" worktree add -q "$F/wt" -b wt-branch
cb "$F/wt" "dir #801"
check_status "T16 <repo> given as a worktree path → 0" 0 "$STATUS"
check_contains "T16 … resolved to the main checkout" "$OUT" "$(cd "$P" && pwd -P)"
run_in "$F" "$BRIEF_TOOL" proj "dir #801"
check_status "T16 <repo> given as a relative path → 0" 0 "$STATUS"
CLOUD_LEDGER=store/rel.tsv run_in "$F" "$BRIEF_TOOL" proj "dir #801"
check_file "T16 a relative CLOUD_LEDGER is made absolute against the start directory" "$F/store/rel.tsv"
mkdir -p "$F/reltmp"
TMPDIR=reltmp run_in "$F" "$BRIEF_TOOL" proj "dir #801"
check_status "T16 a relative TMPDIR → 0 (made absolute before the scan's cd)" 0 "$STATUS"
mkdir -p "$F/decoy/proj"
CDPATH="$F/decoy" run_in "$F" "$BRIEF_TOOL" proj "dir #801"
check_status "T16 an exported CDPATH naming a same-named dir → 0" 0 "$STATUS"
check_contains "T16 … the relative <repo> still resolves to the right checkout" "$OUT" "$(cd "$P" && pwd -P) <PR#>"

# --- T19: slugs ---------------------------------------------------------------------------------------------------
fx
for pair in "dir #801=claude/cloud-dir-801" "KB.34=claude/cloud-kb-34" "H.130=claude/cloud-h-130" "34.=claude/cloud-34"; do
  id="${pair%%=*}" want="${pair#*=}"
  cb "$P" "$id"
  check_eq "T19 $id → $want" "$want" "$(row_of "$id" | cut -f4)"
done

# --- T20 / T20b: --check --------------------------------------------------------------------------------------------
fx
cbo "$P" "dir #802" --check
check_status "T20 --check on a no-verdict ticket → 4" 4 "$STATUS"
check_contains "T20 … its receipt" "$(tail -n 1 <<< "$OUT")" "cloud-check: 4 dir #802 "
cbo "$P" "dir #801" --check
check_status "T20 --check on an eligible ticket → 0" 0 "$STATUS"
check_eq "T20 the last stdout line is the receipt" "cloud-check: 0 dir #801 $(git -C "$P" rev-parse HEAD)" "$(tail -n 1 <<< "$OUT")"
nothing_written "T20 eligible"
cbo "$P" "dir #809" --check
check_status "T20 --check on a refusal → 3" 3 "$STATUS"
check_contains "T20 a refusal's receipt" "$(tail -n 1 <<< "$OUT")" "cloud-check: 3 "
git -C "$P" checkout -q -b elsewhere
cbo "$P" "dir #801" --check
check_status "T20 --check with the main checkout on another branch → 0 (no G9)" 0 "$STATUS"
git -C "$P" checkout -q main
cbo "$P" "dir #823" --check
check_status "T20 --check with a token in the ticket → 1" 1 "$STATUS"
cbo "$P" "dir #822" --check
check_status "T20 --check on a 'for the design' Model rec → 3" 3 "$STATUS"
check_contains "T20 … G8" "$ERR" "refused: G8"
cbo "$P" "dir #829" --check
check_status "T20 --check on a G6 refusal → 3" 3 "$STATUS"
check_contains "T20 … G6" "$ERR" "refused: G6"
unprotect
cbo "$P" "dir #801" --check
check_status "T20 --check on a G1b refusal → 3" 3 "$STATUS"
check_contains "T20 … G1b" "$ERR" "refused: G1b"
nothing_written "T20"
gh_ok "$GH_FX" example/proj
cb "$P" "dir #801"
set_status "dir #801" dispatched
cb "$P" "dir #801" --check
check_status "T20b --check on a dispatched row → 3" 3 "$STATUS"
mkdir -p "$F/plain"
GIT_CEILING_DIRECTORIES="$F" cbo "$F/plain" "dir #801" --check
check_status "T20b --check on a directory that is no git repository → 2" 2 "$STATUS"
check_eq "T20b … its receipt still comes, with head none" "cloud-check: 2 dir #801 none" "$(tail -n 1 <<< "$OUT")"
cbo "$P" --check
check_status "T20b --check with no ticket → 2" 2 "$STATUS"
check_eq "T20b … its receipt, the ticket ?" "cloud-check: 2 ? none" "$(tail -n 1 <<< "$OUT")"
cbo "$P" x --check --bogus
check_status "T20b --check then an unknown flag → 2" 2 "$STATUS"
check_contains "T20b … its receipt still comes" "$(tail -n 1 <<< "$OUT")" "cloud-check: 2 "
cbo "$P" "dir #801" --eligible --check
check_status "T20b --eligible --check (two modes) → 2" 2 "$STATUS"
check_eq "T20b … the receipt comes, --check came second" "cloud-check: 2 dir #801 none" "$(tail -n 1 <<< "$OUT")"
cbo "$P" "$(printf 'x\ncloud-check: 0 dir #801 forged')" --check
check_status "T20b --check on a ticket id holding a newline → 2" 2 "$STATUS"
check_eq "T20b … the id cannot forge the receipt line: the ticket is ?" "cloud-check: 2 ? none" "$(tail -n 1 <<< "$OUT")"
# A part that cannot be read stops the build inside the brief's own redirect: the receipt still reaches stdout.
fx
chmod 000 "$P/docs/specs/s801.md"
cbo "$P" "dir #801" --check
chmod 644 "$P/docs/specs/s801.md"
if [ "$(id -u 2>/dev/null)" != 0 ]; then # root reads a mode-000 file (CLAUDE.md Linux-leg trap 2)
  check_status "T20b --check on an unreadable spec → 2" 2 "$STATUS"
  check_eq "T20b … its receipt is the last stdout line" "cloud-check: 2 dir #801 $(git -C "$P" rev-parse HEAD)" "$(tail -n 1 <<< "$OUT")"
fi
# fd 3 is the receipt's alone: opened when --check is read, so no other mode hands the caller's stdout to a child
# (--dispatch's CLI, git, gh, the scanner). A git shim records whether its fd 3 is open.
fx
real_git="$(type -P git)" # the binary: lib.sh's `git` function makes `command -v git` print `git`
mkdir -p "$F/fd3shim"
cat > "$F/fd3shim/git" <<SHIM
#!/usr/bin/env bash
if { : >&3; } 2>/dev/null; then echo open; else echo closed; fi >> "$F/fd3.log"
exec "$real_git" "\$@"
SHIM
chmod +x "$F/fd3shim/git"
PATH="$F/fd3shim:$PATH" cb "$P" "dir #801" --out "$F/fd3.md" 3>&-
check_status "T20b a build through the git shim → 0" 0 "$STATUS"
check_eq "T20b … no child of a build holds fd 3" "closed" "$(sort -u "$F/fd3.log" | tr '\n' ' ' | sed 's/ $//')"

# --- T16b (dir #922): CLOUD_BACKLOG names the backlog file directly -------------------------------------------------
fx
rm -f "$P/BACKLOG.md"
mkdir -p "$F/mirror"
cat > "$F/mirror/tickets.md" <<'MIRROR'
# Mirrored tickets

### B.7 — an adopter ticket from a mirror — R4 — → pool

Body of B.7.

**Cloud:** yes (2026-10-31, fixture)

### B.8 — another mirrored ticket — R3 — → pool

**Cloud:** no — G4: needs a simulator (2026-10-31, fixture)
MIRROR
CLOUD_BACKLOG="$F/mirror/tickets.md" cb "$P" "B.7" --out "$F/b-b7.md"
check_status "T16b CLOUD_BACKLOG: a mirrored ticket builds with no BACKLOG.md in the project" 0 "$STATUS"
check_contains "T16b … the ticket part holds its heading" "$(part_of "$F/b-b7.md" ticket)" "### B.7 — an adopter ticket from a mirror"
check_contains "T16b … and its body" "$(part_of "$F/b-b7.md" ticket)" "Body of B.7."
check_absent "T16b … and not the sibling" "$(part_of "$F/b-b7.md" ticket)" "B.8"
CLOUD_BACKLOG="$F/mirror/tickets.md" cbo "$P" "B.8" --check
check_contains "T16b the verdict line is read from the file" "$ERR$OUT" "G4"
pushd "$F" >/dev/null && CLOUD_BACKLOG="mirror/tickets.md" cb "$P" "B.7" --out "$F/b-rel.md"; popd >/dev/null || exit
check_status "T16b a relative CLOUD_BACKLOG resolves against the start directory" 0 "$STATUS"
CLOUD_BACKLOG="$F/mirror/missing.md" cb "$P" "B.7"
check_status "T16b a missing CLOUD_BACKLOG file → exit 2" 2 "$STATUS"
check_contains "T16b … it is named" "$OUT" "$F/mirror/missing.md"
CLOUD_BACKLOG='' cb "$P" "B.7"
check_status "T16b an empty CLOUD_BACKLOG is set, not unset → exit 2" 2 "$STATUS"
CLOUD_BACKLOG="$F/mirror" cb "$P" "B.7"
check_status "T16b a CLOUD_BACKLOG directory → exit 2" 2 "$STATUS"
CLOUD_BACKLOG="$F/mirror/missing.md" cbo "$P" --sweep
check_status "T16b --sweep with a missing CLOUD_BACKLOG → exit 2" 2 "$STATUS"
CLOUD_BACKLOG="$F/mirror/tickets.md" cbo "$P" --sweep
check_status "T16b --sweep reads the file → 0" 0 "$STATUS"
check_contains "T16b … it lists the file's open ticket" "$OUT" "B.7	R4	yes"
check_contains "T16b … and the no verdict's row" "$OUT" "B.8	R3	no — G4"

# --- T17: --sweep --------------------------------------------------------------------------------------------------
fx
cb "$P" "dir #812"; set_status "dir #812" dispatched
cb "$P" "dir #814"; set_status "dir #814" landed
set_cell "dir #814" 13 aaaa
printf '[{"number":7,"head":{"sha":"bbbb"}}]\n' > "$GH_FX/api/repos_example_proj_pulls_head_example_claude_cloud-dir-814_state_all.json"
printf '[]\n' > "$GH_FX/api/repos_example_proj_pulls_head_example_claude_cloud-dir-812_state_all.json"
cb "$P" "dir #815"; set_status "dir #815" dispatched
printf '[{"number":4,"head":{"sha":"cccc"}}]\n' > "$GH_FX/api/repos_example_proj_pulls_head_example_claude_cloud-dir-815_state_all.json"
bl_before="$(cksum_of "$P/BACKLOG.md")" lg_before="$(cksum_of "$CLOUD_LEDGER")"
cbo "$P" --sweep
check_status "T17 --sweep → 0" 0 "$STATUS"
check_contains "T17 lists a yes ticket" "$OUT" "dir #801	R4	yes"
check_contains "T17 lists a no-verdict ticket with —" "$OUT" "dir #802	R4	—"
check_contains "T17 lists a no ticket with its row" "$OUT" "dir #803	R3	no — G4"
check_contains "T17 lists a 📐-only ticket" "$OUT" "dir #812	📐	yes"
check_absent "T17 skips a closed ticket" "$OUT" "dir #804"
check_absent "T17 skips an R2 ticket" "$OUT" "dir #809	"
check_contains "T17 a dispatched row with its age and no PR" "$OUT" "dispatched	dir #812	claude/cloud-dir-812	since $TODAY (0 days)	no PR"
check_contains "T17 a dispatched row with the stub gh's PR answer" "$OUT" "dispatched	dir #815	claude/cloud-dir-815	since $TODAY (0 days)	PR #4"
check_contains "T17 a landed row whose head moved is stale" "$OUT" "STALE: the PR head is bbbb, landed at aaaa"
check_eq "T17 the backlog unchanged" "$bl_before" "$(cksum_of "$P/BACKLOG.md")"
check_eq "T17 the ledger unchanged" "$lg_before" "$(cksum_of "$CLOUD_LEDGER")"
touch "$GH_FX/fail"
cbo "$P" --sweep
check_status "T17 gh failing during --sweep → exit 2" 2 "$STATUS"
check_contains "T17 … the dispatched row's PR is unknown" "$OUT" "dispatched	dir #812	claude/cloud-dir-812	since $TODAY (0 days)	PR unknown (gh failed)"
check_contains "T17 … the landed row's state is unknown" "$OUT" "landed	dir #814	claude/cloud-dir-814	PR unknown (gh failed)	unknown"
check_contains "T17 … gh's own stderr passes through" "$ERR" "error connecting"
check_contains "T17 … and the failure is named" "$ERR" "PR columns"
rm "$GH_FX/fail"
printf '[{"number":7,"head":{"sha":"aaaa"}}]\n' > "$GH_FX/api/repos_example_proj_pulls_head_example_claude_cloud-dir-814_state_all.json"
cbo "$P" --sweep
check_contains "T17 a landed row at its PR head is current" "$OUT" "landed	dir #814	claude/cloud-dir-814	PR #7	current"
set_cell "dir #814" 12 3
cbo "$P" --sweep
check_contains "T17 a landed row whose last landing check failed is stale" "$OUT" "STALE: the last landing check exited 3"
# A same-day row is 0 days in every zone: a zone 14 h ahead of UTC (no tzdata: UTC, still passing) and a POSIX
# zone 12 h behind it (no tzdata needed), the build and the sweep both in it.
for zone in Pacific/Kiritimati XXX+12; do
  fx
  TZ="$zone" cb "$P" "dir #812"; set_status "dir #812" dispatched
  printf '[]\n' > "$GH_FX/api/repos_example_proj_pulls_head_example_claude_cloud-dir-812_state_all.json"
  TZ="$zone" cbo "$P" --sweep
  check_contains "T17 TZ=$zone: a row built today is 0 days old" "$OUT" "dispatched	dir #812	claude/cloud-dir-812	since $(TZ="$zone" date +%F) (0 days)"
done
# A row dated tomorrow (a clock set back since) reads -1 days, not 0: the rounding is symmetric. Tomorrow is today's
# local noon plus a day: now + 86400 s lands two dates ahead from late evening before a 23-hour (DST) day.
fx
cb "$P" "dir #812"; set_status "dir #812" dispatched
printf '[]\n' > "$GH_FX/api/repos_example_proj_pulls_head_example_claude_cloud-dir-812_state_all.json"
today="$(date +%F)"
e=$(( $(date -d "$today 12:00:00" +%s 2>/dev/null || date -j -f '%Y-%m-%d %H:%M:%S' "$today 12:00:00" +%s) + 86400 ))
tomorrow="$(date -d "@$e" +%F 2>/dev/null || date -r "$e" +%F)"
set_cell "dir #812" 1 "$tomorrow"
cbo "$P" --sweep
check_contains "T17 a row dated tomorrow is -1 days old" "$OUT" "since $tomorrow (-1 days)"
# A failed `cloud-land.sh --ticket` run records the PR (cell 14) but leaves the branch cell: the sweep reads the
# recorded PR first, so a PR from another branch never reads as "no PR" (the abandon trigger).
fx
cb "$P" "dir #812"; set_status "dir #812" dispatched
set_cell "dir #812" 12 3; set_cell "dir #812" 13 eeee; set_cell "dir #812" 14 9
printf '[]\n' > "$GH_FX/api/repos_example_proj_pulls_head_example_claude_cloud-dir-812_state_all.json"
printf '{"number":9,"head":{"sha":"eeee"}}\n' > "$GH_FX/api/repos_example_proj_pulls_9.json"
cbo "$P" --sweep
check_status "T17 a dispatched row with a recorded PR → 0" 0 "$STATUS"
check_contains "T17 … shows the recorded PR, not its branch's (none)" "$OUT" "dispatched	dir #812	claude/cloud-dir-812	since $TODAY (0 days)	PR #9"
fx
printf '# Backlog\n\n## Open\n\n### dir #1 — closed — R4 — ✅ DONE\n' > "$P/BACKLOG.md"
cbo "$P" --sweep
check_status "T17 a sweep with no open R3/R4/📐 ticket → 0" 0 "$STATUS"
check_eq "T17 … a header and no ticket rows" "0" "$(grep -c '^  dir #' <<< "$OUT")"

# --- T18 / T21: --dispatch -----------------------------------------------------------------------------------------
fx
git -C "$P" checkout -q -b elsewhere
cb "$P" "dir #801" --dispatch
check_status "T18 off the default branch → exit 3" 3 "$STATUS"
check_contains "T18 … G9" "$OUT" "refused: G9"
check_eq "T18 a G9 refusal leaves no dispatched row" "" "$(status_of 'dir #801')"
git -C "$P" checkout -q main
git -C "$P" push -q origin HEAD:refs/heads/claude/cloud-dir-801
cb "$P" "dir #801" --dispatch
check_status "T18 an existing origin claude/cloud-<slug> → exit 3" 3 "$STATUS"
check_contains "T18 … G9 names the branch" "$OUT" "origin already has claude/cloud-dir-801"
check_nofile "T18 no CLI call on a G9 refusal" "$CLAUDE_FX/calls"
fx
printf '{"default_branch":"dev%sx"}\n' "'" > "$GH_FX/api/repos_example_proj.json"
cb "$P" "dir #801"
check_status "T18 a default branch name with a shell character → exit 3" 3 "$STATUS"
check_contains "T18 … refused as G1, the name given" "$OUT" "refused: G1 — the default branch name 'dev'x'"
nothing_written "T18 default branch"
fx
printf '{"default_branch":"release+1"}\n' > "$GH_FX/api/repos_example_proj.json"
printf '{"protected":true,"protection":{"required_status_checks":{"enforcement_level":"everyone"}}}\n' \
  > "$GH_FX/api/repos_example_proj_branches_release+1.json"
cb "$P" "dir #801"
check_status "T18 a default branch named release+1 passes" 0 "$STATUS"
# A leading `+` is a forced refspec to `git fetch origin <default>` in the VM, a leading `-` an option.
for name in +release -release; do
  fx
  printf '{"default_branch":"%s"}\n' "$name" > "$GH_FX/api/repos_example_proj.json"
  printf '{"protected":true,"protection":{"required_status_checks":{"enforcement_level":"everyone"}}}\n' \
    > "$GH_FX/api/repos_example_proj_branches_${name}.json"
  cb "$P" "dir #801"
  check_status "T18 a default branch named $name → exit 3" 3 "$STATUS"
  check_contains "T18 … refused as G1, the name given" "$OUT" "refused: G1 — the default branch name '$name'"
done
fx
path_farm "$F/farm" script
PATH="$F/farm" cb "$P" "dir #801" --dispatch
check_status "T18 no \`script\` on PATH → exit 5" 5 "$STATUS"
check_eq "T18 … the row back to built" "built" "$(status_of 'dir #801')"
check_contains "T18 … the manual command named" "$OUT" "claude --cloud"
check_nofile "T18 … the CLI never ran" "$CLAUDE_FX/calls"
if [ -n "$HAVE_SCRIPT" ]; then
  fx
  cb "$P" "dir #801" --dispatch 3>&-
  check_status "T18 --dispatch → 0" 0 "$STATUS"
  # This pins the claim only where `script` hands its inherited fds to the CLI: BSD `script` (macOS) does, and
  # util-linux `script -qec` (verified on Linux: util-linux 2.39.3, dir #913) does too. A busybox `script` is unpinned.
  check_eq "T18 the CLI holds no fd 3 (the caller's stdout stays the receipt's)" "closed" "$(cat "$CLAUDE_FX/fd3-at-call")"
  check_eq "T18 the stub claude got --cloud first" "--cloud" "$(cat "$CLAUDE_FX/arg1")"
  check_eq "T18 … the brief text right after it" "$(cat "$CLOUD_BRIEF_DIR/example-proj--dir-801.md")" "$(cat "$CLAUDE_FX/brief")"
  check_eq "T18 … then --model and --effort" "--model sonnet --effort high" "$(cat "$CLAUDE_FX/rest")"
  check_eq "T18 … six arguments" "6" "$(cat "$CLAUDE_FX/argc")"
  check_eq "T18 … from the main checkout" "$(cd "$P" && pwd -P)" "$(cat "$CLAUDE_FX/cwd")"
  check_eq "T18 the row was already dispatched when the CLI ran" "dispatched" "$(awk -F'\t' '$3 == "dir #801" { print $8 }' "$CLAUDE_FX/ledger-at-call")"
  check_eq "T14b the CLI runs with no ledger.lock held" "free" "$(cat "$CLAUDE_FX/lock-at-call")"
  check_eq "T18 the row stays dispatched" "dispatched" "$(status_of 'dir #801')"
  check_contains "T18 the CLI's stdout is printed" "$OUT" "Created cloud session: Fixture"
  check_contains "T21 the claim text" "$OUT" "⏳ IN FLIGHT ($TODAY, branch claude/cloud-dir-801, cloud)"
  check_contains "T21 the heading with the claim appended, 📐 kept" "$OUT" "### dir #801 — eligible, verdict yes, with a spec — R4 — → pool — 📐 SPEC-READY — ⏳ IN FLIGHT ($TODAY, branch claude/cloud-dir-801, cloud)"
  # dir #913 (4): the session id is never written into the ticket (a Log line on a gitignored backlog was a bare
  # `session_<id>` no scan reads); it lives only in the local ledger row. The CLI's own output is printed above the claim.
  ticket_text="${OUT#*Claim — }"
  check_contains "T24 the claim and the Log line are printed" "$ticket_text" "Log: $TODAY — dispatched to a cloud session on claude/cloud-dir-801"
  check_absent "T24 the ticket text the tool prints carries no session id" "$ticket_text" "session_"
  check_eq "T24 the ledger row carries the session id" "session_01FIXTURE" "$(row_of 'dir #801' | cut -f15)"
  check_contains "T18 the landing command is printed" "$OUT" "tools/cloud-land.sh"
  cb "$P" "dir #801" --dispatch
  check_status "T18 a second dispatch without --redispatch → 3" 3 "$STATUS"
  rm -f "$CLAUDE_FX/calls"
  cb "$P" "dir #801" --dispatch --redispatch
  check_status "T18 --redispatch on a dispatched row → 0" 0 "$STATUS"
  check_eq "T18 … one row" "1" "$(row_of 'dir #801' | grep -c '')"
  check_file "T18 … and the CLI ran again" "$CLAUDE_FX/calls"
  fx
  printf '1' > "$CLAUDE_FX/exit"
  cb "$P" "dir #801" --dispatch
  check_status "T18 the CLI exits 1 → 5" 5 "$STATUS"
  check_contains "T18 … its stdout passed through" "$OUT" "stub stdout line"
  check_contains "T18 … its stderr passed through" "$OUT" "stub stderr line"
  check_eq "T18 … the row back to built" "built" "$(status_of 'dir #801')"
  check_absent "T18 … no claim printed" "$OUT" "IN FLIGHT"
  check_eq "T24 … no session id on the built row" "" "$(row_of 'dir #801' | cut -f15)"
  # dir #926: a CLI stopped on its folder-trust prompt, or on any prompt, is killed and the row goes back to built.
  fx
  printf 'trust' > "$CLAUDE_FX/mode"
  SECONDS=0
  cb "$P" "dir #801" --dispatch
  check_status "T18 a trust prompt → exit 5" 5 "$STATUS"
  check_contains "T18 … the remedy named" "$OUT" "run \`claude\` once in"
  check_contains "T18 … the answer to give" "$OUT" "Yes, I trust this folder"
  check_eq "T18 … the row back to built" "built" "$(status_of 'dir #801')"
  check_absent "T18 … no claim printed" "$OUT" "IN FLIGHT"
  check_eq "T18 … stopped within the bound" "yes" "$([ "$SECONDS" -lt 30 ] && echo yes || echo no)"
  fx
  printf 'hang' > "$CLAUDE_FX/mode"
  CLOUD_DISPATCH_TIMEOUT=2 cb "$P" "dir #801" --dispatch
  check_status "T18 a CLI that hangs on another prompt → exit 5" 5 "$STATUS"
  check_contains "T18 … the timeout named" "$OUT" "did not finish within 2s"
  check_eq "T18 … the row back to built" "built" "$(status_of 'dir #801')"
  fx
  sed 's#^docs/specs/$##; s#^BACKLOG.md$##' "$P/.gitignore" > "$F/gi"; cat "$F/gi" > "$P/.gitignore"
  cb "$P" "dir #801" --dispatch
  check_status "T18 a tracked backlog dispatches" 0 "$STATUS"
  check_absent "T24 a tracked backlog's ticket text carries no session id either" "${OUT#*Claim — }" "session_"
  check_eq "T24 … and the ledger row carries it" "session_01FIXTURE" "$(row_of 'dir #801' | cut -f15)"
  fx
  add_ticket '\n### dir #852 — a wrapped heading whose title runs\non — R4 — → pool\n\n**Cloud:** yes (2026-10-27, fixture)\n'
  cb "$P" "dir #852" --dispatch
  check_status "T21 a wrapped heading dispatches" 0 "$STATUS"
  check_contains "T21 the claim goes after the heading's last line" "$OUT" "
  on — R4 — → pool — ⏳ IN FLIGHT ($TODAY, branch claude/cloud-dir-852, cloud)"
  check_absent "T21 … not after its first line" "$OUT" "runs — ⏳"
else
  echo "  SKIP  T18/T21 dispatch cases: no \`script\` on this host (the CLI needs a pseudo-terminal)"
fi

# --- tools/lib/cloud.sh, directly ------------------------------------------------------------------------------
# shellcheck source=tools/lib/repo-top.sh
. "$REPO_ROOT/tools/lib/repo-top.sh"
# shellcheck source=tools/lib/safe-write.sh
. "$REPO_ROOT/tools/lib/safe-write.sh"
# shellcheck source=tools/lib/cloud.sh
. "$REPO_ROOT/tools/lib/cloud.sh"
for pair in "https://github.com/o/r=o/r" "https://github.com/o/r.git=o/r" "https://github.com/o/r/=o/r" \
            "git@github.com:o/r.git=o/r" "ssh://git@github.com/o/r.git=o/r" "https://gitlab.com/o/r=" \
            "https://github.com/o=" "https://github.com/o/r/x=" "/srv/o/r.git="; do
  url="${pair%=*}" want="${pair##*=}"
  check_eq "lib cloud_github_slug $url" "$want" "$(cloud_github_slug "$url" || true)"
done
L="$SANDBOX/lib-ledger/ledger.tsv"
cloud_ledger_init "$L"
check_eq "lib cloud_ledger_init writes the header" "$CLOUD_LEDGER_HEADER" "$(cat "$L")"
cloud_ledger_put "$L" o/r "dir #1" "$(printf 'd\to/r\tdir #1\tb\tm\t1\t?\tbuilt\t\t\t\t\t\t')"
cloud_ledger_put "$L" o/s "dir #1" "$(printf 'd\to/s\tdir #1\tb\tm\t1\t?\tbuilt\t\t\t\t\t\t')"
cloud_ledger_set "$L" o/r "dir #1" 8=landed 13=abc
check_eq "lib cloud_ledger_set changes only the keyed row" "landed abc|built " \
  "$(awk -F'\t' 'NR > 1 { printf "%s %s|", $8, $13 }' "$L" | sed 's/|$//')"
check_eq "lib … keeps an older 14-cell row at 14 cells" "14" "$(cloud_ledger_row "$L" o/r "dir #1" | awk -F'\t' '{print NF}')"
cloud_ledger_set "$L" o/r "dir #1" 15=session_01X
check_eq "lib cloud_ledger_set can set the 15th (session) cell of an older 14-cell row" "session_01X" \
  "$(cloud_ledger_cell "$(cloud_ledger_row "$L" o/r "dir #1")" 15)"
# cloud_gh_api (dir #913): rc 4 for a 404 or a 403 that is no rate limit, rc 2 for a rate limit (transient) or anything else.
fx
rl repos_example_proj "Forbidden" "X-RateLimit-Remaining: 4999"
cloud_gh_api repos/example/proj --jq .default_branch >/dev/null 2>&1; check_status "lib cloud_gh_api: a plain 403 → rc 4" 4 "$?"
rl repos_example_proj "Forbidden" "X-RateLimit-Remaining: 0"
cloud_gh_api repos/example/proj --jq .default_branch >/dev/null 2>&1; check_status "lib cloud_gh_api: a 403 with the remaining count at 0 → rc 2" 2 "$?"
rm -f "$GH_FX/api/repos_example_proj.403" "$GH_FX/api/repos_example_proj.403hdr"
cloud_gh_api repos/example/nothing >/dev/null 2>&1; check_status "lib cloud_gh_api: a 404 → rc 4" 4 "$?"
cloud_gh_api repos/example/proj --jq .default_branch >/dev/null 2>&1; check_status "lib cloud_gh_api: a readable endpoint → rc 0" 0 "$?"
cloud_cell_ok "a$(printf '\t')b"; check_status "lib cloud_cell_ok refuses a tab" 1 "$?"
mkdir -p "$SANDBOX/rel" && printf 'x\n' > "$SANDBOX/rel/list"
check_eq "lib cloud_personal_file makes a relative list absolute (the scanner runs from another directory)" \
  "$(cd "$SANDBOX/rel" && pwd)/list" \
  "$(cd "$SANDBOX/rel" && SECRET_SCAN_PERSONAL_FILE=list && cloud_personal_file && printf '%s' "$SECRET_SCAN_PERSONAL_FILE")"
(cd "$SANDBOX/rel" && SECRET_SCAN_PERSONAL_FILE=absent && cloud_personal_file)
check_status "lib cloud_personal_file refuses a missing list" 1 "$?"
# Keys compare as strings: `2.1` and `2.10`, `34` and `34.` are four tickets, not two.
L2="$SANDBOX/lib-ledger2/ledger.tsv"
cloud_ledger_init "$L2"
for t in 2.1 2.10 34 34.; do
  cloud_ledger_put "$L2" o/r "$t" "$(printf 'd\to/r\t%s\tb\tm\t1\t?\tbuilt-%s\t\t\t\t\t\t' "$t" "$t")"
done
check_eq "lib cloud_ledger_put keeps numerically-equal keys apart" "4" "$(tail -n +2 "$L2" | grep -c '')"
for t in 2.1 2.10 34 34.; do
  check_eq "lib cloud_ledger_row finds $t, not its numeric twin" "built-$t" "$(cloud_ledger_cell "$(cloud_ledger_row "$L2" o/r "$t")" 8)"
done
# A Latin-1 byte under a UTF-8 locale scans clean; a source that cannot be read is rc 2.
mkdir -p "$SANDBOX/scan" && printf 'caf\351\n' > "$SANDBOX/scan/latin1.txt"
mkdir -p "$SANDBOX/scan/w1" "$SANDBOX/scan/w2"
SECRET_SCAN_PERSONAL_FILE=/dev/null LC_ALL=en_US.UTF-8 cloud_scan_file "$REPO_ROOT/tools/secret-guard/secret-scan.sh" "$SANDBOX/scan/latin1.txt" "$SANDBOX/scan/w1" >/dev/null
check_status "lib cloud_scan_file on a Latin-1 byte under a UTF-8 locale → 0" 0 "$?"
SECRET_SCAN_PERSONAL_FILE=/dev/null cloud_scan_file "$REPO_ROOT/tools/secret-guard/secret-scan.sh" "$SANDBOX/scan/absent.txt" "$SANDBOX/scan/w2" >/dev/null 2>&1
check_status "lib cloud_scan_file on a missing source → 2" 2 "$?"
# A ledger that resolves into the Keel checkout is refused by init as by put.
fake_ck="$SANDBOX/fake-checkout"; mkdir -p "$fake_ck" "$SANDBOX/lib-ledger3"
ln -s "$fake_ck/ledger.tsv" "$SANDBOX/lib-ledger3/ledger.tsv"
saved_ck="$KEEL_SAFE_WRITE_CHECKOUT"; KEEL_SAFE_WRITE_CHECKOUT="$fake_ck"
cloud_ledger_init "$SANDBOX/lib-ledger3/ledger.tsv" 2>/dev/null
check_status "lib cloud_ledger_init refuses a ledger linked into the Keel checkout" 1 "$?"
check_nofile "lib … and writes nothing there" "$fake_ck/ledger.tsv"
KEEL_SAFE_WRITE_CHECKOUT="$saved_ck"
# A worktree of a bare repository: the main checkout falls back to the worktree's own top, not the given subdir.
git clone -q --bare "$P" "$SANDBOX/bare.git"
git -C "$SANDBOX/bare.git" worktree add -q "$SANDBOX/bwt" -b bx 2>/dev/null
mkdir -p "$SANDBOX/bwt/sub"
check_eq "lib cloud_resolve_main on a bare repo's worktree subdir → the worktree's top" \
  "$(cd "$SANDBOX/bwt" && pwd -P)" "$(cloud_resolve_main "$SANDBOX/bwt/sub" && printf '%s' "$MAIN")"

# --- T0 ----------------------------------------------------------------------------------------------------------
real_ledger_after="absent"; [ -f "$REAL_LEDGER" ] && real_ledger_after="$(cksum < "$REAL_LEDGER")"
check_eq "T0 the real ~/.keel/cloud/ledger.tsv untouched" "$real_ledger_before" "$real_ledger_after"

summary
