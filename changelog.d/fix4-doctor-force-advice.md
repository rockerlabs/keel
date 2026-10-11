- **`tools/doctor.sh`'s secret-guard advice no longer loops on an edited Keel hook.** The body-exact installer
  (dir #683) refuses to replace a Keel-marked hook that was edited, yet doctor's stale and half-wired advice (machine-wide
  and per repo) told the user to re-run it plainly and got exit 3. Where the installer would refuse, the advice now adds
  `--force` and says the edited copy is saved as `<hook>.pre-keel.bak` (and to move an earlier waiting `.pre-keel.bak`
  aside first, which the installer refuses even with `--force`); a linked hook, or a hooks dir that is not Keel's own,
  gets no `--force`; the per-repo stale advice names the repo's path instead of `<this repo>`. A fixture runs each advised command as printed and checks the warning clears.
  The note-linked `W-CORE-DRIFT` message now says bare `--with-git` exits 2 in a copy home and `--link --with-git` would migrate it
  (the 0.16.0 delta audit, S6-1 and S6-2).
