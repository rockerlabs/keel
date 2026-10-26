- `doctor --install` now reports a missing or corrupt `tools/lib/ledger.sh` as a `G-REQUIRED-LIB` gap (dir #805).
  `install.sh` sources that lib only at its last step, so with it gone the audit used to say "install is complete"
  while `install.sh` did all its work and then exited 1. A census in `tests/test_doctor_guard_truth.sh` now fails
  when a lib that `install.sh` or `uninstall.sh` sources is neither checked nor sourced by `doctor --install`.
