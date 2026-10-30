- The subagent git floor's reader half now has a checked-in mutation list, `tests/mutants/pre-pr-gate-subagent.tsv`
  (dir #790): 24 single-clause mutants of `check_subgit`, `sg_path` and `sg_cd`, swept with
  `tools/self/mutation-sweep.sh <list> tests/test_pre_pr_gate_subagent_floor.sh`. The sweep found eleven clauses
  nothing guarded; `tests/test_pre_pr_gate_subagent_floor.sh` now pins them (rows Y1-Y11).
