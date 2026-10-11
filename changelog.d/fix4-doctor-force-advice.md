- **`tools/doctor.sh`'s secret-guard advice names `--force` where the installer would refuse.** The body-exact installer
  (dir #683) refuses to replace a Keel-marked hook that was edited, so doctor's "re-run `install-secret-guard.sh --global`"
  and "re-vendor" advice looped on exit 3 for that one state (the 0.16.0 delta audit, S6-1). The machine-global stale and
  half-wired arms and the per-repo half-wired and stale arms now add `--force` and say the edited copy is saved as
  `<hook>.pre-keel.bak`, only when a hook there would be refused; the per-repo stale advice names the repo's path instead
  of `<this repo>`. A fixture runs each advised command as doctor prints it and checks the warning is gone. The
  `W-CORE-DRIFT` note-linked message now says bare `--with-git` exits 2 in a copy home and `--link --with-git` would
  migrate it (S6-2).
