- `/polish` step 3 now has a bounded fix-and-rerun loop for a red test run (dir #198), in the guide's § Step 3 and
  reached by a one-line trigger in the core. Ceiling 3 iterations, each fix folded into the tip commit by
  `--amend` and the `polish.3-tests` receipt written once, for the green run only. Exhaustion falls back to
  report-and-stop. A weakening guard stops the loop on any `tests/` edit while the `run.sh` leg is red, and on a
  `tests/` edit that is not shellcheck-flagged, net-shrinking, or more than one added `# shellcheck disable=`.
  The core's word budget rises from 3000 to 3020 words for the trigger.
