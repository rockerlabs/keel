- `install-secret-guard.sh --where` and `--where --global` now report a Keel-marked hook whose body no shipped version
  has as `keel-modified` (`-link` suffixed) instead of `keel` (dir #791). `install.sh` Verify prints a WARN naming the
  edit and `--force` instead of `OK   secret-guard`, and `tools/doctor.sh` reads the new value; a script that compares the
  state with `= keel` sees a changed value for an edited hook.
