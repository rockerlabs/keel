- `tools/self/alpine-clone.sh` now mirrors the source's tags into the Alpine clone on every prepare, a reused
  clone included (dir #869). It fetched with `--no-tags`, so a reused clone kept a stale tag set and the local
  Alpine leg went falsely red on `tests/test_release_history.sh` and `tests/test_self_doctor.sh`. The explicit
  `+refs/tags/*:refs/tags/*` refspec with `--prune` also drops a tag the source deleted, which `--tags` would not.
