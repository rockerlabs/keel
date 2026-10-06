#!/usr/bin/env bash
# test_review_agent.sh — dir #413 slice 1 (A1): the shipped read-only review agent
# (agents/keel-polish-reviewer.md) keeps a STRUCTURAL tool floor. Its frontmatter `tools:` must be
# exactly `Read, Grep, Glob` on exactly one line, its frontmatter keys exactly {name, description, tools},
# and its body must not carry a copy of the Worker-rails block (polish.md's prompt still does — no new
# verbatim copy). One awk extractor reads the frontmatter only: tools/lib/agent-floor.sh, the same one
# tools/doctor.sh's W-REVIEW-AGENT-FLOOR uses, so a drift between the test's reader and the doctor's
# cannot hide. The extractor is also run on a good and a bad sample (the bad one is the shape of the
# KB's design-reviewer.md) and the floor assertion must reject the bad one.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

agent="$REPO_ROOT/agents/keel-polish-reviewer.md"
lib="$REPO_ROOT/tools/lib/agent-floor.sh"
check_file "agents/keel-polish-reviewer.md exists" "$agent"
check_file "tools/lib/agent-floor.sh exists" "$lib"
[ -f "$lib" ] || { summary; exit; }
# shellcheck source=tools/lib/agent-floor.sh
. "$lib"

# --- the shipped file ------------------------------------------------------------------------------
check_eq "name is keel-polish-reviewer" "keel-polish-reviewer" "$(agent_fm_value "$agent" name)"
check_eq "tools is exactly Read, Grep, Glob" "Read, Grep, Glob" "$(agent_fm_value "$agent" tools)"
check_eq "exactly one tools: line in the frontmatter" "1" "$(agent_fm_keys "$agent" | grep -cx tools)"
check_eq "key set is {description, name, tools}, each once" "description name tools" \
  "$(agent_fm_keys "$agent" | sort | tr '\n' ' ' | sed 's/ $//')"
run agent_floor_problem "$agent" "Read, Grep, Glob"
check_eq "the shipped file passes the floor assertion" "" "$OUT"
pin "body states the reviewer cannot run commands" "$agent" 'cannot run' \
  "the body must say the reviewer cannot run anything and must not claim to have"
check_eq "zero copies of the rails block" "0" \
  "$(grep -c 'You are read-only: no writes to the real repository' "$agent" || true)"
check_eq "the body is at most ~25 lines" "ok" \
  "$(awk 'f{n++} /^---$/{c++; if(c==2)f=1} END{print (n<=25 ? "ok" : "too long: " n)}' "$agent")"

# --- the extractor on a good and a bad sample ------------------------------------------------------
good="$SANDBOX/agent-good.md"; bad="$SANDBOX/agent-bad.md"
printf -- '---\nname: x\ndescription: d\ntools: Read, Grep, Glob\n---\nbody mentions tools: Bash, Write\n' > "$good"
printf -- '---\nname: x\ndescription: d\ntools: Read, Grep, Glob, Bash, Write\n---\nbody\n' > "$bad"
check_eq "extractor: good sample" "Read, Grep, Glob" "$(agent_fm_value "$good" tools)"
check_eq "extractor: bad sample (the design-reviewer shape)" "Read, Grep, Glob, Bash, Write" "$(agent_fm_value "$bad" tools)"
run agent_floor_problem "$good" "Read, Grep, Glob"
check_eq "floor assertion accepts the good sample" "" "$OUT"
run agent_floor_problem "$bad" "Read, Grep, Glob"
check_ne "floor assertion rejects the bad sample" "" "$OUT"

# --- every other way the floor can erode -----------------------------------------------------------
mk() { printf -- '---\nname: x\ndescription: d\n%s\n---\nbody\n' "$2" > "$SANDBOX/$1.md"; }
mk fl 'tools: [Read, Grep, Glob]';        run agent_floor_problem "$SANDBOX/fl.md" "Read, Grep, Glob"; check_ne "flow-list form is not the plain one-line form" "" "$OUT"
mk wf 'tools: Read, Grep, Glob, WebFetch'; run agent_floor_problem "$SANDBOX/wf.md" "Read, Grep, Glob"; check_ne "a tool outside the shipped set is flagged" "" "$OUT"
mk none 'model: haiku';                    run agent_floor_problem "$SANDBOX/none.md" "Read, Grep, Glob"; check_ne "no tools: line (grants every tool) is flagged" "" "$OUT"
printf -- '---\nname: x\ndescription: d\ntools: Read, Grep, Glob\ntools: Read, Grep, Glob\n---\nbody\n' > "$SANDBOX/two.md"
run agent_floor_problem "$SANDBOX/two.md" "Read, Grep, Glob"; check_ne "a second tools: line is flagged" "" "$OUT"
mk ag 'tools: Read, Grep, Glob, Agent';    run agent_floor_problem "$SANDBOX/ag.md" "Read, Grep, Glob"; check_ne "Agent in tools is flagged" "" "$OUT"
mk ro 'tools: Glob, Read, Grep';           run agent_floor_problem "$SANDBOX/ro.md" "Read, Grep, Glob"; check_eq "the same set in another order is accepted" "" "$OUT"
run agent_floor_problem "$SANDBOX/does-not-exist.md" "Read, Grep, Glob"; check_ne "a missing file is flagged" "" "$OUT"
summary
