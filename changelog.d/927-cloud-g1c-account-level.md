- `tools/cloud-brief.sh` G1c's started-run probe is now account-level for a private repository on hosted runners: it also
  reads the newest run of the owner's other private repositories (at most 10, read-only) and refuses when a newer sibling
  run never started a job (an account billing block), or passes with a stale-evidence warning when a later sibling run
  started after this repository's own not-started run; public repositories and self-hosted-only workflows are not probed
  (dir #927).
