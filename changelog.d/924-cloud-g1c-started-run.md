- `tools/cloud-brief.sh` G1c now also reads the latest run on the default branch and refuses a job that never started
  (no steps — an account billing block, an offline self-hosted runner), quoting its annotation; a self-hosted-only
  workflow also needs one online runner carrying its labels (a 403 on the runners endpoint warns, no run yet warns)
  (dir #924).
